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

  Future<void> install(PackInfo p) async {
    if (active.containsKey(p.id)) return;
    final st = active[p.id] = DownloadState(p.file);
    notifyListeners();
    final gz = File('${AppPaths.instance.packsDir.path}${Platform.pathSeparator}${p.file}');
    try {
      await downloadFile(AppConfig.instance.dataAssetUrl(p.edition, p.file), gz, sha256Hex: p.sha256,
          onProgress: (r, t) {
        st.received = r;
        st.total = t == 0 ? p.size : t;
        _notifyProgress();
      });
      _close(p.id);
      await gunzipFile(gz, File(_dbPath(p.id)));
      await gz.delete();
      _installed[p.id] = {'edition': p.edition, 'langs': p.langs, 'size': p.unpacked};
      await _installedFile.writeAsString(jsonEncode(_installed));
      active.remove(p.id);
      _registerLanguages();
    } catch (e) {
      st.error = '$e';
      if (await gz.exists()) await gz.delete();
      Future.delayed(const Duration(seconds: 8), () {
        active.remove(p.id);
        notifyListeners();
      });
    }
    notifyListeners();
  }

  /// Downloads several packs one after another (the in-app data picker).
  bool bulkRunning = false;
  Future<void> installAll(Iterable<PackInfo> list) async {
    if (bulkRunning) return;
    bulkRunning = true;
    notifyListeners();
    try {
      // Three downloads at a time: GitHub limits the speed per connection.
      final queue = list.where((p) => !isInstalled(p.id)).toList();
      Future<void> worker() async {
        while (bulkRunning && queue.isNotEmpty) {
          await install(queue.removeAt(0));
        }
      }

      await Future.wait([worker(), worker(), worker()]);
    } finally {
      bulkRunning = false;
      notifyListeners();
    }
  }

  void cancelBulk() {
    bulkRunning = false;
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
    await _installedFile.writeAsString(jsonEncode(_installed));
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
