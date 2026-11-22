import 'dart:convert';

import 'package:flutter/services.dart';

class ModelSpec {
  ModelSpec(Map<String, dynamic> j)
      : id = j['id'],
        name = j['name'],
        license = j['license'] ?? '',
        baseUrl = j['baseUrl'],
        langTokenStyle = j['langTokenStyle'] ?? 'nllb',
        files = (j['files'] as Map).map((k, v) => MapEntry(k as String, List<String>.from(v))),
        approxSizeMB = j['approxSizeMB'] ?? 0;
  final String id, name, license, baseUrl, langTokenStyle;
  final Map<String, List<String>> files;
  final int approxSizeMB;
}

class AppConfig {
  AppConfig._(Map<String, dynamic> j)
      : githubRepo = j['githubRepo'],
        dataReleaseTag = j['dataReleaseTag'] ?? 'data',
        dataEditions = List<String>.from(j['dataEditions'] ?? ['en']),
        iosAppStoreUrl = j['iosAppStoreUrl'] ?? '',
        models = [for (final m in j['translationModels'] ?? []) ModelSpec(m)];

  static late AppConfig instance;

  static Future<AppConfig> load() async {
    final s = await rootBundle.loadString('assets/config/app_config.json');
    return instance = AppConfig._(jsonDecode(s));
  }

  final String githubRepo;
  final String dataReleaseTag;
  final List<String> dataEditions;
  final String iosAppStoreUrl;
  final List<ModelSpec> models;

  String get releasesApi => 'https://api.github.com/repos/$githubRepo/releases';
  /// Packs of each Wiktionary edition live in their own release ("data-en", ...).
  String dataAssetUrl(String edition, String file) =>
      'https://github.com/$githubRepo/releases/download/$dataReleaseTag-$edition/$file';
}
