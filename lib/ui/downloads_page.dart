// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import '../core/config.dart';
import '../data/downloads.dart';
import '../data/normalize.dart';
import '../data/packs.dart';
import '../translate/nmt.dart';
import 'home.dart';
import 'widgets.dart';

/// Lets the user choose which data to download from the project's GitHub
/// releases: dictionaries per language (and per meanings language) and the
/// translation model. Everything downloaded works offline afterwards.
class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key});
  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  String edition = 'en';
  String filter = '';
  bool loading = false;
  String? error;
  bool onlyInstalled = false;
  final Set<String> selected = {}; // language codes in [edition]
  final Map<String, double?> modelProgress = {};
  final Map<String, CancelToken> modelCancel = {};

  @override
  void initState() {
    super.initState();
    if (app.packs.manifests[edition] == null) _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await app.packs.refresh(edition);
    } catch (e) {
      error = '$e';
    }
    if (mounted) setState(() => loading = false);
  }

  // Cached: language code -> pack, and the sorted language list. Rebuilt
  // only when the edition, its manifest or the app language changes.
  Object? _cacheKey;
  Map<String, PackInfo> _lp = const {};
  List<String> _sortedLangs = const [];

  Map<String, PackInfo> get _langPacks {
    final packs = app.packs.manifests[edition];
    final key = (edition, identityHashCode(packs), app.langs.locale);
    if (key != _cacheKey) {
      final out = <String, PackInfo>{};
      for (final p in packs ?? const <PackInfo>[]) {
        for (final l in p.langs.keys) {
          out[l] = p;
        }
      }
      final names = {for (final l in out.keys) l: foldKey(app.langs.name(l))};
      final langs = out.keys.toList()
        ..sort((a, b) {
          final ea = out[a]!.entries[a] ?? 0, eb = out[b]!.entries[b] ?? 0;
          if ((ea >= 1000) != (eb >= 1000)) return ea >= 1000 ? -1 : 1;
          if (ea >= 1000 && ea != eb) return eb.compareTo(ea);
          return names[a]!.compareTo(names[b]!);
        });
      _lp = out;
      _sortedLangs = langs;
      _cacheKey = key;
    }
    return _lp;
  }

  Set<PackInfo> _packsFor(Iterable<String> langs) {
    final lp = _langPacks;
    return {for (final l in langs) if (lp[l] != null && !app.packs.isInstalled(lp[l]!.id)) lp[l]!};
  }

  void _selectSuggested() {
    final ui = app.settings.appLanguage.split('-').first;
    setState(() => selected.addAll({'en', ui, app.settings.lastFrom, app.settings.lastTo}
        .where((l) => _langPacks.containsKey(l))));
  }

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      title: tr('downloads'),
      actions: [
        IconButton(tooltip: tr('refresh'), onPressed: loading ? null : _refresh, icon: const Icon(Icons.refresh)),
      ],
      child: AnimatedBuilder(
        animation: Listenable.merge([app.packs, app.langs]),
        builder: (context, _) {
          final lp = _langPacks;
          var langs = _sortedLangs;
          if (onlyInstalled) langs = langs.where((l) => app.packs.isInstalled(lp[l]!.id)).toList();
          if (filter.isNotEmpty) {
            final f = foldKey(filter);
            langs = langs
                .where((l) =>
                    foldKey(app.langs.name(l)).contains(f) ||
                    foldKey(lp[l]!.langs[l] ?? '').contains(f) ||
                    l == f)
                .toList();
          }
          final todo = _packsFor(selected);
          final todoBytes = todo.fold<int>(0, (n, p) => n + p.size);
          final th = Theme.of(context).textTheme;
          return Column(children: [
            Expanded(
              child: CustomScrollView(slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      SectionTitle(tr('translationModel')),
                      if (NmtModel.supportedOnThisPlatform)
                        for (final m in AppConfig.instance.models) _modelTile(context, m)
                      else
                        Text(tr('modelNotOnPlatform'), style: th.bodySmall),
                      SectionTitle(tr('wikiPacks')),
                      Text(tr('wikiPacksHelp'), style: th.bodySmall),
                      const SizedBox(height: 8),
                      Wrap(spacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        Text('${tr('meaningsIn')}:'),
                        DropdownButton<String>(
                          value: edition,
                          items: [
                            for (final e in AppConfig.instance.dataEditions)
                              DropdownMenuItem(value: e, child: Text(app.langs.name(e))),
                          ],
                          onChanged: (v) {
                            setState(() {
                              edition = v!;
                              selected.clear();
                            });
                            if (app.packs.manifests[edition] == null) _refresh();
                          },
                        ),
                      ]),
                      Text('${tr('installed')}: ${fmtBytes(app.packs.installedBytes)}', style: th.bodySmall),
                      const SizedBox(height: 8),
                      TextField(
                        decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tr('searchLanguage')),
                        onChanged: (v) => setState(() => filter = v),
                      ),
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, runSpacing: 4, children: [
                        ActionChip(
                          avatar: const Icon(Icons.auto_awesome, size: 18),
                          label: Text(tr('suggested')),
                          onPressed: _selectSuggested,
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.select_all, size: 18),
                          label: Text('${tr('selectShown')} (${langs.length})'),
                          onPressed: () => setState(() => selected.addAll(langs)),
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.deselect, size: 18),
                          label: Text(tr('clearSelection')),
                          onPressed: () => setState(selected.clear),
                        ),
                        FilterChip(
                          label: Text(tr('installed')),
                          selected: onlyInstalled,
                          onSelected: (v) => setState(() => onlyInstalled = v),
                        ),
                      ]),
                      if (loading) const LinearProgressIndicator(),
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text('${tr('noDataYet')}\n$error',
                              style: TextStyle(color: Theme.of(context).colorScheme.error)),
                        ),
                    ]),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => _langTile(context, langs[i], lp[langs[i]]!),
                      childCount: langs.length,
                    ),
                  ),
                ),
              ]),
            ),
            // download bar
            Material(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(children: [
                    Expanded(
                      child: app.packs.bulkRunning
                          ? Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                              Text([
                                tr('bulkProgress', ['${app.packs.bulkDone}', '${app.packs.bulkTotal}']),
                                if (app.packs.bulkFailed > 0) tr('bulkFailed', ['${app.packs.bulkFailed}']),
                              ].join(' · ')),
                              const SizedBox(height: 4),
                              LinearProgressIndicator(
                                  value: app.packs.bulkTotal == 0
                                      ? null
                                      : (app.packs.bulkDone + app.packs.bulkFailed) / app.packs.bulkTotal),
                            ])
                          : Text(tr('selectedSummary', ['${selected.length}', fmtBytes(todoBytes)])),
                    ),
                    const SizedBox(width: 12),
                    if (!app.packs.bulkRunning && app.packs.failedPacks(edition).isNotEmpty) ...[
                      OutlinedButton.icon(
                        onPressed: () => app.packs.installAll(app.packs.failedPacks(edition)),
                        icon: const Icon(Icons.refresh),
                        label: Text(tr('retryFailed', ['${app.packs.failedPacks(edition).length}'])),
                      ),
                      const SizedBox(width: 8),
                    ],
                    app.packs.bulkRunning
                        ? OutlinedButton.icon(
                            onPressed: app.packs.cancelBulk, icon: const Icon(Icons.stop), label: Text(tr('cancel')))
                        : FilledButton.icon(
                            onPressed: todo.isEmpty
                                ? null
                                : () async {
                                    await app.packs.installAll(todo.toList());
                                    if (mounted) setState(selected.clear);
                                  },
                            icon: const Icon(Icons.download),
                            label: Text(tr('downloadSelected')),
                          ),
                  ]),
                ),
              ),
            ),
          ]);
        },
      ),
    );
  }

  Widget _langTile(BuildContext context, String l, PackInfo p) {
    final st = app.packs.active[p.id];
    final inst = app.packs.isInstalled(p.id);
    final bundled = app.packs.isBundled(p.id);
    final entries = p.entries[l] ?? 0;
    final shared = p.langs.length > 1;
    final sub = [
      '$entries ${tr('entries')}',
      shared ? '${fmtBytes(p.size)} ${tr('sharedPack', ['${p.langs.length}'])}' : fmtBytes(p.size),
      if (bundled) tr('includedInInstaller'),
    ].join(' · ');
    return CheckboxListTile(
      value: inst ? true : selected.contains(l),
      onChanged: inst || st != null
          ? null
          : (v) => setState(() => v == true ? selected.add(l) : selected.remove(l)),
      title: Text(app.langs.name(l)),
      subtitle: st == null && app.packs.failed[p.id] != null
          ? Text('${tr('error')}: ${app.packs.failed[p.id]}',
              style: TextStyle(color: Theme.of(context).colorScheme.error))
          : st != null
          ? (st.error != null
              ? Text(st.error!, style: TextStyle(color: Theme.of(context).colorScheme.error))
              : LinearProgressIndicator(value: st.fraction))
          : Text(sub),
      secondary: st != null && st.error == null
          ? IconButton(
              tooltip: tr('cancel'), icon: const Icon(Icons.close), onPressed: () => app.packs.cancel(p.id))
          : inst && !bundled
          ? IconButton(
              tooltip: tr('remove'), icon: const Icon(Icons.delete_outline), onPressed: () => app.packs.remove(p.id))
          : Icon(inst ? Icons.offline_pin : Icons.cloud_outlined),
      controlAffinity: ListTileControlAffinity.leading,
    );
  }

  Widget _modelTile(BuildContext context, ModelSpec m) {
    final inst = NmtModel.isInstalled(m);
    final bundled = NmtModel.isBundled(m);
    final prog = modelProgress[m.id];
    final busy = modelProgress.containsKey(m.id);
    return Card(
      child: ListTile(
        leading: Icon(inst ? Icons.offline_pin : Icons.cloud_outlined),
        title: Text(m.name),
        subtitle: busy
            ? LinearProgressIndicator(value: prog)
            : Text('${inst ? (bundled ? tr('includedInInstaller') : tr('installed')) : '~${m.approxSizeMB} MB'} · '
                '${tr('license')}: ${m.license}'),
        trailing: bundled
            ? null
            : busy
            ? IconButton(
                tooltip: tr('cancel'),
                icon: const Icon(Icons.close),
                onPressed: () => modelCancel[m.id]?.cancel())
            : inst
                ? IconButton(
                    tooltip: tr('deleteModel'),
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      await app.translator.unload();
                      await NmtModel.delete(m);
                      setState(() {});
                    })
                : IconButton(
                    tooltip: tr('downloadModel'),
                    icon: const Icon(Icons.download),
                    onPressed: () async {
                      final token = modelCancel[m.id] = CancelToken();
                      setState(() => modelProgress[m.id] = null);
                      try {
                        await NmtModel.download(m, (r, t) {
                          if (mounted) setState(() => modelProgress[m.id] = t > 0 ? r / t : null);
                        }, cancel: token);
                        app.settings.translationModel = m.id;
                      } on DownloadCancelled {
                        await NmtModel.delete(m);
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                        }
                      }
                      if (mounted) setState(() => modelProgress.remove(m.id));
                    }),
      ),
    );
  }
}
