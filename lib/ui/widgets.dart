// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/languages.dart';
import '../data/normalize.dart';

AppState get app => AppState.I;
String tr(String k, [List<String> a = const []]) => app.s.t(k, a);

/// Button that shows a language name (in the app language) and opens the picker.
class LanguageButton extends StatelessWidget {
  const LanguageButton({
    super.key,
    required this.code,
    required this.onChanged,
    this.label,
    this.restrictTo,
    this.highlight,
  });
  final String code;
  final ValueChanged<String> onChanged;
  final String? label;
  final Set<String>? restrictTo;
  final Set<String>? highlight;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: app.langs,
      builder: (context, _) => OutlinedButton(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          alignment: AlignmentDirectional.centerStart,
        ),
        onPressed: () async {
          final r = await pickLanguage(context,
              title: label ?? tr('chooseLanguage'), restrictTo: restrictTo, highlight: highlight, current: code);
          if (r != null) onChanged(r);
        },
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (label != null)
                Text(label!, style: Theme.of(context).textTheme.labelSmall),
              Text(app.langs.name(code), overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium),
            ]),
          ),
          const Icon(Icons.arrow_drop_down),
        ]),
      ),
    );
  }
}

Future<String?> pickLanguage(BuildContext context,
    {required String title, Set<String>? restrictTo, Set<String>? highlight, String? current}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _LanguageDialog(title: title, restrictTo: restrictTo, highlight: highlight, current: current),
  );
}

class _LanguageDialog extends StatefulWidget {
  const _LanguageDialog({required this.title, this.restrictTo, this.highlight, this.current});
  final String title;
  final Set<String>? restrictTo, highlight;
  final String? current;
  @override
  State<_LanguageDialog> createState() => _LanguageDialogState();
}

class _LanguageDialogState extends State<_LanguageDialog> {
  String q = '';
  bool onlyHighlighted = false;

  @override
  Widget build(BuildContext context) {
    final restrict = onlyHighlighted && widget.highlight != null ? widget.highlight : widget.restrictTo;
    var list = app.langs.search(q, restrictTo: restrict);
    if (q.isEmpty && widget.highlight != null && !onlyHighlighted) {
      final h = list.where((l) => widget.highlight!.contains(l.code)).toList();
      list = [...h, ...list.where((l) => !widget.highlight!.contains(l.code))];
    }
    final size = MediaQuery.of(context).size;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560, maxHeight: size.height * 0.9),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              autofocus: true,
              decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tr('searchLanguage')),
              onChanged: (v) => setState(() => q = v),
            ),
          ),
          if (widget.highlight != null && widget.highlight!.isNotEmpty)
            SwitchListTile(
              dense: true,
              title: Text(tr('installed')),
              value: onlyHighlighted,
              onChanged: (v) => setState(() => onlyHighlighted = v),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text('${list.length}', style: Theme.of(context).textTheme.labelSmall),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: list.length,
              itemExtent: 60,
              itemBuilder: (context, i) => _tile(context, list[i]),
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('cancel'))),
          ),
        ]),
      ),
    );
  }

  Widget _tile(BuildContext context, Language l) {
    final name = app.langs.name(l.code);
    final auto = app.langs.autonym(l.code);
    final sub = [
      if (auto != null && foldKey(auto) != foldKey(name)) auto,
      if (l.englishName != name) l.englishName,
      l.code,
      if (l.family != null) l.family!,
    ].join(' · ');
    return ListTile(
      selected: l.code == widget.current,
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: widget.highlight?.contains(l.code) == true ? const Icon(Icons.offline_pin, size: 20) : null,
      onTap: () => Navigator.pop(context, l.code),
    );
  }
}

class SpeakButton extends StatefulWidget {
  const SpeakButton({super.key, required this.onSpeak, this.tooltip});
  final Future<void> Function() onSpeak;
  final String? tooltip;
  @override
  State<SpeakButton> createState() => _SpeakButtonState();
}

class _SpeakButtonState extends State<SpeakButton> {
  bool busy = false;
  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: widget.tooltip ?? tr('speak'),
        icon: busy
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.volume_up),
        onPressed: busy
            ? null
            : () async {
                setState(() => busy = true);
                try {
                  await widget.onSpeak();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${tr('error')}: $e')));
                  }
                } finally {
                  if (mounted) setState(() => busy = false);
                }
              },
      );
}

/// Shown when a language's offline Wiktionary pack is missing.
class NeedsPack extends StatelessWidget {
  const NeedsPack({super.key, required this.lang});
  final String lang;
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: app.packs,
      builder: (context, _) {
        final p = app.packs.packFor('en', lang);
        final st = p == null ? null : app.packs.active[p.id];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('needDownload', [app.langs.name(lang)])),
              if (p != null && app.packs.failed[p.id] != null)
                Text('${tr('error')}: ${app.packs.failed[p.id]}',
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 12),
              if (st != null) ...[
                Row(children: [
                  Expanded(child: LinearProgressIndicator(value: st.fraction)),
                  IconButton(
                      tooltip: tr('cancel'), icon: const Icon(Icons.close), onPressed: () => app.packs.cancel(p!.id)),
                ]),
                if (st.error != null) Text(st.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ] else
                FilledButton.icon(
                  icon: const Icon(Icons.download),
                  label: Text(p == null ? tr('download') : '${tr('download')} (${fmtBytes(p.size)})'),
                  onPressed: () async {
                    try {
                      await app.packs.installLanguage(lang);
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                      }
                    }
                  },
                ),
            ]),
          ),
        );
      },
    );
  }
}

String fmtBytes(int b) {
  if (b < 1024) return '$b B';
  if (b < 1 << 20) return '${(b / 1024).toStringAsFixed(0)} KB';
  if (b < 1 << 30) return '${(b / (1 << 20)).toStringAsFixed(1)} MB';
  return '${(b / (1 << 30)).toStringAsFixed(2)} GB';
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 6),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)),
      );
}
