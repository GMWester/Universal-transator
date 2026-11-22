import 'dart:convert';
import 'dart:io';

import '../core/paths.dart';

class UrbanDefinition {
  UrbanDefinition(Map j)
      : definition = _clean(j['definition'] ?? ''),
        example = _clean(j['example'] ?? ''),
        author = '${j['author'] ?? ''}',
        thumbsUp = (j['thumbs_up'] as num?)?.toInt() ?? 0,
        thumbsDown = (j['thumbs_down'] as num?)?.toInt() ?? 0,
        permalink = '${j['permalink'] ?? ''}',
        word = '${j['word'] ?? ''}',
        raw = Map<String, dynamic>.from(j);

  final String definition, example, author, permalink, word;
  final int thumbsUp, thumbsDown;
  final Map<String, dynamic> raw;

  /// Urban Dictionary marks links to other entries as [word].
  static String _clean(Object s) =>
      '$s'.replaceAll('\r', '').replaceAllMapped(RegExp(r'\[([^\]]+)\]'), (m) => m.group(1)!).trim();
}

/// Optional, online-only slang lookups from Urban Dictionary (English).
/// Urban Dictionary has no official API or redistributable data, so it can
/// not be part of the offline packs; definitions the user has looked at are
/// cached on this device so they can be re-read offline.
class UrbanDictionary {
  static final instance = UrbanDictionary();
  static const _maxCached = 500;

  Map<String, List>? _cache;

  File get _cacheFile =>
      File('${AppPaths.instance.dataDir.path}${Platform.pathSeparator}urban_cache.json');

  Future<Map<String, List>> _load() async {
    if (_cache != null) return _cache!;
    try {
      if (await _cacheFile.exists()) {
        final j = jsonDecode(await _cacheFile.readAsString()) as Map;
        return _cache = j.map((k, v) => MapEntry(k as String, v as List));
      }
    } catch (_) {}
    return _cache = {};
  }

  Future<void> _save() async {
    final c = _cache!;
    while (c.length > _maxCached) {
      c.remove(c.keys.first);
    }
    try {
      await _cacheFile.writeAsString(jsonEncode(c));
    } catch (_) {}
  }

  /// Definitions for [term], best rated first. Falls back to the local cache
  /// when offline; throws if neither is available.
  Future<List<UrbanDefinition>> lookup(String term) async {
    final key = term.trim().toLowerCase();
    if (key.isEmpty) return const [];
    final cache = await _load();
    try {
      final client = HttpClient()
        ..userAgent = 'UniversalTranslator-App'
        ..connectionTimeout = const Duration(seconds: 10);
      try {
        final uri = Uri.https('api.urbandictionary.com', '/v0/define', {'term': term.trim()});
        final res = await (await client.getUrl(uri)).close().timeout(const Duration(seconds: 15));
        if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
        final body = jsonDecode(await res.transform(utf8.decoder).join()) as Map;
        final list = (body['list'] as List? ?? const []);
        cache.remove(key);
        cache[key] = list;
        await _save();
      } finally {
        client.close(force: true);
      }
    } catch (e) {
      if (!cache.containsKey(key)) rethrow;
    }
    final defs = [for (final j in cache[key]!) UrbanDefinition(j as Map)]
      ..sort((a, b) => (b.thumbsUp - b.thumbsDown).compareTo(a.thumbsUp - a.thumbsDown));
    return defs;
  }
}
