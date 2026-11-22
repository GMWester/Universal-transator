import 'dart:convert';
import 'dart:math' as math;

import 'package:unorm_dart/unorm_dart.dart' as unorm;

/// Minimal implementation of a Hugging Face `tokenizer.json` for SentencePiece
/// style models (NLLB, M2M-100, Marian): Unigram or BPE model, Metaspace
/// pre-tokenizer, byte fallback.
class HfTokenizer {
  HfTokenizer._();

  late final String type; // Unigram | BPE
  final Map<String, int> vocab = {};
  final List<String> idToToken = [];
  final List<double> scores = [];
  final Map<String, int> mergeRank = {};
  final Map<String, int> added = {};
  int unkId = 3;
  bool byteFallback = false;
  String replacement = '▁';
  bool addPrefixSpace = true;
  int _maxPieceLen = 16;

  static HfTokenizer parse(String json) {
    final t = HfTokenizer._();
    final j = jsonDecode(json) as Map<String, dynamic>;
    final model = j['model'] as Map<String, dynamic>;
    t.type = model['type'] as String;
    t.byteFallback = model['byte_fallback'] == true;
    if (t.type == 'Unigram') {
      final v = model['vocab'] as List;
      for (var i = 0; i < v.length; i++) {
        final tok = v[i][0] as String;
        t.vocab[tok] = i;
        t.idToToken.add(tok);
        t.scores.add((v[i][1] as num).toDouble());
        if (tok.length > t._maxPieceLen) t._maxPieceLen = math.min(tok.length, 48);
      }
      t.unkId = (model['unk_id'] as int?) ?? 3;
    } else {
      final v = (model['vocab'] as Map).cast<String, int>();
      t.vocab.addAll(v);
      final maxId = v.values.fold<int>(0, math.max);
      t.idToToken.addAll(List.filled(maxId + 1, ''));
      v.forEach((k, id) => t.idToToken[id] = k);
      final merges = model['merges'] as List? ?? const [];
      for (var i = 0; i < merges.length; i++) {
        final m = merges[i];
        final key = m is String ? m : '${m[0]} ${m[1]}';
        t.mergeRank[key] = i;
      }
      final unk = model['unk_token'] as String?;
      if (unk != null && v.containsKey(unk)) t.unkId = v[unk]!;
    }
    for (final a in j['added_tokens'] as List? ?? const []) {
      final c = a['content'] as String;
      final id = a['id'] as int;
      t.added[c] = id;
      while (t.idToToken.length <= id) {
        t.idToToken.add('');
      }
      t.idToToken[id] = c;
    }
    void readMeta(dynamic p) {
      if (p is Map) {
        if (p['type'] == 'Metaspace') {
          t.replacement = (p['replacement'] as String?) ?? '▁';
          final ps = p['prepend_scheme'];
          t.addPrefixSpace = p['add_prefix_space'] != false && ps != 'never';
        }
        for (final k in ['pretokenizers', 'decoders']) {
          for (final x in p[k] as List? ?? const []) {
            readMeta(x);
          }
        }
      }
    }

    readMeta(j['pre_tokenizer']);
    return t;
  }

  int? tokenId(String token) => added[token] ?? vocab[token];

  List<int> encode(String text) {
    var s = unorm.nfkc(text).replaceAll(RegExp(r'\s+'), ' ').trim();
    if (s.isEmpty) return [];
    s = s.replaceAll(' ', replacement);
    if (addPrefixSpace) s = '$replacement$s';
    // Metaspace splits on the replacement char, keeping it as prefix.
    final words = <String>[];
    var cur = StringBuffer();
    for (final r in s.runes) {
      final c = String.fromCharCode(r);
      if (c == replacement && cur.isNotEmpty) {
        words.add(cur.toString());
        cur = StringBuffer();
      }
      cur.write(c);
    }
    if (cur.isNotEmpty) words.add(cur.toString());
    final ids = <int>[];
    for (final w in words) {
      ids.addAll(type == 'Unigram' ? _unigram(w) : _bpe(w));
    }
    return ids;
  }

  List<int> _unigram(String word) {
    final ch = word.runes.map(String.fromCharCode).toList();
    final n = ch.length;
    final best = List<double>.filled(n + 1, -1e30);
    final back = List<int>.filled(n + 1, -1);
    final backId = List<int>.filled(n + 1, -1);
    best[0] = 0;
    final minScore = scores.isEmpty ? -20.0 : scores.reduce(math.min) - 10;
    for (var i = 0; i < n; i++) {
      if (best[i] <= -1e29) continue;
      var piece = '';
      for (var l = 1; l <= _maxPieceLen && i + l <= n; l++) {
        piece += ch[i + l - 1];
        final id = vocab[piece];
        if (id != null) {
          final sc = best[i] + scores[id];
          if (sc > best[i + l]) {
            best[i + l] = sc;
            back[i + l] = i;
            backId[i + l] = id;
          }
        }
      }
      if (best[i + 1] <= -1e29) {
        best[i + 1] = best[i] + minScore;
        back[i + 1] = i;
        backId[i + 1] = -1; // unknown char
      }
    }
    final out = <int>[];
    var k = n;
    while (k > 0) {
      final id = backId[k];
      final start = back[k];
      if (id >= 0) {
        out.add(id);
      } else {
        out.addAll(_fallback(ch.sublist(start, k).join()).reversed);
      }
      k = start;
    }
    return out.reversed.toList();
  }

  List<int> _bpe(String word) {
    final direct = vocab[word];
    if (direct != null) return [direct];
    var parts = word.runes.map(String.fromCharCode).toList();
    while (parts.length > 1) {
      var bestRank = 1 << 30, bestI = -1;
      for (var i = 0; i < parts.length - 1; i++) {
        final r = mergeRank['${parts[i]} ${parts[i + 1]}'];
        if (r != null && r < bestRank) {
          bestRank = r;
          bestI = i;
        }
      }
      if (bestI < 0) break;
      parts = [
        ...parts.sublist(0, bestI),
        parts[bestI] + parts[bestI + 1],
        ...parts.sublist(bestI + 2)
      ];
    }
    final out = <int>[];
    for (final p in parts) {
      final id = vocab[p];
      if (id != null) {
        out.add(id);
      } else {
        out.addAll(_fallback(p));
      }
    }
    return out;
  }

  List<int> _fallback(String s) {
    if (!byteFallback) return [unkId];
    final out = <int>[];
    for (final b in utf8.encode(s)) {
      final id = vocab['<0x${b.toRadixString(16).toUpperCase().padLeft(2, '0')}>'];
      out.add(id ?? unkId);
    }
    return out;
  }

  String decode(List<int> ids, {Set<int> skip = const {}}) {
    final bytes = <int>[];
    final b = StringBuffer();
    void flush() {
      if (bytes.isNotEmpty) {
        b.write(utf8.decode(bytes, allowMalformed: true));
        bytes.clear();
      }
    }

    final byteTok = RegExp(r'^<0x([0-9A-Fa-f]{2})>$');
    for (final id in ids) {
      if (skip.contains(id) || id < 0 || id >= idToToken.length) continue;
      final t = idToToken[id];
      if (added.containsKey(t)) continue;
      final m = byteTok.firstMatch(t);
      if (m != null) {
        bytes.add(int.parse(m.group(1)!, radix: 16));
        continue;
      }
      flush();
      b.write(t);
    }
    flush();
    return b.toString().replaceAll(replacement, ' ').trim();
  }
}
