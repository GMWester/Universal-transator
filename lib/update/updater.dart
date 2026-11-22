import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/config.dart';
import '../core/paths.dart';
import '../data/downloads.dart';

/// Set for the Android build that supports old devices (Android 5/6).
const bool kLegacyBuild = bool.fromEnvironment('LEGACY_ANDROID');

class ReleaseInfo {
  ReleaseInfo(this.version, this.notes, this.assetUrl, this.assetName, this.pageUrl, this.size);
  final String version, notes, pageUrl;
  final String? assetUrl, assetName;
  final int size;
}

/// Self-update from GitHub Releases, from inside the app.
///  * Android (phones, TV, XR): downloads the APK and hands it to the system
///    package installer. It is signed with the same key, so it updates in place.
///  * Windows: downloads and runs the setup program, which replaces the app.
///  * macOS: downloads the .app, swaps it in and relaunches.
///  * Linux: replaces the AppImage (or the extracted bundle) and relaunches.
///  * iOS: Apple only allows App Store / TestFlight updates, so the store page opens.
class Updater extends ChangeNotifier {
  static final instance = Updater();
  static const _ch = MethodChannel('universal_translator/updater');

  String currentVersion = '0.0.0';
  ReleaseInfo? available;
  bool checking = false;
  double? progress;
  String? status;

  Future<void> init() async {
    final p = await PackageInfo.fromPlatform();
    currentVersion = p.version;
  }

  static String assetNameForPlatform() {
    if (Platform.isAndroid) {
      return kLegacyBuild ? 'universal-translator-android-legacy.apk' : 'universal-translator-android.apk';
    }
    if (Platform.isWindows) {
      final arm = Platform.version.contains('windows_arm64');
      return 'universal-translator-windows-${arm ? 'arm64' : 'x64'}-setup.exe';
    }
    if (Platform.isMacOS) return 'universal-translator-macos.zip';
    if (Platform.isLinux) {
      final arm = Platform.version.contains('arm64');
      if (Platform.environment['APPIMAGE'] != null) {
        return arm ? 'universal-translator-linux-aarch64.AppImage' : 'universal-translator-linux-x86_64.AppImage';
      }
      return arm ? 'universal-translator-linux-arm64.tar.gz' : 'universal-translator-linux-x64.tar.gz';
    }
    return '';
  }

  /// universal-translator-linux-x86_64.AppImage -> universal-translator-linux-x86_64-full.AppImage
  static String fullVariant(String asset) {
    final i = asset.indexOf('.');
    return i < 0 ? '$asset-full' : '${asset.substring(0, i)}-full${asset.substring(i)}';
  }

  static bool isNewer(String a, String b) {
    List<int> p(String v) => v
        .replaceFirst(RegExp('^v'), '')
        .split(RegExp(r'[.+\-]'))
        .map((x) => int.tryParse(x) ?? 0)
        .toList();
    final x = p(a), y = p(b);
    for (var i = 0; i < 3; i++) {
      final xi = i < x.length ? x[i] : 0, yi = i < y.length ? y[i] : 0;
      if (xi != yi) return xi > yi;
    }
    return false;
  }

  Future<ReleaseInfo?> check() async {
    checking = true;
    status = null;
    notifyListeners();
    try {
      final j = await getJson('${AppConfig.instance.releasesApi}/latest') as Map;
      final tag = (j['tag_name'] ?? '') as String;
      // A "full" installation (with bundled offline data) updates to the full
      // variant where the whole app is replaced (AppImage, macOS bundle).
      final want = assetNameForPlatform();
      final full = AppPaths.instance.bundledDataDir != null && !Platform.isWindows
          ? fullVariant(want)
          : null;
      String? url, name;
      var size = 0;
      final candidates = <String>[...?(full == null ? null : [full]), want];
      for (final candidate in candidates) {
        for (final a in j['assets'] as List? ?? const []) {
          if (url == null && a['name'] == candidate) {
            url = a['browser_download_url'];
            name = a['name'];
            size = a['size'] ?? 0;
          }
        }
      }
      final r = ReleaseInfo(tag.replaceFirst('v', ''), (j['body'] ?? '') as String, url, name,
          (j['html_url'] ?? '') as String, size);
      available = isNewer(r.version, currentVersion) ? r : null;
      if (available == null) status = 'upToDate';
      return available;
    } catch (e) {
      status = 'error:$e';
      return null;
    } finally {
      checking = false;
      notifyListeners();
    }
  }

  Future<void> install(ReleaseInfo r) async {
    if (Platform.isIOS) {
      final store = AppConfig.instance.iosAppStoreUrl;
      await launchUrl(Uri.parse(store.isNotEmpty ? store : r.pageUrl), mode: LaunchMode.externalApplication);
      return;
    }
    if (r.assetUrl == null) {
      await launchUrl(Uri.parse(r.pageUrl), mode: LaunchMode.externalApplication);
      return;
    }
    final dir = AppPaths.instance.updatesDir;
    final file = File('${dir.path}${Platform.pathSeparator}${r.assetName}');
    progress = 0;
    status = 'downloading';
    notifyListeners();
    try {
      await downloadFile(r.assetUrl!, file, onProgress: (got, total) {
        progress = total > 0 ? got / total : null;
        notifyListeners();
      });
      status = 'installing';
      notifyListeners();
      if (Platform.isAndroid) {
        await _ch.invokeMethod('installApk', {'path': file.path});
      } else if (Platform.isWindows) {
        await Process.start(file.path, ['/SILENT', '/CLOSEAPPLICATIONS', '/RESTARTAPPLICATIONS'],
            mode: ProcessStartMode.detached);
        exit(0);
      } else if (Platform.isMacOS) {
        await _installMac(file);
      } else if (Platform.isLinux) {
        await _installLinux(file);
      }
    } catch (e) {
      status = 'error:$e';
    } finally {
      progress = null;
      notifyListeners();
    }
  }

  Future<void> _installMac(File zip) async {
    // .../Universal Translator.app/Contents/MacOS/universal_translator
    final exe = File(Platform.resolvedExecutable);
    final appDir = exe.parent.parent.parent;
    final tmp = Directory('${zip.parent.path}/unzipped');
    if (await tmp.exists()) await tmp.delete(recursive: true);
    await tmp.create();
    final r = await Process.run('/usr/bin/ditto', ['-x', '-k', zip.path, tmp.path]);
    if (r.exitCode != 0) throw StateError('unzip failed: ${r.stderr}');
    final newApp = tmp.listSync().whereType<Directory>().firstWhere((d) => d.path.endsWith('.app'));
    final script = '''
while kill -0 $pid 2>/dev/null; do sleep 0.3; done
rm -rf "${appDir.path}.old"
mv "${appDir.path}" "${appDir.path}.old" && /usr/bin/ditto "${newApp.path}" "${appDir.path}" && rm -rf "${appDir.path}.old"
xattr -dr com.apple.quarantine "${appDir.path}" 2>/dev/null
open "${appDir.path}"
''';
    await Process.start('/bin/sh', ['-c', script], mode: ProcessStartMode.detached);
    exit(0);
  }

  Future<void> _installLinux(File f) async {
    final appImage = Platform.environment['APPIMAGE'];
    if (appImage != null && f.path.endsWith('.AppImage')) {
      await Process.run('chmod', ['+x', f.path]);
      final script = '''
while kill -0 $pid 2>/dev/null; do sleep 0.3; done
mv -f "${f.path}" "$appImage" && chmod +x "$appImage"
"$appImage" >/dev/null 2>&1 &
''';
      await Process.start('/bin/sh', ['-c', script], mode: ProcessStartMode.detached);
      exit(0);
    }
    // tar.gz bundle: extract over the directory that holds the executable.
    final dir = File(Platform.resolvedExecutable).parent.path;
    final script = '''
while kill -0 $pid 2>/dev/null; do sleep 0.3; done
tar -xzf "${f.path}" -C "$dir" --strip-components=1
"${Platform.resolvedExecutable}" >/dev/null 2>&1 &
''';
    await Process.start('/bin/sh', ['-c', script], mode: ProcessStartMode.detached);
    exit(0);
  }
}
