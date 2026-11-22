// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/characters.dart';
import 'home.dart';
import 'widgets.dart';

/// All characters of a language: its alphabet (CLDR), letters used in its
/// dictionary, and every Unicode character of its scripts.
class CharactersPage extends StatefulWidget {
  const CharactersPage({super.key});
  @override
  State<CharactersPage> createState() => _CharactersPageState();
}

class _CharactersPageState extends State<CharactersPage> {
  late String lang = app.settings.lastFrom;
  String? script;

  @override
  Widget build(BuildContext context) {
    final l = app.langs.byCode(lang);
    final groups = app.chars.groupsFor(lang, packChars: app.dict.langInfo(lang)['chars']);
    final scripts = app.chars.scriptsFor(l);
    final sel = script != null && app.chars.scripts[script] != null
        ? app.chars.scripts[script]!
        : (scripts.isNotEmpty ? scripts.first : null);
    return PageFrame(
      title: tr('characters'),
      child: CustomScrollView(slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              LanguageButton(code: lang, onChanged: (c) => setState(() {
                    lang = c;
                    script = null;
                  })),
              if (l?.scripts.isNotEmpty == true)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Scripts: ${l!.scripts.map((s) => app.chars.scripts[s]?.name ?? s).join(', ')}',
                      style: Theme.of(context).textTheme.bodySmall),
                ),
              for (final g in groups) ...[
                SectionTitle('${g.title} (${g.chars.length})'),
                _grid(context, g.chars, big: true),
              ],
              if (groups.isEmpty && scripts.isEmpty)
                Padding(padding: const EdgeInsets.all(16), child: NeedsPack(lang: lang)),
              if (scripts.isNotEmpty) ...[
                SectionTitle(tr('scriptChars', [sel!.name])),
                Wrap(spacing: 6, children: [
                  for (final s in {...scripts, ...app.chars.scriptsFor(null)})
                    ChoiceChip(
                      label: Text('${s.name} (${s.count})'),
                      selected: s.code == sel.code,
                      onSelected: (_) => setState(() => script = s.code),
                    ),
                  ActionChip(
                    avatar: const Icon(Icons.list, size: 18),
                    label: const Text('…'),
                    onPressed: () async {
                      final keys = app.chars.scripts.values.toList()..sort((a, b) => a.name.compareTo(b.name));
                      final r = await showDialog<String>(
                        context: context,
                        builder: (c) => SimpleDialog(children: [
                          for (final s in keys)
                            SimpleDialogOption(
                                child: Text('${s.name} (${s.count})'), onPressed: () => Navigator.pop(c, s.code)),
                        ]),
                      );
                      if (r != null) setState(() => script = r);
                    },
                  ),
                ]),
                const SizedBox(height: 8),
              ],
            ]),
          ),
        ),
        if (sel != null)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            sliver: _ScriptGrid(info: sel, lang: lang),
          ),
      ]),
    );
  }

  Widget _grid(BuildContext context, List<String> chars, {bool big = false}) => Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [for (final c in chars) CharTile(char: c, lang: lang, big: big)],
      );
}

class _ScriptGrid extends StatelessWidget {
  const _ScriptGrid({required this.info, required this.lang});
  final ScriptInfo info;
  final String lang;
  @override
  Widget build(BuildContext context) {
    final cps = <int>[];
    for (final r in info.ranges) {
      for (var c = r[0]; c <= r[1]; c++) {
        cps.add(c);
      }
    }
    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 64, mainAxisSpacing: 6, crossAxisSpacing: 6),
      delegate: SliverChildBuilderDelegate(
        (context, i) => CharTile(char: String.fromCharCode(cps[i]), lang: lang),
        childCount: cps.length,
      ),
    );
  }
}

class CharTile extends StatelessWidget {
  const CharTile({super.key, required this.char, required this.lang, this.big = false});
  final String char, lang;
  final bool big;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: big ? 56 : null,
      height: big ? 56 : null,
      child: Material(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _details(context),
          child: Center(child: Text(char, style: const TextStyle(fontSize: 26))),
        ),
      ),
    );
  }

  Future<void> _details(BuildContext context) async {
    final cp = char.runes.toList();
    final names = <String>[];
    for (final c in cp) {
      names.add('U+${c.toRadixString(16).toUpperCase().padLeft(4, '0')}  ${await app.chars.charName(c) ?? ''}');
    }
    if (!context.mounted) return;
    final ipa = app.speech.textToIpa(lang, char);
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(char, style: const TextStyle(fontSize: 64), textAlign: TextAlign.center),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final n in names) SelectableText(n),
          if (ipa.isNotEmpty) Text('IPA: $ipa'),
        ]),
        actions: [
          if (ipa.isNotEmpty) SpeakButton(onSpeak: () => app.speech.speakIpa(ipa)),
          IconButton(
              icon: const Icon(Icons.copy),
              onPressed: () => Clipboard.setData(ClipboardData(text: char))),
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK')),
        ],
      ),
    );
  }
}
