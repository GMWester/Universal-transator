import 'package:flutter/foundation.dart';

import '../core/gz_asset.dart';
import 'normalize.dart';

class Language {
  Language({
    required this.code,
    required this.englishName,
    this.glottocode,
    this.iso3,
    this.family,
    this.area,
    this.wals,
    this.scripts = const [],
  });

  factory Language.fromJson(Map<String, dynamic> j) => Language(
        code: j['c'],
        englishName: j['n'],
        glottocode: j['g'],
        iso3: j['i'],
        family: j['f'],
        area: j['a'],
        wals: j['w'],
        scripts: List<String>.from(j['s'] ?? const []),
      );

  final String code;
  String englishName;
  final String? glottocode, iso3, family, area, wals;
  List<String> scripts;
}

class UiLocale {
  UiLocale(this.code, this.ownName, this.count);
  final String code, ownName;
  final int count;
}

/// All languages (Glottolog + CLDR + Wiktionary), with names shown in the
/// language the user chose for the app.
class LanguageRepository extends ChangeNotifier {
  static final instance = LanguageRepository();

  final Map<String, Language> _byCode = {};
  final Map<String, Language> _byIso3 = {};
  List<UiLocale> uiLocales = [];
  Map<String, String> _names = {};
  Map<String, String> _parentNames = {};
  String _locale = 'en';
  List<Language>? _sorted;

  String get locale => _locale;
  Iterable<Language> get all => _byCode.values;

  Future<void> init(String locale) async {
    final list = await loadGzJsonAsset('assets/data/languages.json.gz') as List;
    for (final j in list) {
      final l = Language.fromJson(Map<String, dynamic>.from(j));
      _byCode[l.code] = l;
      if (l.iso3 != null) _byIso3[l.iso3!] = l;
    }
    final idx = await loadGzJsonAsset('assets/data/names_index.json.gz') as List;
    uiLocales = [for (final j in idx) UiLocale(j['c'], j['own'] ?? j['c'], j['count'] ?? 0)]
      ..sort((a, b) => foldKey(a.ownName).compareTo(foldKey(b.ownName)));
    await setLocale(locale);
  }

  /// Adds languages that only appear in downloaded Wiktionary packs.
  void addFromPacks(Map<String, String> codeToEnglishName) {
    var changed = false;
    codeToEnglishName.forEach((code, name) {
      if (!_byCode.containsKey(code)) {
        _byCode[code] = Language(code: code, englishName: name);
        changed = true;
      }
    });
    if (changed) {
      _sorted = null;
      notifyListeners();
    }
  }

  String _resolveLocale(String loc) {
    final codes = uiLocales.map((e) => e.code).toSet();
    if (codes.contains(loc)) return loc;
    final base = loc.split(RegExp('[-_]')).first;
    return codes.contains(base) ? base : 'en';
  }

  Future<void> setLocale(String loc) async {
    final r = _resolveLocale(loc);
    Future<Map<String, String>> fetch(String c) async {
      try {
        final m = await loadGzJsonAsset('assets/data/names/$c.json.gz') as Map;
        return m.map((k, v) => MapEntry(k as String, v as String));
      } catch (_) {
        return const <String, String>{};
      }
    }

    _names = await fetch(r);
    _parentNames = r.contains('-') ? await fetch(r.split('-').first) : {};
    _locale = r;
    _sorted = null;
    notifyListeners();
  }

  Language? byCode(String code) => _byCode[code] ?? _byIso3[code];

  /// Name of a language written in the app language (falls back to English).
  String name(String code) {
    final n = _names[code] ?? _parentNames[code];
    if (n != null) return n;
    final l = byCode(code);
    if (l != null) {
      final viaIso = _names[l.code] ?? _parentNames[l.code];
      return viaIso ?? l.englishName;
    }
    return code;
  }

  /// Name of a language written in that language itself (autonym), if known.
  String? autonym(String code) {
    for (final u in uiLocales) {
      if (u.code == code) return u.ownName;
    }
    return null;
  }

  List<Language> sorted() => _sorted ??= (_byCode.values.toList()
    ..sort((a, b) => foldKey(name(a.code)).compareTo(foldKey(name(b.code)))));

  bool hasLocalizedName(String code) => _names.containsKey(code) || _parentNames.containsKey(code);

  /// Search by name in the app language, English name, autonym or code.
  /// Major languages (those with a CLDR name) and exact matches rank first.
  List<Language> search(String q, {Set<String>? restrictTo}) {
    final base = restrictTo == null
        ? sorted()
        : sorted().where((l) => restrictTo.contains(l.code)).toList();
    if (q.trim().isEmpty) return base;
    final k = foldKey(q.trim());
    final scored = <MapEntry<Language, int>>[];
    for (final l in base) {
      final local = foldKey(name(l.code));
      final eng = foldKey(l.englishName);
      final auto = autonym(l.code);
      final names = [local, eng, if (auto != null) foldKey(auto)];
      int? sc;
      if (names.contains(k) || l.code == k || l.iso3 == k) {
        sc = 0;
      } else if (names.any((n) => n.startsWith(k))) {
        sc = 2;
      } else if (names.any((n) => n.split(RegExp(r'[\s\-(]')).any((w) => w.startsWith(k)))) {
        sc = 4;
      } else if (l.code.startsWith(k) || (l.iso3?.startsWith(k) ?? false)) {
        sc = 6;
      } else if (names.any((n) => n.contains(k))) {
        sc = 8;
      }
      if (sc == null) continue;
      if (!hasLocalizedName(l.code)) sc += 1; // minor languages after major ones
      scored.add(MapEntry(l, sc));
    }
    scored.sort((a, b) => a.value.compareTo(b.value));
    return [for (final e in scored) e.key];
  }
}
