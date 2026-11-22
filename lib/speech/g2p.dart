import 'dart:convert';

import 'package:unorm_dart/unorm_dart.dart' as unorm;

/// Applies the grapheme-to-phoneme rules learned from a language's Wiktionary
/// pronunciations by tools/build_wiktionary.py (learn_g2p).
class LearnedG2p {
  LearnedG2p(this._rules, [this._minTwo = 3]);

  factory LearnedG2p.fromJson(String s) {
    final j = jsonDecode(s) as Map<String, dynamic>;
    final r = (j['r'] as Map).map((k, v) => MapEntry(
        k as String, [for (final e in v as List) _Rule(e[0] as String, e[1] as String, e[2] as int)]));
    return LearnedG2p(r, (j['m2'] as num?)?.toInt() ?? 3);
  }

  final Map<String, List<_Rule>> _rules;

  /// Two-letter rules are used only when seen at least this often (tuned per
  /// language by the data pipeline; low-count digraphs swallow vowels).
  final int _minTwo;

  static List<String> graphemes(String word) {
    final out = <String>[];
    for (final r in unorm.nfc(word.toLowerCase()).runes) {
      final ch = String.fromCharCode(r);
      if (_isCombining(r) && out.isNotEmpty) {
        out[out.length - 1] += ch;
      } else if (_isLetter(ch)) {
        out.add(ch);
      }
    }
    return out;
  }

  String? convert(String word) {
    final g = graphemes(word);
    if (g.isEmpty) return null;
    final b = StringBuffer();
    var i = 0, hits = 0;
    while (i < g.length) {
      String? phon;
      var used = 1;
      if (i + 1 < g.length) {
        final two = g[i] + g[i + 1];
        final r2 = _rules[two];
        if (r2 != null && r2.first.n >= _minTwo) {
          phon = _pick(r2, g, i, 2);
          used = 2;
        }
      }
      if (phon == null) {
        final r1 = _rules[g[i]];
        if (r1 != null) phon = _pick(r1, g, i, 1);
      }
      if (phon == null) {
        phon = basicLetterIpa(g[i]) ?? '';
      } else {
        hits++;
      }
      b.write(phon);
      i += used;
    }
    return hits == 0 && b.isEmpty ? null : b.toString();
  }

  String _pick(List<_Rule> rs, List<String> g, int i, int len) {
    final left = 'L${i > 0 ? g[i - 1] : '^'}';
    final right = 'R${i + len < g.length ? g[i + len] : r'$'}';
    _Rule? best;
    for (final r in rs) {
      if ((r.ctx == left || r.ctx == right) && (best == null || r.n > best.n)) best = r;
    }
    return (best ?? rs.first).phon;
  }
}

class _Rule {
  _Rule(this.ctx, this.phon, this.n);
  final String ctx, phon;
  final int n;
}

bool _isCombining(int r) =>
    (r >= 0x0300 && r <= 0x036F) ||
    (r >= 0x1AB0 && r <= 0x1AFF) ||
    (r >= 0x1DC0 && r <= 0x1DFF) ||
    (r >= 0x20D0 && r <= 0x20FF) ||
    (r >= 0x0900 && r <= 0x0DFF && _indicMark(r)) ||
    (r >= 0x064B && r <= 0x065F) ||
    (r >= 0x0591 && r <= 0x05C7);

bool _indicMark(int r) {
  final o = (r - 0x0900) % 0x80;
  return (o >= 0x00 && o <= 0x03) || (o >= 0x3A && o <= 0x4F) || (o >= 0x51 && o <= 0x57) || o == 0x62 || o == 0x63;
}

final _letter = RegExp(r'\p{L}|\p{M}', unicode: true);
bool _isLetter(String ch) => _letter.hasMatch(ch);

/// Very small, language-neutral fallback: the most typical IPA value of
/// letters in common alphabets. Used only when no Wiktionary data exists.
String? basicLetterIpa(String ch) {
  if (ch.isEmpty) return null;
  final first = ch.runes.first;
  // Hangul syllables are decomposed algorithmically.
  if (first >= 0xAC00 && first <= 0xD7A3) return _hangul(first);
  final base = unorm.nfd(ch).runes.first;
  final s = String.fromCharCode(base);
  final v = _basic[s];
  if (v != null) return v;
  final k = _kana[s];
  if (k != null) return k;
  // Characters that are already IPA symbols.
  if (_ipaSymbols.contains(s)) return s;
  return null;
}

const _basic = {
  // Latin
  'a': 'a', 'b': 'b', 'c': 'k', 'd': 'd', 'e': 'e', 'f': 'f', 'g': 'ɡ', 'h': 'h', 'i': 'i',
  'j': 'j', 'k': 'k', 'l': 'l', 'm': 'm', 'n': 'n', 'o': 'o', 'p': 'p', 'q': 'k', 'r': 'r',
  's': 's', 't': 't', 'u': 'u', 'v': 'v', 'w': 'w', 'x': 'ks', 'y': 'y', 'z': 'z',
  'ß': 's', 'æ': 'æ', 'ø': 'ø', 'œ': 'œ', 'ð': 'ð', 'þ': 'θ', 'ł': 'w', 'đ': 'd', 'ı': 'ɯ',
  'ŋ': 'ŋ', 'ɛ': 'ɛ', 'ɔ': 'ɔ', 'ə': 'ə',
  // Cyrillic
  'а': 'a', 'б': 'b', 'в': 'v', 'г': 'ɡ', 'д': 'd', 'е': 'je', 'ё': 'jo', 'ж': 'ʐ', 'з': 'z',
  'и': 'i', 'й': 'j', 'к': 'k', 'л': 'l', 'м': 'm', 'н': 'n', 'о': 'o', 'п': 'p', 'р': 'r',
  'с': 's', 'т': 't', 'у': 'u', 'ф': 'f', 'х': 'x', 'ц': 't͡s', 'ч': 't͡ɕ', 'ш': 'ʂ', 'щ': 'ɕː',
  'ъ': '', 'ы': 'ɨ', 'ь': 'ʲ', 'э': 'e', 'ю': 'ju', 'я': 'ja', 'і': 'i', 'ї': 'ji', 'є': 'je',
  'ґ': 'ɡ', 'ў': 'w', 'ј': 'j', 'љ': 'ʎ', 'њ': 'ɲ', 'ћ': 't͡ɕ', 'ђ': 'd͡ʑ', 'џ': 'd͡ʒ', 'ѕ': 'd͡z',
  'ә': 'æ', 'ө': 'ø', 'ү': 'y', 'ң': 'ŋ', 'ғ': 'ʁ', 'қ': 'q', 'ұ': 'ʊ', 'һ': 'h',
  // Greek
  'α': 'a', 'β': 'v', 'γ': 'ɣ', 'δ': 'ð', 'ε': 'e', 'ζ': 'z', 'η': 'i', 'θ': 'θ', 'ι': 'i',
  'κ': 'k', 'λ': 'l', 'μ': 'm', 'ν': 'n', 'ξ': 'ks', 'ο': 'o', 'π': 'p', 'ρ': 'r', 'σ': 's',
  'ς': 's', 'τ': 't', 'υ': 'i', 'φ': 'f', 'χ': 'x', 'ψ': 'ps', 'ω': 'o',
  // Armenian
  'ա': 'ɑ', 'բ': 'b', 'գ': 'ɡ', 'դ': 'd', 'ե': 'ɛ', 'զ': 'z', 'է': 'ɛ', 'ը': 'ə', 'թ': 'tʰ',
  'ժ': 'ʒ', 'ի': 'i', 'լ': 'l', 'խ': 'χ', 'ծ': 't͡s', 'կ': 'k', 'հ': 'h', 'ձ': 'd͡z', 'ղ': 'ʁ',
  'ճ': 't͡ʃ', 'մ': 'm', 'յ': 'j', 'ն': 'n', 'շ': 'ʃ', 'ո': 'ɔ', 'չ': 't͡ʃʰ', 'պ': 'p', 'ջ': 'd͡ʒ',
  'ռ': 'r', 'ս': 's', 'վ': 'v', 'տ': 't', 'ր': 'ɾ', 'ց': 't͡sʰ', 'ւ': 'v', 'փ': 'pʰ', 'ք': 'kʰ',
  'օ': 'o', 'ֆ': 'f',
  // Georgian
  'ა': 'ɑ', 'ბ': 'b', 'გ': 'ɡ', 'დ': 'd', 'ე': 'ɛ', 'ვ': 'v', 'ზ': 'z', 'თ': 'tʰ', 'ი': 'i',
  'კ': 'kʼ', 'ლ': 'l', 'მ': 'm', 'ნ': 'n', 'ო': 'ɔ', 'პ': 'pʼ', 'ჟ': 'ʒ', 'რ': 'r', 'ს': 's',
  'ტ': 'tʼ', 'უ': 'u', 'ფ': 'pʰ', 'ქ': 'kʰ', 'ღ': 'ɣ', 'ყ': 'qʼ', 'შ': 'ʃ', 'ჩ': 't͡ʃʰ',
  'ც': 't͡sʰ', 'ძ': 'd͡z', 'წ': 't͡sʼ', 'ჭ': 't͡ʃʼ', 'ხ': 'x', 'ჯ': 'd͡ʒ', 'ჰ': 'h',
  // Hebrew (consonantal)
  'א': 'ʔ', 'ב': 'b', 'ג': 'ɡ', 'ד': 'd', 'ה': 'h', 'ו': 'v', 'ז': 'z', 'ח': 'χ', 'ט': 't',
  'י': 'j', 'כ': 'k', 'ך': 'χ', 'ל': 'l', 'מ': 'm', 'ם': 'm', 'נ': 'n', 'ן': 'n', 'ס': 's',
  'ע': 'ʔ', 'פ': 'p', 'ף': 'f', 'צ': 't͡s', 'ץ': 't͡s', 'ק': 'k', 'ר': 'ʁ', 'ש': 'ʃ', 'ת': 't',
  // Arabic (consonantal)
  'ا': 'aː', 'ب': 'b', 'ت': 't', 'ث': 'θ', 'ج': 'd͡ʒ', 'ح': 'ħ', 'خ': 'x', 'د': 'd', 'ذ': 'ð',
  'ر': 'r', 'ز': 'z', 'س': 's', 'ش': 'ʃ', 'ص': 'sˤ', 'ض': 'dˤ', 'ط': 'tˤ', 'ظ': 'ðˤ', 'ع': 'ʕ',
  'غ': 'ɣ', 'ف': 'f', 'ق': 'q', 'ك': 'k', 'ل': 'l', 'م': 'm', 'ن': 'n', 'ه': 'h', 'و': 'w',
  'ي': 'j', 'ى': 'aː', 'ة': 'a', 'ء': 'ʔ', 'أ': 'ʔa', 'إ': 'ʔi', 'آ': 'ʔaː', 'ؤ': 'ʔ', 'ئ': 'ʔ',
  'پ': 'p', 'چ': 't͡ʃ', 'ژ': 'ʒ', 'گ': 'ɡ', 'ک': 'k', 'ی': 'i',
  // Devanagari (inherent vowel ignored)
  'क': 'k', 'ख': 'kʰ', 'ग': 'ɡ', 'घ': 'ɡʱ', 'ङ': 'ŋ', 'च': 't͡ʃ', 'छ': 't͡ʃʰ', 'ज': 'd͡ʒ',
  'झ': 'd͡ʒʱ', 'ञ': 'ɲ', 'ट': 'ʈ', 'ठ': 'ʈʰ', 'ड': 'ɖ', 'ढ': 'ɖʱ', 'ण': 'ɳ', 'त': 't̪', 'थ': 't̪ʰ',
  'द': 'd̪', 'ध': 'd̪ʱ', 'न': 'n', 'प': 'p', 'फ': 'pʰ', 'ब': 'b', 'भ': 'bʱ', 'म': 'm', 'य': 'j',
  'र': 'r', 'ल': 'l', 'व': 'ʋ', 'श': 'ʃ', 'ष': 'ʂ', 'स': 's', 'ह': 'ɦ', 'अ': 'ə', 'आ': 'aː',
  'इ': 'ɪ', 'ई': 'iː', 'उ': 'ʊ', 'ऊ': 'uː', 'ए': 'eː', 'ऐ': 'ɛː', 'ओ': 'oː', 'औ': 'ɔː',
  // Thai (consonants, approximate)
  'ก': 'k', 'ข': 'kʰ', 'ค': 'kʰ', 'ง': 'ŋ', 'จ': 't͡ɕ', 'ฉ': 't͡ɕʰ', 'ช': 't͡ɕʰ', 'ซ': 's',
  'ญ': 'j', 'ด': 'd', 'ต': 't', 'ถ': 'tʰ', 'ท': 'tʰ', 'น': 'n', 'บ': 'b', 'ป': 'p', 'ผ': 'pʰ',
  'พ': 'pʰ', 'ฟ': 'f', 'ม': 'm', 'ย': 'j', 'ร': 'r', 'ล': 'l', 'ว': 'w', 'ส': 's', 'ห': 'h',
  'อ': 'ʔ', 'ะ': 'a', 'า': 'aː', 'ิ': 'i', 'ี': 'iː', 'ุ': 'u', 'ู': 'uː', 'เ': 'eː', 'แ': 'ɛː', 'โ': 'oː',
};

const _kana = {
  'あ': 'a', 'い': 'i', 'う': 'ɯ', 'え': 'e', 'お': 'o', 'か': 'ka', 'き': 'ki', 'く': 'kɯ',
  'け': 'ke', 'こ': 'ko', 'さ': 'sa', 'し': 'ɕi', 'す': 'sɯ', 'せ': 'se', 'そ': 'so', 'た': 'ta',
  'ち': 't͡ɕi', 'つ': 't͡sɯ', 'て': 'te', 'と': 'to', 'な': 'na', 'に': 'ɲi', 'ぬ': 'nɯ', 'ね': 'ne',
  'の': 'no', 'は': 'ha', 'ひ': 'çi', 'ふ': 'ɸɯ', 'へ': 'he', 'ほ': 'ho', 'ま': 'ma', 'み': 'mi',
  'む': 'mɯ', 'め': 'me', 'も': 'mo', 'や': 'ja', 'ゆ': 'jɯ', 'よ': 'jo', 'ら': 'ɾa', 'り': 'ɾi',
  'る': 'ɾɯ', 'れ': 'ɾe', 'ろ': 'ɾo', 'わ': 'wa', 'を': 'o', 'ん': 'ɴ', 'が': 'ɡa', 'ぎ': 'ɡi',
  'ぐ': 'ɡɯ', 'げ': 'ɡe', 'ご': 'ɡo', 'ざ': 'za', 'じ': 'd͡ʑi', 'ず': 'zɯ', 'ぜ': 'ze', 'ぞ': 'zo',
  'だ': 'da', 'で': 'de', 'ど': 'do', 'ば': 'ba', 'び': 'bi', 'ぶ': 'bɯ', 'べ': 'be', 'ぼ': 'bo',
  'ぱ': 'pa', 'ぴ': 'pi', 'ぷ': 'pɯ', 'ぺ': 'pe', 'ぽ': 'po', 'っ': 'ʔ', 'ー': 'ː',
  'ア': 'a', 'イ': 'i', 'ウ': 'ɯ', 'エ': 'e', 'オ': 'o', 'カ': 'ka', 'キ': 'ki', 'ク': 'kɯ',
  'ケ': 'ke', 'コ': 'ko', 'サ': 'sa', 'シ': 'ɕi', 'ス': 'sɯ', 'セ': 'se', 'ソ': 'so', 'タ': 'ta',
  'チ': 't͡ɕi', 'ツ': 't͡sɯ', 'テ': 'te', 'ト': 'to', 'ナ': 'na', 'ニ': 'ɲi', 'ヌ': 'nɯ', 'ネ': 'ne',
  'ノ': 'no', 'ハ': 'ha', 'ヒ': 'çi', 'フ': 'ɸɯ', 'ヘ': 'he', 'ホ': 'ho', 'マ': 'ma', 'ミ': 'mi',
  'ム': 'mɯ', 'メ': 'me', 'モ': 'mo', 'ヤ': 'ja', 'ユ': 'jɯ', 'ヨ': 'jo', 'ラ': 'ɾa', 'リ': 'ɾi',
  'ル': 'ɾɯ', 'レ': 'ɾe', 'ロ': 'ɾo', 'ワ': 'wa', 'ヲ': 'o', 'ン': 'ɴ', 'ガ': 'ɡa', 'ギ': 'ɡi',
  'グ': 'ɡɯ', 'ゲ': 'ɡe', 'ゴ': 'ɡo', 'ザ': 'za', 'ジ': 'd͡ʑi', 'ズ': 'zɯ', 'ゼ': 'ze', 'ゾ': 'zo',
  'ダ': 'da', 'デ': 'de', 'ド': 'do', 'バ': 'ba', 'ビ': 'bi', 'ブ': 'bɯ', 'ベ': 'be', 'ボ': 'bo',
  'パ': 'pa', 'ピ': 'pi', 'プ': 'pɯ', 'ペ': 'pe', 'ポ': 'po', 'ッ': 'ʔ',
};

const _ipaSymbols = {
  'ɐ', 'ɑ', 'ɒ', 'ɓ', 'ɕ', 'ɖ', 'ɗ', 'ɘ', 'ɚ', 'ɜ', 'ɝ', 'ɞ', 'ɟ', 'ɠ', 'ɡ', 'ɢ', 'ɣ', 'ɤ',
  'ɥ', 'ɦ', 'ɧ', 'ɨ', 'ɪ', 'ɫ', 'ɬ', 'ɭ', 'ɮ', 'ɯ', 'ɰ', 'ɱ', 'ɲ', 'ɳ', 'ɴ', 'ɵ', 'ɶ', 'ɸ',
  'ɹ', 'ɺ', 'ɻ', 'ɽ', 'ɾ', 'ʀ', 'ʁ', 'ʂ', 'ʃ', 'ʄ', 'ʈ', 'ʉ', 'ʊ', 'ʋ', 'ʌ', 'ʍ', 'ʎ', 'ʏ',
  'ʐ', 'ʑ', 'ʒ', 'ʔ', 'ʕ', 'ʙ', 'ʛ', 'ʜ', 'ʝ', 'ʟ', 'ʡ', 'ʢ', 'χ', 'β', 'θ',
};

String _hangul(int cp) {
  const ini = ['k', 'k͈', 'n', 't', 't͈', 'ɾ', 'm', 'p', 'p͈', 's', 's͈', '', 't͡ɕ', 't͡ɕ͈', 't͡ɕʰ', 'kʰ', 'tʰ', 'pʰ', 'h'];
  const med = ['a', 'ɛ', 'ja', 'jɛ', 'ʌ', 'e', 'jʌ', 'je', 'o', 'wa', 'wɛ', 'we', 'jo', 'u', 'wʌ', 'we', 'wi', 'ju', 'ɯ', 'ɰi', 'i'];
  const fin = ['', 'k̚', 'k̚', 'k̚', 'n', 'n', 'n', 't̚', 'l', 'k̚', 'm', 'l', 'l', 'l', 'p̚', 'l', 'm', 'p̚', 'p̚', 't̚', 't̚', 'ŋ', 't̚', 't̚', 'k̚', 't̚', 'p̚', 't̚'];
  final s = cp - 0xAC00;
  return ini[s ~/ 588] + med[(s % 588) ~/ 28] + fin[s % 28];
}
