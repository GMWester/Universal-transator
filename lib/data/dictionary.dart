import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

import 'normalize.dart';
import 'packs.dart';

class Sense {
  Sense(Map<String, dynamic> j)
      : glosses = List<String>.from(j['g'] ?? const []),
        tags = List<String>.from(j['t'] ?? const []),
        topics = List<String>.from(j['p'] ?? const []),
        examples = [for (final x in j['x'] ?? const []) List<String>.from(x)],
        formOf = j['f'],
        synonyms = List<String>.from(j['sy'] ?? const []);
  final List<String> glosses, tags, topics, synonyms;
  final List<List<String>> examples; // [text, translation, romanization]
  final String? formOf;
}

class Entry {
  Entry(this.id, this.lang, this.word, this.pos, Map<String, dynamic> d, this.edition)
      : senses = [for (final s in d['s'] ?? const []) Sense(Map<String, dynamic>.from(s))],
        ipa = [for (final x in d['ip'] ?? const []) List<String>.from(x)],
        forms = [for (final x in d['fm'] ?? const []) List<String>.from(x)],
        etymology = d['et'],
        synonyms = List<String>.from(d['sy'] ?? const []),
        antonyms = List<String>.from(d['an'] ?? const []),
        derived = List<String>.from(d['de'] ?? const []),
        related = List<String>.from(d['re'] ?? const []);
  final int id;
  final String lang, word, pos, edition;
  final List<Sense> senses;
  final List<List<String>> ipa; // [ipa, tags]
  final List<List<String>> forms; // [form, tags]
  final String? etymology;
  final List<String> synonyms, antonyms, derived, related;

  /// First IPA without brackets, for speech.
  String? get speakableIpa {
    if (ipa.isEmpty) return null;
    var s = ipa.first.first.trim();
    if (s.length > 1 && '/['.contains(s[0])) s = s.substring(1);
    if (s.isNotEmpty && '/]'.contains(s[s.length - 1])) s = s.substring(0, s.length - 1);
    return s.split(RegExp(r'[,~]')).first.trim();
  }
}

class TranslationGroup {
  TranslationGroup(this.sourceWord, this.pos, this.gloss, this.targets);
  final String sourceWord, pos, gloss;
  final List<TranslatedWord> targets;
}

class TranslatedWord {
  TranslatedWord(this.word, this.roman, this.tags);
  final String word, roman, tags;
}

/// Offline Wiktionary lookups across installed packs.
class Dictionary {
  Dictionary(this.packs);
  final PackSource packs;

  static Map<String, dynamic> _decode(Uint8List blob) =>
      jsonDecode(utf8.decode(zlib.decode(blob))) as Map<String, dynamic>;

  List<Entry> _rows(ResultSet rs, String edition) => [
        for (final r in rs)
          Entry(r['id'] as int, r['lang'] as String, r['word'] as String,
              (r['pos'] ?? '') as String, _decode(r['data'] as Uint8List), edition)
      ];

  /// Entries for [query] in [lang]: the word itself, then lemmas it is a form of.
  List<Entry> lookup(String lang, String query, {String edition = 'en'}) {
    final db = packs.dbFor(lang, edition: edition);
    if (db == null) return const [];
    final key = normKey(query);
    final out = _rows(
        db.select('SELECT * FROM entries WHERE lang=? AND norm=? ORDER BY id LIMIT 40', [lang, key]),
        edition);
    final seen = out.map((e) => e.id).toSet();
    final lemmas = db.select(
        'SELECT e.* FROM forms f JOIN entries e ON e.id=f.entry_id WHERE f.lang=? AND f.norm=? LIMIT 20',
        [lang, key]);
    for (final e in _rows(lemmas, edition)) {
      if (seen.add(e.id)) out.add(e);
    }
    return out;
  }

  /// Headword suggestions starting with [prefix].
  List<String> suggest(String lang, String prefix, {String edition = 'en', int limit = 30}) {
    final db = packs.dbFor(lang, edition: edition);
    if (db == null || prefix.trim().isEmpty) return const [];
    final key = normKey(prefix);
    final rs = db.select(
        "SELECT DISTINCT word FROM entries WHERE lang=? AND norm >= ? AND norm < ? ORDER BY norm LIMIT ?",
        [lang, key, '$key\u{10FFFF}', limit]);
    return [for (final r in rs) r['word'] as String];
  }

  /// Words of [lang] whose (English or app-language) meaning contains [text].
  List<Entry> searchMeaning(String lang, String text, {String edition = 'en', int limit = 40}) {
    final db = packs.dbFor(lang, edition: edition);
    if (db == null) return const [];
    final q = text
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => '"${w.replaceAll('"', '')}"')
        .join(' ');
    if (q.isEmpty) return const [];
    try {
      final ids = db.select('SELECT rowid FROM gloss_fts WHERE gloss_fts MATCH ? LIMIT 400', [q]);
      if (ids.isEmpty) return const [];
      final list = ids.map((r) => r['rowid']).join(',');
      final rows = _rows(db.select('SELECT * FROM entries WHERE id IN ($list) AND lang=?', [lang]), edition);
      // Prefer entries whose gloss is exactly the searched text.
      final t = text.toLowerCase().trim();
      int score(Entry e) {
        var best = 1000;
        for (final s in e.senses) {
          for (final g in s.glosses) {
            final gl = g.toLowerCase();
            final parts = gl.split(RegExp(r'[;,]')).map((x) => x.trim().replaceFirst(RegExp(r'^(to|a|an|the) '), ''));
            if (parts.contains(t.replaceFirst(RegExp(r'^(to|a|an|the) '), ''))) best = 0;
            if (best > 0) best = gl.length < best ? gl.length : best;
          }
        }
        return best;
      }

      rows.sort((a, b) => score(a).compareTo(score(b)));
      return rows.take(limit).toList();
    } on SqliteException {
      return const [];
    }
  }

  /// Translations of [word] from [from] to [to] using Wiktionary translation
  /// tables (English senses as pivot), then meanings as a fallback.
  List<TranslationGroup> translateWord(String from, String to, String word) {
    final out = <TranslationGroup>[];
    final fromDb = packs.dbFor(from);
    final toDb = packs.dbFor(to);
    if (fromDb == null) return out;
    var key = normKey(word);
    var senseRows = fromDb.select('SELECT DISTINCT sense_id FROM tr WHERE lang=? AND norm=?', [from, key]);
    if (senseRows.isEmpty) {
      // try the lemma of an inflected form
      final lemma = fromDb.select(
          'SELECT e.norm FROM forms f JOIN entries e ON e.id=f.entry_id WHERE f.lang=? AND f.norm=? LIMIT 1',
          [from, key]);
      if (lemma.isNotEmpty) {
        key = lemma.first['norm'] as String;
        senseRows = fromDb.select('SELECT DISTINCT sense_id FROM tr WHERE lang=? AND norm=?', [from, key]);
      }
    }
    final ids = [for (final r in senseRows) r['sense_id'] as int];
    if (ids.isNotEmpty) {
      final idList = ids.take(300).join(',');
      final senses = {
        for (final r in fromDb.select('SELECT * FROM senses WHERE id IN ($idList)'))
          r['id'] as int: r
      };
      final targets = <int, List<TranslatedWord>>{};
      if (to == 'en') {
        for (final s in senses.values) {
          targets.putIfAbsent(s['id'] as int, () => []).add(TranslatedWord(s['word'] as String, '', ''));
        }
      } else if (toDb != null) {
        for (final r in toDb.select('SELECT * FROM tr WHERE sense_id IN ($idList) AND lang=?', [to])) {
          targets.putIfAbsent(r['sense_id'] as int, () => []).add(
              TranslatedWord(r['word'] as String, (r['roman'] ?? '') as String, (r['tags'] ?? '') as String));
        }
      }
      for (final id in ids) {
        final s = senses[id];
        final t = targets[id];
        if (s == null || t == null || t.isEmpty) continue;
        out.add(TranslationGroup(s['word'] as String, (s['pos'] ?? '') as String, (s['gloss'] ?? '') as String, t));
      }
    }
    if (out.isNotEmpty) return out;

    // Fallback through meanings: X's English glosses, then words of Y with that meaning.
    final entries = lookup(from, word);
    for (final e in entries) {
      for (final s in e.senses.where((s) => s.formOf == null).take(6)) {
        final gloss = s.glosses.isEmpty ? '' : s.glosses.first;
        if (gloss.isEmpty) continue;
        if (to == 'en') {
          out.add(TranslationGroup(e.word, e.pos, gloss, [TranslatedWord(gloss, '', '')]));
          continue;
        }
        if (toDb == null) continue;
        final head = gloss.split(RegExp(r'[;,(]')).first.trim();
        if (head.split(' ').length > 4) continue;
        final cands = searchMeaning(to, head, limit: 5);
        if (cands.isNotEmpty) {
          out.add(TranslationGroup(e.word, e.pos, gloss,
              [for (final c in cands) TranslatedWord(c.word, '', c.pos)]));
        }
      }
    }
    return out;
  }

  /// Pronunciation of a single word, if Wiktionary has one.
  String? ipaFor(String lang, String word) {
    final db = packs.dbFor(lang);
    if (db == null) return null;
    final key = normKey(word);
    final r = db.select('SELECT ipa FROM ipa WHERE lang=? AND norm=?', [lang, key]);
    if (r.isNotEmpty) return r.first['ipa'] as String;
    return null;
  }

  /// Learned grapheme-to-phoneme rules and frequent characters of a language.
  Map<String, String?> langInfo(String lang) {
    final db = packs.dbFor(lang);
    if (db == null) return const {};
    final r = db.select('SELECT g2p, chars FROM langs WHERE code=?', [lang]);
    if (r.isEmpty) return const {};
    return {'g2p': r.first['g2p'] as String?, 'chars': r.first['chars'] as String?};
  }

  Database? db(String lang) => packs.dbFor(lang);
}
