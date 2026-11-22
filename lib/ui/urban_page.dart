// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/urban.dart';
import 'home.dart';
import 'widgets.dart';

/// Urban Dictionary tab: online slang definitions (optional, see Settings).
class UrbanPage extends StatefulWidget {
  const UrbanPage({super.key});
  @override
  State<UrbanPage> createState() => _UrbanPageState();
}

class _UrbanPageState extends State<UrbanPage> {
  final q = TextEditingController();
  Future<List<UrbanDefinition>>? _f;
  String term = '';
  bool all = false;

  void _search(String w) {
    final t = w.trim();
    if (t.isEmpty) return;
    q.text = t;
    setState(() {
      term = t;
      all = false;
      _f = UrbanDictionary.instance.lookup(t);
    });
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return PageFrame(
      title: tr('urbanTab'),
      child: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
          controller: q,
          decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tr('urbanSearch')),
          textInputAction: TextInputAction.search,
          onSubmitted: _search,
        ),
        const SizedBox(height: 8),
        Text(tr('urbanNote'), style: th.labelSmall),
        if (_f != null)
          FutureBuilder<List<UrbanDefinition>>(
            future: _f,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator());
              }
              if (snap.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(tr('urbanOffline'), style: th.bodyMedium?.copyWith(color: cs.error)),
                );
              }
              final defs = snap.data!;
              if (defs.isEmpty) {
                return Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(tr('noResults'))));
              }
              final shown = all ? defs : defs.take(5).toList();
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SizedBox(height: 8),
                for (final d in shown)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(d.word.isEmpty ? term : d.word, style: th.titleLarge),
                        const SizedBox(height: 6),
                        SelectableText(d.definition, style: th.bodyLarge),
                        if (d.example.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(d.example, style: th.bodyMedium?.copyWith(fontStyle: FontStyle.italic)),
                          ),
                        const SizedBox(height: 8),
                        Row(children: [
                          Icon(Icons.thumb_up_outlined, size: 16, color: cs.onSurfaceVariant),
                          Text(' ${d.thumbsUp}   ', style: th.labelSmall),
                          Icon(Icons.thumb_down_outlined, size: 16, color: cs.onSurfaceVariant),
                          Text(' ${d.thumbsDown}   ', style: th.labelSmall),
                          Expanded(child: Text(d.author, style: th.labelSmall, overflow: TextOverflow.ellipsis)),
                          if (d.permalink.startsWith('http'))
                            IconButton(
                              tooltip: 'urbandictionary.com',
                              icon: const Icon(Icons.open_in_new, size: 18),
                              onPressed: () =>
                                  launchUrl(Uri.parse(d.permalink), mode: LaunchMode.externalApplication),
                            ),
                        ]),
                      ]),
                    ),
                  ),
                if (!all && defs.length > 5)
                  Center(
                    child: TextButton(
                        onPressed: () => setState(() => all = true), child: Text('+${defs.length - 5}')),
                  ),
              ]);
            },
          ),
      ]),
    );
  }
}
