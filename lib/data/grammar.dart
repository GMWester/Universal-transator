import '../core/gz_asset.dart';
import 'languages.dart';

class GrammarParam {
  GrammarParam(Map<String, dynamic> j)
      : id = j['id'],
        source = j['src'],
        name = j['name'],
        area = j['area'] ?? '',
        group = j['grp'] ?? 'other',
        doc = j['doc'] ?? '',
        codes = Map<String, String>.from(j['codes'] ?? const {});
  final String id, source, name, area, group, doc;
  final Map<String, String> codes;

  String describe(String value) {
    final c = codes[value];
    if (source == 'grambank' && (value == '0' || value == '1') && codes.length <= 2) {
      return value == '1' ? 'Yes' : 'No';
    }
    return c ?? value;
  }
}

class GrammarExample {
  GrammarExample(List l)
      : text = l[0] ?? '',
        analyzed = l[1] ?? '',
        gloss = l[2] ?? '',
        translation = l[3] ?? '';
  final String text, analyzed, gloss, translation;
}

class GrammarRule {
  GrammarRule(this.param, this.value, this.examples);
  final GrammarParam param;
  final String value;
  final List<GrammarExample> examples;
  String get valueText => param.describe(value);
}

class GrammarDoc {
  GrammarDoc(Map j)
      : title = j['title'] ?? '',
        author = j['author'] ?? '',
        url = j['url'] ?? '',
        text = j['text'] ?? '';
  final String title, author, url, text;
}

class Comparison {
  Comparison(this.param, this.a, this.b);
  final GrammarParam param;
  final GrammarRule? a, b;
  bool get differs => a != null && b != null && a!.value != b!.value;
  bool get same => a != null && b != null && a!.value == b!.value;
}

/// Grammar rules of all languages from WALS (wals.info) and Grambank
/// (grambank.clld.org), bundled in the app.
class Grammar {
  static final instance = Grammar();

  final List<GrammarParam> params = [];
  final Map<String, int> _paramIndex = {};
  final Map<String, List<List>> _langs = {};
  final Map<String, List> _examples = {};
  Map<String, String> groups = {};
  Map<String, GrammarDoc>? _docs;
  bool loaded = false;

  Future<void> init() async {
    final j = await loadGzJsonAsset('assets/data/grammar.json.gz') as Map;
    for (final p in j['params'] as List) {
      _paramIndex[p['id']] = params.length;
      params.add(GrammarParam(Map<String, dynamic>.from(p)));
    }
    (j['langs'] as Map).forEach((k, v) => _langs[k as String] = List<List>.from(v));
    (j['examples'] as Map).forEach((k, v) => _examples[k as String] = v as List);
    groups = Map<String, String>.from(j['groups'] ?? const {});
    loaded = true;
  }

  Future<GrammarDoc?> doc(String key) async {
    _docs ??= ((await loadGzJsonAsset('assets/data/grammar_docs.json.gz')) as Map)
        .map((k, v) => MapEntry(k as String, GrammarDoc(v as Map)));
    return _docs![key];
  }

  String? _gc(String code) => LanguageRepository.instance.byCode(code)?.glottocode;

  bool hasData(String code) => _langs.containsKey(_gc(code));

  Set<String> get languagesWithData {
    final out = <String>{};
    for (final l in LanguageRepository.instance.all) {
      if (l.glottocode != null && _langs.containsKey(l.glottocode)) out.add(l.code);
    }
    return out;
  }

  List<GrammarRule> rules(String code) {
    final rows = _langs[_gc(code)];
    if (rows == null) return const [];
    return [
      for (final r in rows)
        GrammarRule(params[r[0] as int], '${r[1]}', [
          if (r.length > 2)
            for (final x in r[2] as List)
              if (_examples[x] != null) GrammarExample(_examples[x]!)
        ])
    ];
  }

  String? valueOf(String code, String paramId) {
    final i = _paramIndex[paramId];
    final rows = _langs[_gc(code)];
    if (i == null || rows == null) return null;
    for (final r in rows) {
      if (r[0] == i) return '${r[1]}';
    }
    return null;
  }

  List<Comparison> compare(String a, String b) {
    final ra = {for (final r in rules(a)) r.param.id: r};
    final rb = {for (final r in rules(b)) r.param.id: r};
    final out = <Comparison>[];
    for (final p in params) {
      if (ra.containsKey(p.id) || rb.containsKey(p.id)) {
        out.add(Comparison(p, ra[p.id], rb[p.id]));
      }
    }
    return out;
  }
}
