import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:ipareader_ffi/ipareader_ffi.dart';

import '../core/paths.dart';
import '../core/settings.dart';
import '../data/dictionary.dart';
import '../data/normalize.dart';
import 'g2p.dart';

/// Text to speech: text -> IPA (Wiktionary pronunciations, learned rules) ->
/// audio with IPAReader (https://github.com/GMWester/IPAReader).
class Speech {
  Speech(this.dict, this.settings);
  final Dictionary dict;
  final Settings settings;
  final AudioPlayer _player = AudioPlayer();
  final Map<String, LearnedG2p?> _g2p = {};
  int _n = 0;

  static final _token = RegExp(r"[\p{L}\p{M}\p{N}'’\-]+|[.,!?;:¿¡。、，！？]", unicode: true);
  static final _noSpaceScripts = RegExp(
      r'[฀-໿က-႟ក-៿぀-ヿ㐀-䶿一-鿿豈-﫿]');

  LearnedG2p? _rules(String lang) {
    if (_g2p.containsKey(lang)) return _g2p[lang];
    final s = dict.langInfo(lang)['g2p'];
    LearnedG2p? r;
    if (s != null && s.isNotEmpty) {
      try {
        r = LearnedG2p.fromJson(s);
      } catch (_) {}
    }
    return _g2p[lang] = r;
  }

  /// Converts text in [lang] into IPA for IPAReader.
  String textToIpa(String lang, String text) {
    final out = <String>[];
    for (final m in _token.allMatches(text)) {
      final tok = m.group(0)!;
      if ('.,!?;:¿¡。、，！？'.contains(tok)) {
        const map = {'。': '.', '、': ',', '，': ',', '！': '!', '？': '?', '¿': '', '¡': ''};
        final p = map[tok] ?? tok;
        if (p.isNotEmpty) out.add(p);
        continue;
      }
      if (_noSpaceScripts.hasMatch(tok)) {
        out.addAll(_segmentIpa(lang, tok));
      } else {
        out.add(_wordIpa(lang, tok));
      }
    }
    return out.where((s) => s.isNotEmpty).join(' ').replaceAll(' ,', ',').replaceAll(' .', '.')
        .replaceAll(' ?', '?').replaceAll(' !', '!');
  }

  String _wordIpa(String lang, String w) {
    final ipa = dict.ipaFor(lang, w);
    if (ipa != null) return ipa;
    final r = _rules(lang);
    final g = r?.convert(w);
    if (g != null && g.isNotEmpty) return g;
    final b = StringBuffer();
    for (final ch in LearnedG2p.graphemes(w)) {
      b.write(basicLetterIpa(ch) ?? '');
    }
    if (b.isEmpty && RegExp(r'^\p{N}+$', unicode: true).hasMatch(w)) return '';
    return b.toString();
  }

  /// Longest-match segmentation for scripts written without spaces.
  List<String> _segmentIpa(String lang, String s) {
    final chars = s.runes.map(String.fromCharCode).toList();
    final out = <String>[];
    var i = 0;
    while (i < chars.length) {
      String? hit;
      var len = 1;
      for (var l = chars.length - i < 8 ? chars.length - i : 8; l >= 1; l--) {
        final ipa = dict.ipaFor(lang, chars.sublist(i, i + l).join());
        if (ipa != null) {
          hit = ipa;
          len = l;
          break;
        }
      }
      out.add(hit ?? (basicLetterIpa(chars[i]) ?? ''));
      i += len;
    }
    return out;
  }

  Future<void> speakText(String lang, String text) => speakIpa(textToIpa(lang, text));

  Future<void> speakEntry(Entry e) async {
    final ipa = e.speakableIpa;
    await speakIpa(ipa ?? textToIpa(e.lang, e.word));
  }

  Future<void> speakIpa(String ipa) async {
    if (ipa.trim().isEmpty) return;
    final wav = await IpaReader.synthWavAsync(
        ipa,
        IpaSpeechSettings(
          voice: settings.voice,
          speed: settings.speechSpeed,
          pitchShift: settings.pitchShift,
        ));
    final f = File('${AppPaths.instance.tempDir.path}${Platform.pathSeparator}ipr_${_n++ % 4}.wav');
    await f.writeAsBytes(wav, flush: true);
    await _player.stop();
    await _player.play(DeviceFileSource(f.path));
  }

  Future<void> stop() => _player.stop();

  static String normalized(String s) => normKey(s);
}
