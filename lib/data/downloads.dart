import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

typedef Progress = void Function(int received, int total);

/// Downloads [url] to [dest] on a background isolate (network reading, file
/// writing and the SHA-256 check never touch the UI thread). Progress is
/// reported about 6 times per second.
Future<File> downloadFile(String url, File dest, {String? sha256Hex, Progress? onProgress}) async {
  final port = ReceivePort();
  final done = Completer<File>();
  final sub = port.listen((m) {
    if (done.isCompleted) return;
    if (m is List && m.length == 2 && m[0] is int) {
      onProgress?.call(m[0] as int, m[1] as int);
    } else if (m == 'ok') {
      done.complete(dest);
    } else if (m is String) {
      done.completeError(HttpException(m));
    } else if (m is List) {
      done.completeError(StateError('download failed: ${m.first}')); // uncaught isolate error
    } else if (m == null) {
      done.completeError(StateError('download stopped')); // isolate exited early
    }
  });
  try {
    await Isolate.spawn(_downloadWorker, [url, dest.path, sha256Hex ?? '', port.sendPort],
        onError: port.sendPort, onExit: port.sendPort);
    return await done.future;
  } finally {
    await sub.cancel();
    port.close();
  }
}

Future<void> _downloadWorker(List args) async {
  final url = args[0] as String, destPath = args[1] as String, want = args[2] as String;
  final out = args[3] as SendPort;
  final client = HttpClient()
    ..userAgent = 'UniversalTranslator-App'
    ..connectionTimeout = const Duration(seconds: 30);
  final part = File('$destPath.part');
  try {
    await part.parent.create(recursive: true);
    final req = await client.getUrl(Uri.parse(url));
    final res = await req.close(); // follows GitHub's redirect to its download CDN
    if (res.statusCode != 200) {
      out.send('HTTP ${res.statusCode} for $url');
      return;
    }
    final total = res.contentLength > 0 ? res.contentLength : 0;
    final raf = await part.open(mode: FileMode.write);
    final digestSink = _DigestSink();
    final hasher = sha256.startChunkedConversion(digestSink);
    var got = 0, last = 0;
    final clock = Stopwatch()..start();
    // Buffer writes into ~1 MB blocks.
    final buf = BytesBuilder(copy: false);
    await for (final chunk in res) {
      buf.add(chunk);
      hasher.add(chunk);
      got += chunk.length;
      if (buf.length >= 1 << 20) await raf.writeFrom(buf.takeBytes());
      if (clock.elapsedMilliseconds - last >= 160) {
        last = clock.elapsedMilliseconds;
        out.send([got, total]);
      }
    }
    if (buf.length > 0) await raf.writeFrom(buf.takeBytes());
    await raf.close();
    hasher.close();
    out.send([got, total]);
    if (want.isNotEmpty && digestSink.value.toString() != want.toLowerCase()) {
      await part.delete();
      out.send('Checksum mismatch, download corrupted');
      return;
    }
    final dest = File(destPath);
    if (await dest.exists()) await dest.delete();
    await part.rename(destPath);
    out.send('ok');
  } catch (e) {
    out.send('$e');
  } finally {
    client.close(force: true);
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
