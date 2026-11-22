// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import '../data/dictionary.dart';
import '../data/grammar.dart';
import 'home.dart';
import 'widgets.dart';

const _groupOrder = ['sentence', 'word', 'sounds', 'other', 'lexicon'];

/// Grammar rules of a language, and the differences between two languages in
/// sentence structure and word structure.
class GrammarPage extends StatefulWidget {
  const GrammarPage({super.key});
  @override
  State<GrammarPage> createState() => _GrammarPageState();
}

class _GrammarPageState extends State<GrammarPage> {
  late String a = app.settings.lastFrom, b = app.settings.lastTo;
  bool compare = true, onlyDiff = false;
  String filter = '';
  final wordCtl = TextEditingController();
  List<Entry> wordA = [], wordB = [];

  String _groupName(String g) {
    const k = {'sentence': 'sentenceStructure', 'word': 'wordStructure'};
    final key = k[g];
    if (key != null) {
      final t = tr(key);
      if (t != key) return t;
    }
    return app.grammar.groups[g] ?? g;
  }

  @override
  Widget build(BuildContext context) {
    final withData = app.grammar.languagesWithData;
    return PageFrame(
      title: tr('grammar'),
      child: ListView(padding: const EdgeInsets.all(16), children: [
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: false, label: Text(tr('rules')), icon: const Icon(Icons.rule)),
            ButtonSegment(value: true, label: Text(tr('compare')), icon: const Icon(Icons.compare_arrows)),
          ],
          selected: {compare},
          onSelectionChanged: (s) => setState(() => compare = s.first),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: LanguageButton(
                code: a, label: compare ? 'A' : null, highlight: withData,
                onChanged: (c) => setState(() => a = c)),
          ),
          if (compare) ...[
            IconButton(
                icon: const Icon(Icons.swap_horiz),
                onPressed: () => setState(() {
                      final t = a;
                      a = b;
                      b = t;
                    })),
            Expanded(
              child: LanguageButton(code: b, label: 'B', highlight: withData, onChanged: (c) => setState(() => b = c)),
            ),
          ],
        ]),
        const SizedBox(height: 8),
        TextField(
          decoration: InputDecoration(prefixIcon: const Icon(Icons.filter_list), hintText: tr('searchWord')),
          onChanged: (v) => setState(() => filter = v.toLowerCase()),
        ),
        if (compare)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('onlyDifferences')),
            value: onlyDiff,
            onChanged: (v) => setState(() => onlyDiff = v),
          ),
        if (compare) _summary(context),
        if (compare) _wordCompare(context),
        ...(compare ? _compareList(context) : _rulesList(context)),
        const SizedBox(height: 24),
        Text('WALS Online (Dryer & Haspelmath 2013, CC BY 4.0) · Grambank (2023, CC BY 4.0)',
            style: Theme.of(context).textTheme.labelSmall),
      ]),
    );
  }

  /// Key word-order facts side by side.
  Widget _summary(BuildContext context) {
    const keys = ['81A', '82A', '83A', '85A', '86A', '87A', '88A', '89A', '90A', '92A', '26A', '49A', '30A', '37A', '38A', '69A'];
    final rows = <TableRow>[];
    for (final k in keys) {
      final p = app.grammar.params.where((p) => p.id == k).firstOrNull;
      if (p == null) continue;
      final va = app.grammar.valueOf(a, k), vb = app.grammar.valueOf(b, k);
      if (va == null && vb == null) continue;
      final diff = va != null && vb != null && va != vb;
      final cs = Theme.of(context).colorScheme;
      rows.add(TableRow(
        decoration: BoxDecoration(color: diff ? cs.errorContainer.withOpacity(0.35) : null),
        children: [
          Padding(padding: const EdgeInsets.all(6), child: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600))),
          Padding(padding: const EdgeInsets.all(6), child: Text(va == null ? '—' : p.describe(va))),
          Padding(padding: const EdgeInsets.all(6), child: Text(vb == null ? '—' : p.describe(vb))),
        ],
      ));
    }
    if (rows.isEmpty) return Padding(padding: const EdgeInsets.all(12), child: Text(tr('noGrammarData')));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Table(
          columnWidths: const {0: FlexColumnWidth(1.3), 1: FlexColumnWidth(), 2: FlexColumnWidth()},
          children: [
            TableRow(children: [
              const SizedBox(),
              Padding(padding: const EdgeInsets.all(6), child: Text(app.langs.name(a), style: Theme.of(context).textTheme.titleSmall)),
              Padding(padding: const EdgeInsets.all(6), child: Text(app.langs.name(b), style: Theme.of(context).textTheme.titleSmall)),
            ]),
            ...rows,
          ],
        ),
      ),
    );
  }

  /// Word structure from the dictionaries: inflected forms of a word in A and its translation in B.
  Widget _wordCompare(BuildContext context) {
    final th = Theme.of(context).textTheme;
    Widget forms(List<Entry> es) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final e in es.take(2)) ...[
            Text('${e.word} (${e.pos})', style: th.titleSmall),
            for (final f in e.forms.take(24)) Text('${f[0]}   ${f[1]}', style: th.bodySmall),
            if (e.forms.isEmpty) Text('—', style: th.bodySmall),
          ]
        ]);
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text('${tr('wordStructure') == 'wordStructure' ? 'Word structure' : tr('wordStructure')}: ${tr('forms')}'),
      children: [
        TextField(
          controller: wordCtl,
          decoration: InputDecoration(hintText: '${tr('searchWord')} (${app.langs.name(a)})'),
          onSubmitted: (w) => setState(() {
            wordA = app.dict.lookup(a, w);
            final t = app.dict.translateWord(a, b, w);
            wordB = t.isEmpty ? [] : app.dict.lookup(b, t.first.targets.first.word);
          }),
        ),
        const SizedBox(height: 8),
        if (app.packs.dbFor(a) == null) NeedsPack(lang: a),
        if (app.packs.dbFor(b) == null) NeedsPack(lang: b),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: forms(wordA)),
          const SizedBox(width: 12),
          Expanded(child: forms(wordB)),
        ]),
      ],
    );
  }

  bool _match(GrammarParam p) =>
      filter.isEmpty || p.name.toLowerCase().contains(filter) || p.area.toLowerCase().contains(filter);

  List<Widget> _rulesList(BuildContext context) {
    final rules = app.grammar.rules(a).where((r) => _match(r.param)).toList();
    if (rules.isEmpty) return [Padding(padding: const EdgeInsets.all(24), child: Text(tr('noGrammarData')))];
    final out = <Widget>[];
    for (final g in _groupOrder) {
      final rs = rules.where((r) => r.param.group == g).toList();
      if (rs.isEmpty) continue;
      out.add(SectionTitle('${_groupName(g)} (${rs.length})'));
      for (final r in rs) {
        out.add(ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(r.param.name),
          subtitle: Text('${r.valueText}   ·   ${r.param.area}   ·   ${r.param.source == 'wals' ? 'WALS ${r.param.id}' : r.param.id}'),
          trailing: r.examples.isNotEmpty ? const Icon(Icons.format_quote) : const Icon(Icons.info_outline),
          onTap: () => _showRule(context, r.param, [r]),
        ));
      }
    }
    return out;
  }

  List<Widget> _compareList(BuildContext context) {
    final cmp = app.grammar.compare(a, b).where((c) => _match(c.param) && (!onlyDiff || c.differs)).toList();
    final cs = Theme.of(context).colorScheme;
    final out = <Widget>[];
    for (final g in _groupOrder) {
      final rs = cmp.where((c) => c.param.group == g).toList();
      if (rs.isEmpty) continue;
      final diffs = rs.where((c) => c.differs).length;
      out.add(SectionTitle('${_groupName(g)} — ${tr('different')}: $diffs / ${rs.length}'));
      for (final c in rs) {
        out.add(Card(
          color: c.differs ? cs.errorContainer.withOpacity(0.25) : null,
          child: InkWell(
            onTap: () => _showRule(context, c.param, [if (c.a != null) c.a!, if (c.b != null) c.b!]),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(c.param.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                  Icon(c.differs ? Icons.compare_arrows : (c.same ? Icons.check : Icons.remove), size: 18),
                ]),
                const SizedBox(height: 4),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: Text('${app.langs.name(a)}: ${c.a?.valueText ?? '—'}')),
                  const SizedBox(width: 8),
                  Expanded(child: Text('${app.langs.name(b)}: ${c.b?.valueText ?? '—'}')),
                ]),
              ]),
            ),
          ),
        ));
      }
    }
    if (out.isEmpty) out.add(Padding(padding: const EdgeInsets.all(24), child: Text(tr('noGrammarData'))));
    return out;
  }

  Future<void> _showRule(BuildContext context, GrammarParam p, List<GrammarRule> rules) async {
    final doc = await app.grammar.doc(p.doc);
    if (!context.mounted) return;
    final th = Theme.of(context).textTheme;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        builder: (context, sc) => ListView(controller: sc, padding: const EdgeInsets.all(20), children: [
          Text(p.name, style: th.titleLarge),
          Text('${p.area} · ${p.source == 'wals' ? 'WALS ${p.id}' : 'Grambank ${p.id}'}', style: th.labelSmall),
          const SizedBox(height: 12),
          for (final r in rules) ...[
            Text('${_langOf(r)}: ${r.valueText}', style: th.titleMedium),
            for (final x in r.examples)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(x.text, style: th.bodyLarge?.copyWith(fontStyle: FontStyle.italic)),
                    _Interlinear(words: x.analyzed.split('\t'), glosses: x.gloss.split('\t')),
                    Text(x.translation, style: th.bodyMedium),
                  ]),
                ),
              ),
          ],
          SectionTitle(tr('codesTitle') == 'codesTitle' ? 'Possible values' : tr('codesTitle')),
          for (final e in p.codes.entries) Text('• ${p.describe(e.key)}${p.source == 'grambank' ? '' : ''}'),
          if (doc != null) ...[
            SectionTitle(doc.title),
            if (doc.author.isNotEmpty) Text(doc.author, style: th.labelSmall),
            const SizedBox(height: 6),
            SelectableText(doc.text, style: th.bodyMedium),
            const SizedBox(height: 8),
            Text(doc.url, style: th.labelSmall),
          ],
        ]),
      ),
    );
  }

  String _langOf(GrammarRule r) {
    final ra = app.grammar.rules(a).where((x) => x.param.id == r.param.id).firstOrNull;
    if (identical(ra?.param, r.param) && ra?.value == r.value && rulesFromA(r)) return app.langs.name(a);
    return app.langs.name(b);
  }

  bool rulesFromA(GrammarRule r) => app.grammar.valueOf(a, r.param.id) == r.value;
}

class _Interlinear extends StatelessWidget {
  const _Interlinear({required this.words, required this.glosses});
  final List<String> words, glosses;
  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Wrap(spacing: 14, runSpacing: 6, children: [
        for (var i = 0; i < words.length; i++)
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(words[i], style: th.bodyMedium),
            Text(i < glosses.length ? glosses[i] : '', style: th.labelSmall),
          ]),
      ]),
    );
  }
}
