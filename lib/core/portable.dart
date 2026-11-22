import 'dart:convert';
import 'dart:io';

/// Portable mode: when a file named `portable.txt` is next to the program
/// (Windows portable zip, or any desktop copy), everything the app writes -
/// dictionaries, translation models, settings, temporary files - is kept in a
/// `user-data` folder beside the program, so the whole folder can be moved or run
/// from a USB stick without leaving anything on the computer.
class Portable {
  Portable._();

  static final Directory? appDir = () {
    if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) return null;
    try {
      final exeDir = File(Platform.resolvedExecutable).parent;
      if (File('${exeDir.path}${Platform.pathSeparator}portable.txt').existsSync()) return exeDir;
    } catch (_) {}
    return null;
  }();

  static bool get enabled => appDir != null;

  static Directory get dataDir =>
      Directory('${appDir!.path}${Platform.pathSeparator}user-data')..createSync(recursive: true);
}

/// Small JSON-file key/value store used for settings in portable mode.
class JsonPrefs {
  JsonPrefs._(this._file, this._m);
  final File _file;
  final Map<String, Object?> _m;

  static Future<JsonPrefs> open(File f) async {
    Map<String, Object?> m = {};
    try {
      if (await f.exists()) m = Map<String, Object?>.from(jsonDecode(await f.readAsString()) as Map);
    } catch (_) {}
    return JsonPrefs._(f, m);
  }

  Object? get(String k) => _m[k];

  void set(String k, Object? v) {
    if (v == null) {
      _m.remove(k);
    } else {
      _m[k] = v;
    }
    try {
      final tmp = File('${_file.path}.tmp');
      tmp.writeAsStringSync(jsonEncode(_m), flush: true);
      tmp.renameSync(_file.path);
    } catch (_) {}
  }
}
