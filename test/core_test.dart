import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ipareader_ffi/ipareader_ffi.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:universal_translator/data/characters.dart';
import 'package:universal_translator/data/dictionary.dart';
import 'package:universal_translator/data/normalize.dart';
import 'package:universal_translator/data/packs.dart';
import 'package:universal_translator/speech/g2p.dart';
import 'package:universal_translator/translate/tokenizer.dart';
import 'package:universal_translator/data/urban.dart';
import 'package:universal_translator/update/updater.dart';

class FixturePacks implements PackSource {
  final nl = sqlite3.open('test/fixtures/wikt-en-nl.sqlite', mode: OpenMode.readOnly);
  final misc = sqlite3.open('test/fixtures/wikt-en-misc1.sqlite', mode: OpenMode.readOnly);
  @override
  Database? dbFor(String lang, {String edition = 'en'}) =>
      edition != 'en' ? null : (lang == 'nl' ? nl : (['en', 'de', 'fr', 'es'].contains(lang) ? misc : null));
}

void main() {
  final dict = Dictionary(FixturePacks());

  test('normKey matches the Python pack builder', () {
    expect(normKey('  Häuser '), 'häuser');
    expect(normKey('café'), 'cafe');
    expect(normKey('мо́ре'), 'море');
  });

  test('lookup word and inflected form', () {
    final e = dict.lookup('nl', 'huis');
    expect(e.first.word, 'huis');
    expect(e.first.senses.first.glosses.first, 'house');
    expect(dict.lookup('nl', 'huizen').map((x) => x.word), contains('huis'));
    expect(dict.lookup('en', 'Houses').first.word, 'house');
  });

  test('X to Y translation through Wiktionary translation tables', () {
    expect(dict.translateWord('en', 'nl', 'dog').first.targets.first.word, 'hond');
    expect(dict.translateWord('nl', 'de', 'hond').first.targets.first.word, 'Hund');
    expect(dict.translateWord('de', 'en', 'Haus').first.targets.first.word, 'house');
    expect(dict.translateWord('nl', 'fr', 'eten').first.targets.first.word, 'manger');
  });

  test('meaning search (reverse dictionary)', () {
    expect(dict.searchMeaning('nl', 'dog').map((e) => e.word), contains('hond'));
  });

  test('pronunciation from Wiktionary and learned G2P rules', () {
    expect(dict.ipaFor('nl', 'hond'), 'ɦɔnt');
    final g2p = LearnedG2p.fromJson(dict.langInfo('nl')['g2p']!);
    expect(g2p.convert('schoolbaa'), 'sxoːlbaː');
    expect(basicLetterIpa('한'), 'han');
  });

  test('CLDR UnicodeSet parsing', () {
    expect(Characters.parseSet('[a b {ij} c-e]'), ['a', 'b', 'ij', 'c', 'd', 'e']);
  });

  test('version comparison', () {
    expect(Updater.isNewer('1.2.0', '1.1.9'), isTrue);
    expect(Updater.isNewer('v1.0.0', '1.0.0'), isFalse);
  });

  test('Unigram tokenizer round trip', () {
    final t = HfTokenizer.parse('''{"added_tokens":[{"id":0,"content":"<s>"},{"id":2,"content":"</s>"},{"id":5,"content":"eng_Latn"}],
      "pre_tokenizer":{"type":"Metaspace","replacement":"▁","prepend_scheme":"always"},
      "model":{"type":"Unigram","unk_id":1,"vocab":[["<s>",0],["<unk>",0],["</s>",0],["▁",-3],["▁hello",-2],["eng_Latn",0],["▁wor",-4],["ld",-4],["▁world",-2.5],["h",-5],["e",-5],["l",-5],["o",-5]]}}''');
    final ids = t.encode('hello world');
    expect(ids, [4, 8]);
    expect(t.decode([5, ...ids, 2]), 'hello world');
    expect(t.tokenId('eng_Latn'), 5);
  });

  test('IPAReader synthesizes IPA to WAV', () {
    if (!File('build/test_lib/libipareader_ffi.so').existsSync()) {
      markTestSkipped('native lib not built for host tests');
      return;
    }
    final wav = IpaReader.synthWav('ˈhɛloʊ ˈwɝld');
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(wav.length, greaterThan(10000));
  });

  test('Urban Dictionary entries: links unwrapped, votes parsed', () {
    final d = UrbanDefinition({
      'word': 'yeet',
      'definition': 'To [throw] something\r\nwith force',
      'example': 'He [yeeted] the ball',
      'thumbs_up': 120,
      'thumbs_down': 7,
      'author': 'someone',
      'permalink': 'https://www.urbandictionary.com/define.php?term=yeet',
    });
    expect(d.definition, 'To throw something\nwith force');
    expect(d.example, 'He yeeted the ball');
    expect(d.thumbsUp - d.thumbsDown, 113);
  });
}
