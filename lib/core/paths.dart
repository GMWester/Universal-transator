import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Where downloaded data lives. Everything under [dataDir] is used offline.
class AppPaths {
  AppPaths._(this.dataDir, this.tempDir);

  static late AppPaths instance;

  static Future<AppPaths> init() async {
    final support = await getApplicationSupportDirectory();
    final tmp = await getTemporaryDirectory();
    final d = Directory('${support.path}${Platform.pathSeparator}offline');
    await d.create(recursive: true);
    instance = AppPaths._(d, tmp);
    return instance;
  }

  final Directory dataDir;
  final Directory tempDir;

  String get sep => Platform.pathSeparator;
  Directory get packsDir => Directory('${dataDir.path}${sep}packs')..createSync(recursive: true);
  Directory get modelsDir => Directory('${dataDir.path}${sep}models')..createSync(recursive: true);
  Directory get updatesDir => Directory('${tempDir.path}${sep}ut_updates')..createSync(recursive: true);
}
