import '../core/gz_asset.dart';
import 'languages.dart';

class CharGroup {
  CharGroup(this.title, this.chars);
  final String title;
  final List<String> chars;
}

class ScriptInfo {
  ScriptInfo(this.code, this.name, this.ranges);
  final String code, name;
  final List<List<int>> ranges;
  int get count => ranges.fold(0, (n, r) => n + r[1] - r[0] + 1);
  Iterable<String> chars() sync* {
    for (final r in ranges) {
      for (var c = r[0]; c <= r[1]; c++) {
        yield String.fromCharCode(c);
      }
    }
  }
}

/// Character inventories: CLDR exemplar sets per language and every Unicode
/// character of each script.
class Characters {
  static final instance = Characters();

  final Map<String, ScriptInfo> scripts = {};
  final Map<String, Map<String, String>> _exemplars = {};
  Map<int, String>? _names;
  String unicodeVersion = '';

  Future<void> init() async {
    final j = await loadGzJsonAsset('assets/data/characters.json.gz') as Map;
    (j['scripts'] as Map).forEach((k, v) {
      scripts[k as String] = ScriptInfo(
          k, v['n'] as String, [for (final r in v['r'] as List) [r[0] as int, r[1] as int]]);
    });
    (j['exemplars'] as Map).forEach((k, v) => _exemplars[k as String] = Map<String, String>.from(v));
    unicodeVersion = j['unicode'] ?? '';
  }

  Future<String?> charName(int cp) async {
    _names ??= ((await loadGzJsonAsset('assets/data/char_names.json.gz')) as Map)
        .map((k, v) => MapEntry(int.parse(k as String, radix: 16), v as String));
    final n = _names![cp];
    if (n != null) return n;
    if ((cp >= 0x4E00 && cp <= 0x9FFF) || (cp >= 0x3400 && cp <= 0x4DBF) || (cp >= 0x20000 && cp <= 0x3134F)) {
      return 'CJK UNIFIED IDEOGRAPH-${cp.toRadixString(16).toUpperCase()}';
    }
    if (cp >= 0xAC00 && cp <= 0xD7A3) return 'HANGUL SYLLABLE';
    return null;
  }

  bool hasExemplars(String code) => _exemplars.containsKey(code);

  /// Parses a CLDR UnicodeSet like "[a b c {ch} d-f]".
  static List<String> parseSet(String s) {
    var t = s.trim();
    if (t.startsWith('[')) t = t.substring(1);
    if (t.endsWith(']')) t = t.substring(0, t.length - 1);
    final out = <String>[];
    final runes = t.runes.toList();
    var i = 0;
    while (i < runes.length) {
      final c = runes[i];
      if (c == 0x20) {
        i++;
        continue;
      }
      if (c == 0x7B) {
        // {multi}
        final end = runes.indexOf(0x7D, i);
        if (end < 0) break;
        out.add(String.fromCharCodes(runes.sublist(i + 1, end)));
        i = end + 1;
        continue;
      }
      var ch = c;
      if (c == 0x5C && i + 1 < runes.length) {
        // escape
        if (runes[i + 1] == 0x75 && i + 5 < runes.length) {
          ch = int.parse(String.fromCharCodes(runes.sublist(i + 2, i + 6)), radix: 16);
          i += 6;
        } else {
          ch = runes[i + 1];
          i += 2;
        }
      } else {
        i++;
      }
      // combining marks attach to the previous character
      if (out.isNotEmpty && _isMark(ch)) {
        out[out.length - 1] += String.fromCharCode(ch);
        continue;
      }
      if (i + 1 < runes.length && runes[i] == 0x2D && runes[i + 1] != 0x20) {
        final endCh = runes[i + 1];
        for (var x = ch; x <= endCh && x - ch < 5000; x++) {
          out.add(String.fromCharCode(x));
        }
        i += 2;
        continue;
      }
      out.add(String.fromCharCode(ch));
    }
    return out;
  }

  static bool _isMark(int c) =>
      (c >= 0x0300 && c <= 0x036F) || (c >= 0x0591 && c <= 0x05C7) || (c >= 0x064B && c <= 0x065F) ||
      (c >= 0x0900 && c <= 0x0DFF && ((c & 0x7F) >= 0x3A && (c & 0x7F) <= 0x4F)) ||
      (c >= 0x0E31 && c <= 0x0E3A) || (c >= 0x0E47 && c <= 0x0E4E);

  /// Groups for a language: CLDR alphabet sets, frequent characters seen in
  /// its Wiktionary words, and its scripts.
  List<CharGroup> groupsFor(String code, {String? packChars}) {
    final out = <CharGroup>[];
    final ex = _exemplars[code] ?? _exemplars[code.split('-').first];
    if (ex != null) {
      const titles = {
        'exemplarCharacters': 'Alphabet',
        'index': 'Capital letters / index',
        'auxiliary': 'Additional letters (loanwords, names)',
        'numbers': 'Numbers',
        'punctuation': 'Punctuation',
      };
      for (final k in titles.keys) {
        final v = ex[k];
        if (v != null && v.isNotEmpty) out.add(CharGroup(titles[k]!, parseSet(v)));
      }
    }
    if (packChars != null && packChars.isNotEmpty && ex == null) {
      final chars = packChars.runes.map(String.fromCharCode).where((c) => c.trim().isNotEmpty).toList();
      out.add(CharGroup('Letters used in the dictionary', chars));
    }
    return out;
  }

  static const _alias = {
    'Hans': ['Hani'], 'Hant': ['Hani'], 'Jpan': ['Hira', 'Kana', 'Hani'],
    'Kore': ['Hang', 'Hani'], 'Hrkt': ['Hira', 'Kana'], 'Aran': ['Arab'], 'Syre': ['Syrc'],
    'Syrj': ['Syrc'], 'Syrn': ['Syrc'], 'Latf': ['Latn'], 'Latg': ['Latn'], 'Cyrs': ['Cyrl'],
  };

  List<ScriptInfo> scriptsFor(Language? l) {
    final out = <String>[];
    for (final s in l?.scripts ?? const <String>[]) {
      for (final x in _alias[s] ?? [s]) {
        if (scripts[x] != null && !out.contains(x)) out.add(x);
      }
    }
    return [for (final s in out) scripts[s]!];
  }
}
