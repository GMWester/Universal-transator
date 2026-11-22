import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';

import '../core/config.dart';
import '../core/paths.dart';
import 'downloads.dart';
import 'languages.dart';

class PackInfo {
  PackInfo(this.edition, Map<String, dynamic> j)
      : file = j['file'],
        size = j['size'] ?? 0,
        unpacked = j['unpacked'] ?? 0,
        sha256 = j['sha256'] ?? '',
        langs = (j['langs'] as Map).map((k, v) =>
            MapEntry(k as String, (v['n'] ?? k) as String)),
        entries = (j['langs'] as Map).map((k, v) =>
            MapEntry(k as String, (v['e'] ?? 0) as int));
  final String edition, file, sha256;
  final int size, unpacked;
  final Map<String, String> langs;
  final Map<String, int> entries;
  String get id => file.replaceAll('.sqlite.gz', '');
}

class DownloadState {
  DownloadState(this.label);
  final String label;
  final CancelToken cancel = CancelToken();
  int received = 0, total = 0;
  String? error;
  double? get fraction => total > 0 ? received / total : null;
}

/// Anything that can give the open database holding a language.
abstract class PackSource {
  Database? dbFor(String lang, {String edition = 'en'});
}

/// Downloads and opens Wiktionary language packs. Once downloaded, a pack is
/// used fully offline.
class PackManager extends ChangeNotifier implements PackSource {
  static final instance = PackManager();

  /// edition -> manifest packs (cached on disk so the list works offline)
  final Map<String, List<PackInfo>> manifests = {};
  final Map<String, DownloadState> active = {};
  final Map<String, Database> _open = {};
  Map<String, dynamic> _installed = {}; // packId -> {edition, langs:{code:name}}
  /// Packs shipped inside a "full" installer: packId -> {edition, langs, size, path}
  final Map<String, dynamic> _bundled = {};

  Map<String, dynamic> get _entries => {..._installed, ..._bundled};

  bool isBundled(String packId) => _bundled.containsKey(packId);

  File get _installedFile => File('${AppPaths.instance.packsDir.path}${Platform.pathSeparator}installed.json');
  File _manifestCache(String ed) =>
      File('${AppPaths.instance.packsDir.path}${Platform.pathSeparator}manifest-$ed.json');
  String _dbPath(String packId) => _bundled[packId]?['path'] as String? ??
      '${AppPaths.instance.packsDir.path}${Platform.pathSeparator}$packId.sqlite';

  Future<void> init() async {
    try {
      if (await _installedFile.exists()) {
        _installed = jsonDecode(await _installedFile.readAsString());
      }
    } catch (_) {
      _installed = {};
    }
    final b = AppPaths.instance.bundledDataDir;
    if (b != null) {
      try {
        final sep = Platform.pathSeparator;
        final j = jsonDecode(await File('${b.path}${sep}bundled.json').readAsString()) as Map;
        j.forEach((id, v) {
          final path = '${b.path}${sep}packs$sep$id.sqlite';
          if (File(path).existsSync()) _bundled[id as String] = {...Map<String, dynamic>.from(v), 'path': path};
        });
      } catch (_) {}
    }
    for (final ed in AppConfig.instance.dataEditions) {
      final f = _manifestCache(ed);
      if (await f.exists()) {
        try {
          _parseManifest(ed, jsonDecode(await f.readAsString()));
        } catch (_) {}
      }
    }
    _registerLanguages();
  }

  void _parseManifest(String ed, Map<String, dynamic> j) {
    manifests[ed] = [for (final p in j['packs'] as List) PackInfo(ed, Map<String, dynamic>.from(p))];
  }

  void _registerLanguages() {
    final names = <String, String>{};
    for (final v in _entries.values) {
      (v['langs'] as Map).forEach((k, n) => names[k as String] = n as String);
    }
    final en = manifests['en'];
    if (en != null) {
      for (final p in en) {
        names.addAll(p.langs);
      }
    }
    LanguageRepository.instance.addFromPacks(names);
  }

  /// Fetches the pack list for [edition] from the data release.
  Future<void> refresh(String edition) async {
    final j = await getJson(AppConfig.instance.dataAssetUrl(edition, 'manifest-$edition.json'));
    await _manifestCache(edition).writeAsString(jsonEncode(j));
    _parseManifest(edition, Map<String, dynamic>.from(j));
    _registerLanguages();
    notifyListeners();
  }

  bool isInstalled(String packId) =>
      _entries.containsKey(packId) && File(_dbPath(packId)).existsSync();

  Iterable<String> get installedIds => _entries.keys.where(isInstalled);

  /// Languages with an installed pack for [edition].
  Set<String> installedLanguages([String edition = 'en']) => {
        for (final e in _entries.entries)
          if (e.value['edition'] == edition && isInstalled(e.key))
            ...(e.value['langs'] as Map).keys.cast<String>()
      };

  PackInfo? packFor(String edition, String lang) {
    for (final p in manifests[edition] ?? const <PackInfo>[]) {
      if (p.langs.containsKey(lang)) return p;
    }
    return null;
  }

  DateTime _lastNotify = DateTime.fromMillisecondsSinceEpoch(0);

  /// Download progress arrives for every network chunk; redraw at most ~6x/s.
  void _notifyProgress() {
    final now = DateTime.now();
    if (now.difference(_lastNotify).inMilliseconds >= 160) {
      _lastNotify = now;
      notifyListeners();
    }
  }

  /// Deletes a file, ignoring errors (Windows can keep a file locked for a
  /// moment, e.g. by antivirus scanning).
  static Future<void> _tryDelete(File f) async {
    for (var i = 0; i < 5; i++) {
      try {
        if (await f.exists()) await f.delete();
        return;
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }
  }

  // installed.json is written by several parallel downloads: one at a time.
  Future<void> _saveChain = Future.value();
  Future<void> _saveInstalled() {
    final next = _saveChain.then((_) async {
      final data = jsonEncode(_installed);
      for (var i = 0; i < 5; i++) {
        try {
          final tmp = File('${_installedFile.path}.tmp');
          await tmp.writeAsString(data, flush: true);
          if (await _installedFile.exists()) await _installedFile.delete();
          await tmp.rename(_installedFile.path);
          return;
        } catch (_) {
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }
    });
    _saveChain = next.catchError((_) {});
    return _saveChain;
  }

  /// Packs whose last download failed: packId -> error (shown until retried).
  final Map<String, String> failed = {};

  /// Downloads and unpacks one pack, retrying up to 3 times. Never throws.
  Future<bool> install(PackInfo p) async {
    if (active.containsKey(p.id)) return false;
    final st = active[p.id] = DownloadState(p.file);
    failed.remove(p.id);
    notifyListeners();
    final gz = File('${AppPaths.instance.packsDir.path}${Platform.pathSeparator}${p.file}');
    Object? lastError;
    for (var attempt = 1; attempt <= 3 && !st.cancel.cancelled; attempt++) {
      try {
        st.received = 0;
        await downloadFile(AppConfig.instance.dataAssetUrl(p.edition, p.file), gz,
            sha256Hex: p.sha256, cancel: st.cancel, onProgress: (r, t) {
          st.received = r;
          st.total = t == 0 ? p.size : t;
          _notifyProgress();
        });
        if (st.cancel.cancelled) throw DownloadCancelled();
        _close(p.id);
        await gunzipFile(gz, File(_dbPath(p.id)));
        await _tryDelete(gz);
        _installed[p.id] = {'edition': p.edition, 'langs': p.langs, 'size': p.unpacked};
        await _saveInstalled();
        active.remove(p.id);
        _registerLanguages();
        notifyListeners();
        return true;
      } on DownloadCancelled {
        break;
      } catch (e) {
        lastError = e;
        await _tryDelete(gz);
        if (attempt < 3) await Future.delayed(Duration(seconds: attempt * 3));
      }
    }
    active.remove(p.id);
    await _tryDelete(gz);
    if (!st.cancel.cancelled && lastError != null) failed[p.id] = _friendly(lastError);
    notifyListeners();
    return false;
  }

  static String _friendly(Object e) {
    final s = '$e';
    if (s.contains('No space') || s.contains('ENOSPC') || s.contains('not enough space') ||
        s.contains('errno = 112') || s.contains('errno = 28')) {
      return 'Not enough free disk space';
    }
    return s.length > 160 ? '${s.substring(0, 160)}…' : s;
  }

  /// Downloads several packs, three at a time (the in-app data picker).
  /// One failing pack never stops the others; failed packs can be retried.
  bool bulkRunning = false;
  int bulkTotal = 0, bulkDone = 0, bulkFailed = 0;
  Future<void> installAll(Iterable<PackInfo> list) async {
    if (bulkRunning) return;
    final queue = list.where((p) => !isInstalled(p.id)).toList();
    bulkRunning = true;
    bulkTotal = queue.length;
    bulkDone = 0;
    bulkFailed = 0;
    notifyListeners();
    Future<void> worker() async {
      while (bulkRunning && queue.isNotEmpty) {
        final p = queue.removeAt(0);
        bool ok;
        try {
          ok = await install(p);
        } catch (e) {
          ok = false;
          failed[p.id] = _friendly(e);
        }
        if (ok) {
          bulkDone++;
        } else if (failed.containsKey(p.id)) {
          bulkFailed++;
        }
        notifyListeners();
      }
    }

    try {
      await Future.wait([worker(), worker(), worker()]);
    } finally {
      bulkRunning = false;
      notifyListeners();
    }
  }

  /// Packs (of [edition]) whose download failed.
  List<PackInfo> failedPacks(String edition) =>
      [for (final p in manifests[edition] ?? const <PackInfo>[]) if (failed.containsKey(p.id)) p];

  /// Stops one download.
  void cancel(String packId) => active[packId]?.cancel.cancel();

  /// Stops the queue and every running download.
  void cancelBulk() {
    bulkRunning = false;
    for (final s in active.values.toList()) {
      s.cancel.cancel();
    }
    notifyListeners();
  }

  Future<void> installLanguage(String lang, {String edition = 'en'}) async {
    var p = packFor(edition, lang);
    if (p == null) {
      await refresh(edition);
      p = packFor(edition, lang);
    }
    if (p == null) throw StateError('No $edition Wiktionary data for "$lang"');
    await install(p);
  }

  Future<void> remove(String packId) async {
    if (isBundled(packId)) return; // part of the installer
    _close(packId);
    final f = File(_dbPath(packId));
    if (await f.exists()) await f.delete();
    _installed.remove(packId);
    await _saveInstalled();
    notifyListeners();
  }

  void _close(String id) {
    _open.remove(id)?.dispose();
  }

  /// Open database of the installed pack holding [lang] in [edition].
  @override
  Database? dbFor(String lang, {String edition = 'en'}) {
    for (final e in _entries.entries) {
      if (e.value['edition'] == edition && (e.value['langs'] as Map).containsKey(lang)) {
        return _db(e.key);
      }
    }
    return null;
  }

  /// All open databases for an edition (for cross-pack queries).
  Iterable<Database> dbsForEdition(String edition) sync* {
    for (final e in _entries.entries) {
      if (e.value['edition'] == edition) {
        final d = _db(e.key);
        if (d != null) yield d;
      }
    }
  }

  Database? _db(String id) {
    if (_open[id] != null) return _open[id];
    final path = _dbPath(id);
    if (!File(path).existsSync()) return null;
    return _open[id] = sqlite3.open(path, mode: OpenMode.readOnly);
  }

  int get installedBytes {
    var n = 0;
    for (final id in installedIds) {
      try {
        n += File(_dbPath(id)).lengthSync();
      } catch (_) {}
    }
    return n;
  }
}
