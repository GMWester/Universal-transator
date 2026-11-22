// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import '../core/config.dart';
import '../data/packs.dart';
import '../translate/nmt.dart';
import 'home.dart';
import 'widgets.dart';

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
  final Map<String, double?> modelProgress = {};
  bool bulk = false;

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

  @override
  void initState() {
    super.initState();
    if (app.packs.manifests['en'] == null) _refresh();
  }

  Future<void> _downloadAll(List<PackInfo> list) async {
    setState(() => bulk = true);
    for (final p in list) {
      if (!bulk || !mounted) break;
      if (!app.packs.isInstalled(p.id)) await app.packs.install(p);
    }
    if (mounted) setState(() => bulk = false);
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
          final packs = app.packs.manifests[edition] ?? const <PackInfo>[];
          String label(PackInfo p) {
            final names = p.langs.keys.map(app.langs.name).toList()..sort();
            return names.length <= 3 ? names.join(', ') : '${names.take(3).join(', ')} +${names.length - 3}';
          }

          final shown = packs.where((p) {
            if (filter.isEmpty) return true;
            final f = filter.toLowerCase();
            return p.langs.keys.any((c) => app.langs.name(c).toLowerCase().contains(f) || c == f) ||
                p.langs.values.any((n) => n.toLowerCase().contains(f));
          }).toList();
          final total = packs.fold<int>(0, (n, p) => n + p.size);
          return ListView(padding: const EdgeInsets.all(16), children: [
            SectionTitle(tr('translationModel')),
            for (final m in AppConfig.instance.models) _modelTile(context, m),
            SectionTitle(tr('wikiPacks')),
            Text(tr('wikiPacksHelp'), style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Row(children: [
              Text('${tr('meaningsIn')}: '),
              DropdownButton<String>(
                value: edition,
                items: [
                  for (final e in AppConfig.instance.dataEditions)
                    DropdownMenuItem(value: e, child: Text('${app.langs.name(e)} Wiktionary')),
                ],
                onChanged: (v) {
                  setState(() => edition = v!);
                  if (app.packs.manifests[edition] == null) _refresh();
                },
              ),
            ]),
            Text('${tr('installed')}: ${fmtBytes(app.packs.installedBytes)}',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            TextField(
              decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tr('searchLanguage')),
              onChanged: (v) => setState(() => filter = v),
            ),
            const SizedBox(height: 8),
            if (loading) const LinearProgressIndicator(),
            if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            if (packs.isNotEmpty)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: bulk
                    ? OutlinedButton.icon(
                        onPressed: () => setState(() => bulk = false),
                        icon: const Icon(Icons.stop),
                        label: Text(tr('cancel')))
                    : OutlinedButton.icon(
                        onPressed: () => _downloadAll(packs),
                        icon: const Icon(Icons.download),
                        label: Text('${tr('downloadAll')} (${fmtBytes(total)})')),
              ),
            for (final p in shown) _packTile(context, p, label(p)),
          ]);
        },
      ),
    );
  }

  Widget _packTile(BuildContext context, PackInfo p, String label) {
    final st = app.packs.active[p.id];
    final inst = app.packs.isInstalled(p.id);
    final entries = p.entries.values.fold<int>(0, (a, b) => a + b);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: st != null
          ? (st.error != null
              ? Text(st.error!, style: TextStyle(color: Theme.of(context).colorScheme.error))
              : LinearProgressIndicator(value: st.fraction))
          : Text('${fmtBytes(p.size)} · $entries entries'),
      trailing: inst
          ? IconButton(
              tooltip: tr('remove'), icon: const Icon(Icons.delete_outline), onPressed: () => app.packs.remove(p.id))
          : IconButton(
              tooltip: tr('download'),
              icon: const Icon(Icons.download),
              onPressed: st != null ? null : () => app.packs.install(p)),
      leading: Icon(inst ? Icons.offline_pin : Icons.cloud_outlined),
    );
  }

  Widget _modelTile(BuildContext context, ModelSpec m) {
    final inst = NmtModel.isInstalled(m);
    final prog = modelProgress[m.id];
    final busy = modelProgress.containsKey(m.id);
    return Card(
      child: ListTile(
        leading: Icon(inst ? Icons.offline_pin : Icons.cloud_outlined),
        title: Text(m.name),
        subtitle: busy
            ? LinearProgressIndicator(value: prog)
            : Text('${inst ? tr('installed') : '~${m.approxSizeMB} MB'} · ${tr('license')}: ${m.license}'),
        trailing: busy
            ? null
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
                      setState(() => modelProgress[m.id] = null);
                      try {
                        await NmtModel.download(m, (r, t) {
                          if (mounted) setState(() => modelProgress[m.id] = t > 0 ? r / t : null);
                        });
                        app.settings.translationModel = m.id;
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
