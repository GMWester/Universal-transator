import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

typedef Progress = void Function(int received, int total);

/// Streams [url] to [dest] (through a .part file), optionally checking SHA-256.
Future<File> downloadFile(String url, File dest,
    {String? sha256Hex, Progress? onProgress, http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final req = http.Request('GET', Uri.parse(url))
      ..headers['User-Agent'] = 'UniversalTranslator-App';
    final res = await c.send(req);
    if (res.statusCode != 200) {
      throw HttpException('HTTP ${res.statusCode} for $url');
    }
    await dest.parent.create(recursive: true);
    final part = File('${dest.path}.part');
    final sink = part.openWrite();
    final total = res.contentLength ?? 0;
    var got = 0;
    final digestSink = _DigestSink();
    final hasher = sha256.startChunkedConversion(digestSink);
    try {
      await for (final chunk in res.stream) {
        sink.add(chunk);
        hasher.add(chunk);
        got += chunk.length;
        onProgress?.call(got, total);
      }
    } finally {
      await sink.close();
      hasher.close();
    }
    if (sha256Hex != null && sha256Hex.isNotEmpty &&
        digestSink.value.toString() != sha256Hex.toLowerCase()) {
      await part.delete();
      throw const FormatException('Checksum mismatch, download corrupted');
    }
    if (await dest.exists()) await dest.delete();
    return await part.rename(dest.path);
  } finally {
    if (client == null) c.close();
  }
}

Future<void> gunzipFile(File src, File dest) async {
  final tmp = File('${dest.path}.tmp');
  await src.openRead().transform(gzip.decoder).pipe(tmp.openWrite());
  if (await dest.exists()) await dest.delete();
  await tmp.rename(dest.path);
}

Future<dynamic> getJson(String url) async {
  final r = await http.get(Uri.parse(url), headers: {
    'User-Agent': 'UniversalTranslator-App',
    'Accept': 'application/vnd.github+json, application/json',
  });
  if (r.statusCode != 200) throw HttpException('HTTP ${r.statusCode} for $url');
  return jsonDecode(utf8.decode(r.bodyBytes));
}

class _DigestSink implements Sink<Digest> {
  late Digest value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
