// ignore_for_file: deprecated_member_use
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:ipareader_ffi/ipareader_ffi.dart';

import '../core/config.dart';
import '../core/settings.dart';
import '../translate/nmt.dart';
import 'home.dart';
import 'widgets.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      title: tr('settings'),
      child: AnimatedBuilder(
        animation: Listenable.merge([app.settings, app.updater, app.langs]),
        builder: (context, _) {
          final s = app.settings;
          final th = Theme.of(context).textTheme;
          return ListView(padding: const EdgeInsets.all(16), children: [
            SectionTitle(tr('theme')),
            SegmentedButton<AppTheme>(
              segments: [
                ButtonSegment(value: AppTheme.light, label: Text(tr('light')), icon: const Icon(Icons.light_mode)),
                ButtonSegment(value: AppTheme.dark, label: Text(tr('dark')), icon: const Icon(Icons.dark_mode)),
                ButtonSegment(value: AppTheme.oled, label: Text(tr('oled')), icon: const Icon(Icons.brightness_1)),
              ],
              selected: {s.theme},
              onSelectionChanged: (v) => s.theme = v.first,
            ),
            SectionTitle(tr('appLanguage')),
            Text(tr('appLanguageHelp'), style: th.bodySmall),
            const SizedBox(height: 6),
            OutlinedButton(
              onPressed: () => _pickUiLanguage(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(children: [
                  Expanded(child: Text('${app.langs.autonym(app.langs.locale) ?? app.langs.locale}  ·  ${app.langs.name(app.langs.locale)}')),
                  const Icon(Icons.arrow_drop_down),
                ]),
              ),
            ),
            SectionTitle(tr('voice')),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'female', label: Text(tr('female'))),
                ButtonSegment(value: 'male', label: Text(tr('male'))),
              ],
              selected: {s.voice},
              onSelectionChanged: (v) => s.voice = v.first,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${tr('speed')}: ${s.speechSpeed.toStringAsFixed(2)}×'),
              subtitle: Slider(min: 0.5, max: 2.0, divisions: 30, value: s.speechSpeed, onChanged: (v) => s.speechSpeed = v),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${tr('pitch')}: ${s.pitchShift.toStringAsFixed(1)}'),
              subtitle: Slider(min: -8, max: 8, divisions: 32, value: s.pitchShift, onChanged: (v) => s.pitchShift = v),
              trailing: SpeakButton(onSpeak: () => app.speech.speakIpa('ˈjuːnɪvɜːsəl ˈtɹænsleɪtə')),
            ),
            SectionTitle(tr('translationModel')),
            if (!NmtModel.supportedOnThisPlatform) Text(tr('modelNotOnPlatform'), style: th.bodySmall),
            for (final m in AppConfig.instance.models.where((_) => NmtModel.supportedOnThisPlatform))
              RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                value: m.id,
                groupValue: app.translator.activeSpec?.id,
                onChanged: NmtModel.isInstalled(m) ? (v) => s.translationModel = v : null,
                title: Text(m.name),
                subtitle: Text(NmtModel.isInstalled(m) ? m.license : '${tr('notInstalled')} · ${m.license}'),
              ),
            SectionTitle(tr('updates')),
            Text('${tr('version')} ${app.updater.currentVersion}', style: th.bodyMedium),
            if (Platform.isIOS) Text(tr('iosUpdate'), style: th.bodySmall),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('autoUpdate')),
              value: s.autoCheckUpdates,
              onChanged: (v) => s.autoCheckUpdates = v,
            ),
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              OutlinedButton.icon(
                onPressed: app.updater.checking ? null : app.updater.check,
                icon: const Icon(Icons.system_update),
                label: Text(tr('checkUpdates')),
              ),
              if (app.updater.available != null)
                FilledButton.icon(
                  onPressed: app.updater.progress != null ? null : () => app.updater.install(app.updater.available!),
                  icon: const Icon(Icons.download),
                  label: Text('${tr('install')} ${app.updater.available!.version}'),
                ),
            ]),
            if (app.updater.progress != null) LinearProgressIndicator(value: app.updater.progress),
            if (app.updater.status == 'upToDate') Text(tr('upToDate')),
            if (app.updater.status?.startsWith('error:') == true)
              Text(app.updater.status!.substring(6), style: TextStyle(color: Theme.of(context).colorScheme.error)),
            if (app.updater.available?.notes.isNotEmpty == true)
              Padding(padding: const EdgeInsets.only(top: 8), child: Text(app.updater.available!.notes, style: th.bodySmall)),
            SectionTitle(tr('sources')),
            Text(
              'Speech: IPAReader ${_iprVersion()} (github.com/GMWester/IPAReader, AGPL-3.0)\n'
              'Dictionary: Wiktionary via Wiktextract / kaikki.org (CC BY-SA 4.0)\n'
              'Grammar: WALS Online (CC BY 4.0), Grambank (CC BY 4.0)\n'
              'Languages: Glottolog (CC BY 4.0), Unicode CLDR (Unicode License)\n'
              'Characters: Unicode ${app.chars.unicodeVersion}\n'
              'Translation: NLLB-200 (Meta, CC BY-NC 4.0) or M2M-100 (Meta, MIT), run with ONNX Runtime',
              style: th.bodySmall,
            ),
          ]);
        },
      ),
    );
  }

  String _iprVersion() {
    try {
      return IpaReader.version;
    } catch (_) {
      return '';
    }
  }

  Future<void> _pickUiLanguage(BuildContext context) async {
    final r = await showDialog<String>(context: context, builder: (_) => const _UiLangDialog());
    if (r != null) {
      app.settings.appLanguage = r;
      await app.langs.setLocale(r);
    }
  }
}

class _UiLangDialog extends StatefulWidget {
  const _UiLangDialog();
  @override
  State<_UiLangDialog> createState() => _UiLangDialogState();
}

class _UiLangDialogState extends State<_UiLangDialog> {
  String q = '';
  @override
  Widget build(BuildContext context) {
    final list = app.langs.uiLocales.where((u) {
      if (q.isEmpty) return true;
      final f = q.toLowerCase();
      return u.ownName.toLowerCase().contains(f) || u.code.contains(f) || app.langs.name(u.code).toLowerCase().contains(f);
    }).toList();
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 520, maxHeight: MediaQuery.of(context).size.height * 0.9),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              autofocus: true,
              decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tr('searchLanguage')),
              onChanged: (v) => setState(() => q = v),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (c, i) => ListTile(
                title: Text(list[i].ownName),
                subtitle: Text('${app.langs.name(list[i].code)} · ${list[i].code}'),
                selected: list[i].code == app.langs.locale,
                onTap: () => Navigator.pop(context, list[i].code),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
