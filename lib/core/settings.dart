import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppTheme { light, dark, oled }

/// User preferences, persisted with shared_preferences.
class Settings extends ChangeNotifier {
  Settings._(this._p);

  static Future<Settings> load() async =>
      Settings._(await SharedPreferences.getInstance());

  final SharedPreferences _p;

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
