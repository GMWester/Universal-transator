// ignore_for_file: deprecated_member_use
import 'dart:io';

import 'package:flutter/material.dart';

import 'characters_page.dart';
import 'dictionary_page.dart';
import 'downloads_page.dart';
import 'grammar_page.dart';
import 'settings_page.dart';
import 'translate_page.dart';
import 'urban_page.dart';
import 'widgets.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String tab = 'translate';
  final Set<String> _visited = {'translate'}; // pages are built the first time they are opened

  @override
  void initState() {
    super.initState();
    if (!app.settings.dataPromptShown && app.packs.installedIds.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _firstRunPrompt());
    }
    // Dictionary updates (newer packs published): tell the user once per start.
    Future.delayed(const Duration(seconds: 5), _checkDataUpdates);
    if (app.settings.autoCheckUpdates && !Platform.isIOS) {
      Future.delayed(const Duration(seconds: 3), _autoUpdateCheck);
    }
  }

  void _go(String id) => setState(() {
        tab = id;
        _visited.add(id);
      });

  /// First start: offer to pick which dictionaries to download.
  Future<void> _firstRunPrompt() async {
    app.settings.dataPromptShown = true;
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('firstRunTitle')),
        content: Text(tr('firstRunBody')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('later'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('chooseData'))),
        ],
      ),
    );
    if (go == true && mounted) _go('downloads');
  }

  Future<void> _checkDataUpdates() async {
    if (app.packs.installedIds.isEmpty) return;
    await app.packs.refreshInstalledEditions();
    final n = app.packs.outdatedPacks().length;
    if (n == 0 || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 12),
      content: Text(tr('dataUpdates', ['$n'])),
      action: SnackBarAction(
          label: tr('updateAllShort'),
          onPressed: () => app.packs.installAll(app.packs.outdatedPacks(), updates: true)),
    ));
  }

  Future<void> _autoUpdateCheck() async {
    final r = await app.updater.check();
    if (r == null || !mounted || app.settings.skippedVersion == r.version) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 12),
      content: Text(tr('updateAvailable', [r.version])),
      action: SnackBarAction(label: tr('install'), onPressed: () => app.updater.install(r)),
    ));
  }

  @override
  Widget build(BuildContext context) =>
      AnimatedBuilder(animation: app.settings, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final tabs = <(String, IconData, String, Widget)>[
      ('translate', Icons.translate, tr('translate'), const TranslatePage()),
      ('dictionary', Icons.menu_book, tr('dictionary'), const DictionaryPage()),
      if (app.settings.urbanDictionary)
        ('urban', Icons.forum_outlined, tr('urbanTab'), const UrbanPage()),
      ('grammar', Icons.account_tree, tr('grammar'), const GrammarPage()),
      ('characters', Icons.abc, tr('characters'), const CharactersPage()),
      ('downloads', Icons.download_for_offline, tr('downloads'), const DownloadsPage()),
      ('settings', Icons.settings, tr('settings'), const SettingsPage()),
    ];
    var index = tabs.indexWhere((t) => t.$1 == tab);
    if (index < 0) index = 0;
    final items = [for (final t in tabs) (t.$2, t.$3)];
    final wide = MediaQuery.of(context).size.width >= 720;
    // Rebuild every page when the app language changes.
    final body = KeyedSubtree(
      key: ValueKey(app.settings.appLanguage),
      child: IndexedStack(index: index, children: [
        for (final t in tabs) _visited.contains(t.$1) ? KeyedSubtree(key: ValueKey(t.$1), child: t.$4) : SizedBox.shrink(key: ValueKey(t.$1)),
      ]),
    );
    if (wide) {
      return Scaffold(
        body: SafeArea(
          child: Row(children: [
            NavigationRail(
              selectedIndex: index,
              labelType: NavigationRailLabelType.all,
              onDestinationSelected: (i) => _go(tabs[i].$1),
              destinations: [
                for (final it in items)
                  NavigationRailDestination(icon: Icon(it.$1), label: Text(it.$2)),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ]),
        ),
      );
    }
    return Scaffold(
      body: SafeArea(child: body),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        onDestinationSelected: (i) => _go(tabs[i].$1),
        destinations: [for (final it in items) NavigationDestination(icon: Icon(it.$1), label: it.$2)],
      ),
    );
  }
}

/// Common page frame with a title bar.
class PageFrame extends StatelessWidget {
  const PageFrame({super.key, required this.title, required this.child, this.actions});
  final String title;
  final Widget child;
  final List<Widget>? actions;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title), actions: actions),
        body: child,
      );
}
