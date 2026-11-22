import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'portable.dart';

/// Where downloaded data lives. Everything under [dataDir] is used offline.
class AppPaths {
  AppPaths._(this.dataDir, this.tempDir);

  static late AppPaths instance;

  static Future<AppPaths> init() async {
    if (Portable.enabled) {
      // Everything stays in <program folder>/user-data.
      final base = Portable.dataDir;
      final sep = Platform.pathSeparator;
      final d = Directory('${base.path}${sep}offline')..createSync(recursive: true);
      final t = Directory('${base.path}${sep}tmp')..createSync(recursive: true);
      return instance = AppPaths._(d, t);
    }
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
  /// Offline data shipped inside a "full" installer (read-only), or null.
  /// Windows/Linux: `<app dir>/offline-data`, macOS: `<App>.app/Contents/Resources/offline-data`.
  late final Directory? bundledDataDir = () {
    try {
      final exeDir = File(Platform.resolvedExecutable).parent;
      final candidates = [
        Directory('${exeDir.path}${sep}offline-data'),
        Directory('${exeDir.parent.path}${sep}Resources${sep}offline-data'),
      ];
      for (final d in candidates) {
        if (File('${d.path}${sep}bundled.json').existsSync()) return d;
      }
    } catch (_) {}
    return null;
  }();

  Directory get updatesDir => Directory('${tempDir.path}${sep}ut_updates')..createSync(recursive: true);
}
