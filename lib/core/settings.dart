import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'portable.dart';

enum AppTheme { light, dark, oled }

/// Key/value storage: shared_preferences normally, a JSON file beside the
/// program in portable mode.
class _Store {
  _Store(this._sp, this._json);
  final SharedPreferences? _sp;
  final JsonPrefs? _json;
  String? getString(String k) => _sp != null ? _sp.getString(k) : _json!.get(k) as String?;
  double? getDouble(String k) => _sp != null ? _sp.getDouble(k) : (_json!.get(k) as num?)?.toDouble();
  bool? getBool(String k) => _sp != null ? _sp.getBool(k) : _json!.get(k) as bool?;
  void setString(String k, String v) => _sp != null ? _sp.setString(k, v) : _json!.set(k, v);
  void setDouble(String k, double v) => _sp != null ? _sp.setDouble(k, v) : _json!.set(k, v);
  void setBool(String k, bool v) => _sp != null ? _sp.setBool(k, v) : _json!.set(k, v);
  void remove(String k) => _sp != null ? _sp.remove(k) : _json!.set(k, null);
}

/// User preferences.
class Settings extends ChangeNotifier {
  Settings._(this._p);

  static Future<Settings> load() async {
    if (Portable.enabled) {
      final f = File('${Portable.dataDir.path}${Platform.pathSeparator}settings.json');
      return Settings._(_Store(null, await JsonPrefs.open(f)));
    }
    return Settings._(_Store(await SharedPreferences.getInstance(), null));
  }

  final _Store _p;

  AppTheme get theme =>
      AppTheme.values.asNameMap()[_p.getString('theme') ?? ''] ?? AppTheme.dark;
  set theme(AppTheme v) => _set('theme', v.name);

  /// Language of the interface and of all language names (CLDR locale code).
  String get appLanguage => _p.getString('appLanguage') ?? _systemLanguage();
  set appLanguage(String v) => _set('appLanguage', v);

  String get voice => _p.getString('voice') ?? 'female';
  set voice(String v) => _set('voice', v);

  double get speechSpeed => _p.getDouble('speechSpeed') ?? 1.0;
  set speechSpeed(double v) {
    _p.setDouble('speechSpeed', v);
    notifyListeners();
  }

  double get pitchShift => _p.getDouble('pitchShift') ?? 0.0;
  set pitchShift(double v) {
    _p.setDouble('pitchShift', v);
    notifyListeners();
  }

  String? get translationModel => _p.getString('translationModel');
  set translationModel(String? v) {
    if (v == null) {
      _p.remove('translationModel');
    } else {
      _p.setString('translationModel', v);
    }
    notifyListeners();
  }

  bool get autoCheckUpdates => _p.getBool('autoCheckUpdates') ?? true;
  set autoCheckUpdates(bool v) {
    _p.setBool('autoCheckUpdates', v);
    notifyListeners();
  }

  String get lastFrom => _p.getString('lastFrom') ?? 'en';
  set lastFrom(String v) => _p.setString('lastFrom', v);
  String get lastTo => _p.getString('lastTo') ?? 'es';
  set lastTo(String v) => _p.setString('lastTo', v);

  bool get dataPromptShown => _p.getBool('dataPromptShown') ?? false;
  set dataPromptShown(bool v) => _p.setBool('dataPromptShown', v);

  String get skippedVersion => _p.getString('skippedVersion') ?? '';
  set skippedVersion(String v) => _p.setString('skippedVersion', v);

  void _set(String k, String v) {
    _p.setString(k, v);
    notifyListeners();
  }

  static String _systemLanguage() {
    final l = PlatformDispatcher.instance.locale;
    return l.languageCode.isEmpty ? 'en' : l.languageCode;
  }
}
