// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../translate/nmt.dart';
import '../translate/translator.dart';
import 'home.dart';
import 'widgets.dart';

class TranslatePage extends StatefulWidget {
  const TranslatePage({super.key});
  @override
  State<TranslatePage> createState() => _TranslatePageState();
}

class _TranslatePageState extends State<TranslatePage> {
  late String from = app.settings.lastFrom, to = app.settings.lastTo;
  final input = TextEditingController();
  TranslationResult? result;
  String resultIpa = '';
  bool busy = false;
  String? error;

  Future<void> _go() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final r = await app.translator.translate(input.text, from, to);
      final ipa = app.speech.textToIpa(to, r.text);
      setState(() {
        result = r;
        resultIpa = ipa;
      });
    } catch (e) {
      setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final installed = app.packs.installedLanguages();
    return PageFrame(
      title: tr('translate'),
      child: AnimatedBuilder(
        animation: Listenable.merge([app.translator, app.packs, app.settings]),
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(children: [
              Expanded(
                child: LanguageButton(
                  code: from,
                  label: tr('from'),
                  highlight: installed,
                  onChanged: (c) => setState(() => app.settings.lastFrom = from = c),
                ),
              ),
              IconButton(
                tooltip: tr('swap'),
                icon: const Icon(Icons.swap_horiz),
                onPressed: () => setState(() {
                  final t = from;
                  from = to;
                  to = t;
                  app.settings.lastFrom = from;
                  app.settings.lastTo = to;
                  if (result != null) {
                    input.text = result!.text;
                    result = null;
                  }
                }),
              ),
              Expanded(
                child: LanguageButton(
                  code: to,
                  label: tr('to'),
                  highlight: installed,
                  onChanged: (c) => setState(() => app.settings.lastTo = to = c),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: input,
              minLines: 4,
              maxLines: 12,
              decoration: InputDecoration(
                hintText: tr('enterText'),
                suffixIcon: SpeakButton(onSpeak: () => app.speech.speakText(from, input.text)),
              ),
              onSubmitted: (_) => _go(),
            ),
            const SizedBox(height: 12),
            Row(children: [
              FilledButton.icon(
                onPressed: busy ? null : _go,
                icon: busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.translate),
                label: Text(tr('translateAction')),
              ),
              const SizedBox(width: 12),
              if (app.translator.loading) Text(tr('loadingModel')),
            ]),
            if (app.translator.activeSpec == null && NmtModel.supportedOnThisPlatform)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(tr('modelMissing'), style: Theme.of(context).textTheme.bodySmall),
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            if (result != null) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SelectableText(result!.text, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Row(children: [
                      SpeakButton(onSpeak: () => app.speech.speakText(to, result!.text)),
                      IconButton(
                        tooltip: tr('copy'),
                        icon: const Icon(Icons.copy),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: result!.text));
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('copied'))));
                        },
                      ),
                      const Spacer(),
                      Flexible(
                        child: Text(
                          result!.notes.where((n) => !n.startsWith('missing:') && n != 'approximate').join(' '),
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    ]),
                    if (result!.method == 'dictionary')
                      Text(tr('approximate'), style: Theme.of(context).textTheme.bodySmall),
                    SelectableText('IPA: $resultIpa',
                        style: Theme.of(context).textTheme.bodySmall),
                  ]),
                ),
              ),
              for (final n in result!.notes.where((n) => n.startsWith('missing:')))
                NeedsPack(lang: n.substring(8)),
            ],
          ],
        ),
      ),
    );
  }
}
