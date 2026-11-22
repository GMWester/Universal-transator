// ignore_for_file: deprecated_member_use
import 'dart:async';

import 'package:flutter/material.dart';

import '../data/dictionary.dart';
import 'home.dart';
import 'widgets.dart';

/// [language] to [other language] dictionary.
class DictionaryPage extends StatefulWidget {
  const DictionaryPage({super.key});
  @override
  State<DictionaryPage> createState() => _DictionaryPageState();
}

class _DictionaryPageState extends State<DictionaryPage> {
  late String from = app.settings.lastFrom, to = app.settings.lastTo;
  final q = TextEditingController();
  List<String> suggestions = [];
  List<Entry> entries = [];
  List<TranslationGroup> translations = [];
  List<Entry> glossEntries = []; // meanings written in the app language
  bool byMeaning = false;
  String searched = '';
  Timer? _deb;

  void _onType(String v) {
    _deb?.cancel();
    _deb = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      setState(() => suggestions = byMeaning ? [] : app.dict.suggest(from, v));
    });
  }

  void _search(String word) {
    q.text = word;
    final w = word.trim();
    if (w.isEmpty) return;
    setState(() {
      searched = w;
      suggestions = [];
      if (byMeaning) {
        entries = app.dict.searchMeaning(from, w);
        translations = [];
        glossEntries = [];
      } else {
        entries = app.dict.lookup(from, w);
        translations = from == to ? [] : app.dict.translateWord(from, to, w);
        final ui = app.settings.appLanguage.split('-').first;
        glossEntries = ui != 'en' && app.packs.dbFor(from, edition: ui) != null
            ? app.dict.lookup(from, w, edition: ui)
            : [];
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      title: tr('dictionary'),
      child: AnimatedBuilder(
        animation: Listenable.merge([app.packs, app.langs]),
        builder: (context, _) {
          final installed = app.packs.installedLanguages();
          return ListView(padding: const EdgeInsets.all(16), children: [
            Row(children: [
              Expanded(
                child: LanguageButton(
                    code: from,
                    label: tr('from'),
                    highlight: installed,
                    onChanged: (c) => setState(() {
                          from = c;
                          if (searched.isNotEmpty) _search(searched);
                        })),
              ),
              IconButton(
                tooltip: tr('swap'),
                icon: const Icon(Icons.swap_horiz),
                onPressed: () => setState(() {
                  final t = from;
                  from = to;
                  to = t;
                }),
              ),
              Expanded(
                child: LanguageButton(
                    code: to,
                    label: tr('to'),
                    highlight: installed,
                    onChanged: (c) => setState(() {
                          to = c;
                          if (searched.isNotEmpty) _search(searched);
                        })),
              ),
            ]),
            const SizedBox(height: 12),
            if (!installed.contains(from)) NeedsPack(lang: from),
            if (from != to && to != 'en' && !installed.contains(to)) NeedsPack(lang: to),
            TextField(
              controller: q,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: byMeaning ? tr('meaningSearch') : tr('searchWord'),
              ),
              onChanged: _onType,
              onSubmitted: _search,
              textInputAction: TextInputAction.search,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('meaningSearch')),
              value: byMeaning,
              onChanged: (v) => setState(() => byMeaning = v),
            ),
            if (suggestions.isNotEmpty)
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final s in suggestions) ActionChip(label: Text(s), onPressed: () => _search(s)),
              ]),
            if (translations.isNotEmpty) ...[
              SectionTitle('${tr('translations')} → ${app.langs.name(to)}'),
              for (final g in translations) _TranslationCard(group: g, to: to),
            ],
            if (searched.isNotEmpty && entries.isEmpty && translations.isEmpty)
              Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(tr('noResults')))),
            for (final e in entries) EntryCard(entry: e, onWord: _search),
            if (glossEntries.isNotEmpty) ...[
              SectionTitle('${tr('meaningsIn')} ${app.langs.name(app.settings.appLanguage)}'),
              for (final e in glossEntries) EntryCard(entry: e, onWord: _search),
            ],
          ]);
        },
      ),
    );
  }
}

class _TranslationCard extends StatelessWidget {
  const _TranslationCard({required this.group, required this.to});
  final TranslationGroup group;
  final String to;
  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${group.sourceWord} (${group.pos})${group.gloss.isNotEmpty ? ' — ${group.gloss}' : ''}',
              style: th.bodySmall),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final t in group.targets)
              InputChip(
                avatar: const Icon(Icons.volume_up, size: 16),
                label: Text([t.word, if (t.roman.isNotEmpty) '(${t.roman})', if (t.tags.isNotEmpty) t.tags].join(' ')),
                onPressed: () => app.speech.speakText(to, t.word),
              ),
          ]),
        ]),
      ),
    );
  }
}

class EntryCard extends StatelessWidget {
  const EntryCard({super.key, required this.entry, this.onWord});
  final Entry entry;
  final ValueChanged<String>? onWord;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final e = entry;
    final cs = Theme.of(context).colorScheme;
    Widget words(String title, List<String> w) => w.isEmpty
        ? const SizedBox.shrink()
        : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SectionTitle(title),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final x in w.take(30))
                ActionChip(label: Text(x), onPressed: onWord == null ? null : () => onWord!(x)),
            ]),
          ]);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text.rich(TextSpan(children: [
                TextSpan(text: e.word, style: th.headlineSmall),
                TextSpan(text: '  ${e.pos}', style: th.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
              ])),
            ),
            SpeakButton(onSpeak: () => app.speech.speakEntry(e)),
          ]),
          if (e.ipa.isNotEmpty)
            Wrap(spacing: 12, children: [
              for (final p in e.ipa.take(4))
                InkWell(
                  onTap: () => app.speech.speakIpa(p[0].replaceAll(RegExp(r'^[/\[]|[/\]]$'), '')),
                  child: Text('${p[0]}${p[1].isNotEmpty ? '  (${p[1]})' : ''}',
                      style: th.bodyMedium?.copyWith(color: cs.primary)),
                ),
            ]),
          SectionTitle(tr('meanings')),
          for (var i = 0; i < e.senses.length; i++) _sense(context, i + 1, e.senses[i]),
          if (e.forms.isNotEmpty) ...[
            SectionTitle(tr('forms')),
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final f in e.forms.take(60))
                Chip(
                  label: Text(f[1].isEmpty ? f[0] : '${f[0]}  ·  ${f[1]}', style: th.bodySmall),
                  visualDensity: VisualDensity.compact,
                ),
            ]),
          ],
          words(tr('synonyms'), e.synonyms),
          words(tr('antonyms'), e.antonyms),
          words(tr('related'), [...e.related, ...e.derived]),
          if (e.etymology != null && e.etymology!.isNotEmpty) ...[
            SectionTitle(tr('etymology')),
            Text(e.etymology!, style: th.bodyMedium),
          ],
        ]),
      ),
    );
  }

  Widget _sense(BuildContext context, int n, Sense s) {
    final th = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 28, child: Text('$n.', style: th.bodyMedium)),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (s.tags.isNotEmpty || s.topics.isNotEmpty)
              Text('(${[...s.tags, ...s.topics].join(', ')})',
                  style: th.bodySmall?.copyWith(color: cs.onSurfaceVariant, fontStyle: FontStyle.italic)),
            for (final g in s.glosses) SelectableText(g, style: th.bodyLarge),
            if (s.formOf != null && onWord != null)
              TextButton(onPressed: () => onWord!(s.formOf!), child: Text('→ ${s.formOf}')),
            for (final x in s.examples)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(x[0], style: th.bodyMedium?.copyWith(fontStyle: FontStyle.italic))),
                    SpeakButton(onSpeak: () => app.speech.speakText(entry.lang, x[0])),
                  ]),
                  if (x.length > 2 && x[2].isNotEmpty) Text(x[2], style: th.bodySmall),
                  if (x.length > 1 && x[1].isNotEmpty) Text(x[1], style: th.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                ]),
              ),
            if (s.synonyms.isNotEmpty)
              Text('${tr('synonyms')}: ${s.synonyms.join(', ')}', style: th.bodySmall),
          ]),
        ),
      ]),
    );
  }
}
