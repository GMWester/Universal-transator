import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_translator/data/downloads.dart';

void main() {
  final server = Platform.environment['UT_TEST_SERVER'];
  test('background download with progress and checksum', () async {
    if (server == null) {
      markTestSkipped('set UT_TEST_SERVER to run');
      return;
    }
    final dir = await Directory.systemTemp.createTemp('dl');
    final updates = <int>[];
    final sw = Stopwatch()..start();
    final f = await downloadFile('$server/blob.bin', File('${dir.path}/blob.bin'),
        sha256Hex: '7b86e31dcc9b1e2509ca2018efff3c7238c2f783796cee570ad8e5aa3afd3d74', onProgress: (r, t) => updates.add(r));
    expect(await f.length(), 30000000);
    expect(updates.last, 30000000);
    await expectLater(
        downloadFile('$server/blob.bin', File('${dir.path}/b2.bin'), sha256Hex: '00'),
        throwsA(isA<HttpException>()));
    await expectLater(downloadFile('$server/missing.bin', File('${dir.path}/b3.bin')),
        throwsA(isA<HttpException>()));
    // ignore: avoid_print
    print('30 MB in ${sw.elapsedMilliseconds} ms, ${updates.length} progress updates');
  });

  test('cancel stops a running download and removes the partial file', () async {
    if (server == null) {
      markTestSkipped('set UT_TEST_SERVER to run');
      return;
    }
    final dir = await Directory.systemTemp.createTemp('dl');
    final token = CancelToken();
    final dest = File('${dir.path}/big.bin');
    final f = downloadFile('$server/big.bin', dest, cancel: token, onProgress: (r, t) {
      if (r > 0) token.cancel();
    });
    await expectLater(f, throwsA(isA<DownloadCancelled>()));
    expect(await dest.exists(), isFalse);
    expect(await File('${dest.path}.part').exists(), isFalse);
  });
}
