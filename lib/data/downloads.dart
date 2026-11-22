import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

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
    try {
      var last = 0;
      final clock = Stopwatch()..start();
      await for (final chunk in res.stream) {
        sink.add(chunk);
        got += chunk.length;
        // report at most ~6 times per second
        if (clock.elapsedMilliseconds - last >= 160) {
          last = clock.elapsedMilliseconds;
          onProgress?.call(got, total);
        }
      }
      onProgress?.call(got, total);
    } finally {
      await sink.close();
    }
    // Checksum on a background isolate so the UI stays smooth.
    if (sha256Hex != null && sha256Hex.isNotEmpty &&
        await fileSha256(part.path) != sha256Hex.toLowerCase()) {
      await part.delete();
      throw const FormatException('Checksum mismatch, download corrupted');
    }
    if (await dest.exists()) await dest.delete();
    return await part.rename(dest.path);
  } finally {
    if (client == null) c.close();
  }
}

Future<String> fileSha256(String path) => Isolate.run(() async {
      final out = _DigestSink();
      final h = sha256.startChunkedConversion(out);
      await for (final c in File(path).openRead()) {
        h.add(c);
      }
      h.close();
      return out.value.toString();
    });

/// Unpacks a .gz file on a background isolate.
Future<void> gunzipFile(File src, File dest) {
  final s = src.path, d = dest.path;
  return Isolate.run(() async {
    final tmp = File('$d.tmp');
    await File(s).openRead().transform(gzip.decoder).pipe(tmp.openWrite());
    final out = File(d);
    if (await out.exists()) await out.delete();
    await tmp.rename(d);
  });
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
