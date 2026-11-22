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
        approxSizeMB = j['approxSizeMB'] ?? 0,
        mirrorUrl = j['githubMirror'] == true && AppConfig._repo != null
            ? 'https://github.com/${AppConfig._repo}/releases/download/model-${j['id']}/'
            : '';
  final String id, name, license, baseUrl, langTokenStyle, mirrorUrl;
  final Map<String, List<String>> files;
  final int approxSizeMB;
}

class AppConfig {
  static String? _repo;

  AppConfig._(Map<String, dynamic> j)
      : githubRepo = j['githubRepo'],
        dataReleaseTag = j['dataReleaseTag'] ?? 'data',
        dataEditions = List<String>.from(j['dataEditions'] ?? ['en']),
        iosAppStoreUrl = j['iosAppStoreUrl'] ?? '',
        models = [for (final m in j['translationModels'] ?? []) ModelSpec(m)];

  static late AppConfig instance;

  static Future<AppConfig> load() async {
    final j = jsonDecode(await rootBundle.loadString('assets/config/app_config.json'));
    _repo = j['githubRepo'] as String?;
    return instance = AppConfig._(j);
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
