import 'package:unorm_dart/unorm_dart.dart' as unorm;

final _space = RegExp(r'\s+');
const _strip = {0x0301, 0x0300, 0x0341, 0x0340, 0x030F, 0x0311};

/// Lookup key. Must match `norm()` in tools/build_wiktionary.py:
/// NFKD, lower case, drop acute/grave/stress accents, NFC, collapse spaces.
String normKey(String s) {
  final d = unorm.nfkd(s.trim().toLowerCase());
  final b = StringBuffer();
  for (final r in d.runes) {
    if (!_strip.contains(r)) b.writeCharCode(r);
  }
  return unorm.nfc(b.toString()).replaceAll(_space, ' ');
}

/// Lower-case, accent-insensitive key for searching language names.
String foldKey(String s) {
  final d = unorm.nfkd(s.toLowerCase());
  final b = StringBuffer();
  for (final r in d.runes) {
    if (r >= 0x0300 && r <= 0x036F) continue;
    b.writeCharCode(r);
  }
  return b.toString();
}
