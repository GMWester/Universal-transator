import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Loads a gzip-compressed JSON asset, decoding off the UI thread.
Future<dynamic> loadGzJsonAsset(String key) async {
  final data = await rootBundle.load(key);
  final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  return compute(_decode, bytes);
}

dynamic _decode(Uint8List bytes) => jsonDecode(utf8.decode(gzip.decode(bytes)));
