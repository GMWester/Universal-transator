import 'package:flutter/foundation.dart';

import '../core/config.dart';
import '../core/settings.dart';
import '../data/dictionary.dart';
import '../data/grammar.dart';
import 'nmt.dart';

class TranslationResult {
  TranslationResult(this.text, this.method, {this.notes = const []});
  final String text;
  final String method; // 'neural' | 'dictionary'
  final List<String> notes;
}

/// Sentence translation: the neural model when it knows both languages,
/// otherwise a Wiktionary word-by-word translation re-ordered with the target
/// language's word-order rules (WALS).
class Translator extends ChangeNotifier {
  Translator(this.dict, this.grammar, this.settings);
  final Dictionary dict;
  final Grammar grammar;
  final Settings settings;
  NmtModel? _model;
  String? _loadedId;
  bool loading = false;
  String? loadError;

  ModelSpec? get activeSpec {
    final id = settings.translationModel;
    for (final m in AppConfig.instance.models) {
      if (m.id == id && NmtModel.isInstalled(m)) return m;
    }
    for (final m in AppConfig.instance.models) {
      if (NmtModel.isInstalled(m)) return m;
    }
    return null;
  }

  Future<NmtModel?> model() async {
    final spec = activeSpec;
    if (spec == null) return null;
    if (_model != null && _loadedId == spec.id) return _model;
    loading = true;
    loadError = null;
    notifyListeners();
    try {
      await _model?.close();
      _model = await NmtModel.load(spec);
      _loadedId = spec.id;
    } catch (e) {
      loadError = '$e';
      _model = null;
    } finally {
      loading = false;
      notifyListeners();
    }
    return _model;
  }

  Future<void> unload() async {
    await _model?.close();
    _model = null;
    _loadedId = null;
  }

  Future<TranslationResult> translate(String text, String from, String to) async {
    if (text.trim().isEmpty) return TranslationResult('', 'none');
    if (from == to) return TranslationResult(text, 'none');
    final m = await model();
    if (m != null && m.langToken(from) != null && m.langToken(to) != null) {
      final t = await m.translate(text, from, to);
      return TranslationResult(t, 'neural', notes: ['${m.spec.name} • offline']);
    }
    return _dictionaryTranslate(text, from, to);
  }

  TranslationResult _dictionaryTranslate(String text, String from, String to) {
    final notes = <String>[];
    if (dict.db(from) == null) notes.add('missing:$from');
    if (to != 'en' && dict.db(to) == null) notes.add('missing:$to');
    final tokenRe = RegExp(r"[\p{L}\p{M}\p{N}'’\-]+|[^\s\p{L}\p{M}\p{N}]+", unicode: true);
    final sentences = <String>[];
    for (final sentence in NmtModel.splitSentences(text)) {
      final words = <_W>[];
      for (final m in tokenRe.allMatches(sentence)) {
        final tok = m.group(0)!;
        if (!RegExp(r'\p{L}', unicode: true).hasMatch(tok)) {
          words.add(_W(tok, tok, 'punct'));
          continue;
        }
        final groups = dict.translateWord(from, to, tok);
        final entries = dict.lookup(from, tok);
        final pos = entries.isNotEmpty ? entries.first.pos : '';
        if (groups.isNotEmpty && groups.first.targets.isNotEmpty) {
          words.add(_W(tok, groups.first.targets.first.word, pos));
        } else {
          words.add(_W(tok, tok, pos));
        }
      }
      sentences.add(_reorder(words, from, to).map((w) => w.out).join(' ')
          .replaceAll(RegExp(r' ([.,!?;:])'), r'$1'));
    }
    notes.add('approximate');
    return TranslationResult(sentences.join(' '), 'dictionary', notes: notes);
  }

  List<_W> _reorder(List<_W> w, String from, String to) {
    final fa = grammar.valueOf(from, '87A'), ta = grammar.valueOf(to, '87A');
    // 87A: 1 = Adjective-Noun, 2 = Noun-Adjective
    if (fa != null && ta != null && fa != ta && (fa == '1' || fa == '2') && (ta == '1' || ta == '2')) {
      for (var i = 0; i + 1 < w.length; i++) {
        final a = w[i], b = w[i + 1];
        final first = fa == '1' ? 'adj' : 'noun', second = fa == '1' ? 'noun' : 'adj';
        if (a.pos == first && b.pos == second) {
          w[i] = b;
          w[i + 1] = a;
          i++;
        }
      }
    }
    final fo = grammar.valueOf(from, '81A'), tord = grammar.valueOf(to, '81A');
    // 81A: 1 SOV, 2 SVO, 3 VSO
    if (fo == '2' && tord == '1') {
      final vi = w.indexWhere((x) => x.pos == 'verb');
      final end = w.lastIndexWhere((x) => x.pos != 'punct');
      if (vi >= 0 && end > vi) {
        final v = w.removeAt(vi);
        w.insert(end, v);
      }
    } else if (fo == '1' && tord == '2') {
      final vi = w.lastIndexWhere((x) => x.pos == 'verb');
      final subjEnd = w.indexWhere((x) => x.pos == 'noun' || x.pos == 'pron');
      if (vi > subjEnd + 1 && subjEnd >= 0) {
        final v = w.removeAt(vi);
        w.insert(subjEnd + 1, v);
      }
    }
    return w;
  }
}

class _W {
  _W(this.src, this.out, this.pos);
  final String src, out, pos;
}
