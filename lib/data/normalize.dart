import 'package:unorm_dart/unorm_dart.dart' as unorm;

final _space = RegExp(r'\s+');
const _strip = {0x0301, 0x0300, 0x0341, 0x0340, 0x030F, 0x0311};

/// Lookup key. Must match `norm()` in tools/build_wiktionary.py:
/// NFKD, lower case, drop acute/grave/stress accents, NFC, collapse spaces.
String normKey(String s) {
  final t = s.trim().toLowerCase();
  if (_isAscii(t)) return t.replaceAll(_space, ' ');
  final d = unorm.nfkd(s.trim().toLowerCase());
  final b = StringBuffer();
  for (final r in d.runes) {
    if (!_strip.contains(r)) b.writeCharCode(r);
  }
  return unorm.nfc(b.toString()).replaceAll(_space, ' ');
}

bool _isAscii(String s) {
  for (var i = 0; i < s.length; i++) {
    if (s.codeUnitAt(i) > 0x7F) return false;
  }
  return true;
}

final Map<String, String> _foldCache = {};

/// Lower-case, accent-insensitive key for searching language names.
/// Memoized: Unicode decomposition is slow and the same ~20 000 language
/// names are compared over and over while sorting and searching.
String foldKey(String s) {
  final hit = _foldCache[s];
  if (hit != null) return hit;
  final r = _isAscii(s) ? s.toLowerCase() : _fold(s);
  if (_foldCache.length > 60000) _foldCache.clear();
  return _foldCache[s] = r;
}

String _fold(String s) {
  final d = unorm.nfkd(s.toLowerCase());
  final b = StringBuffer();
  for (final r in d.runes) {
    if (r >= 0x0300 && r <= 0x036F) continue;
    b.writeCharCode(r);
  }
  return b.toString();
}
