// ignore_for_file: deprecated_member_use
import 'dart:io';

import 'package:flutter/material.dart';

import 'characters_page.dart';
import 'dictionary_page.dart';
import 'downloads_page.dart';
import 'grammar_page.dart';
import 'settings_page.dart';
import 'translate_page.dart';
import 'widgets.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int index = 0;

  @override
  void initState() {
    super.initState();
    if (!app.settings.dataPromptShown && app.packs.installedIds.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _firstRunPrompt());
    }
    if (app.settings.autoCheckUpdates && !Platform.isIOS) {
      Future.delayed(const Duration(seconds: 3), _autoUpdateCheck);
    }
  }

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
    if (go == true && mounted) setState(() => index = 4);
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
    final items = [
      (Icons.translate, tr('translate')),
      (Icons.menu_book, tr('dictionary')),
      (Icons.account_tree, tr('grammar')),
      (Icons.abc, tr('characters')),
      (Icons.download_for_offline, tr('downloads')),
      (Icons.settings, tr('settings')),
    ];
    final pages = const [
      TranslatePage(),
      DictionaryPage(),
      GrammarPage(),
      CharactersPage(),
      DownloadsPage(),
      SettingsPage(),
    ];
    final wide = MediaQuery.of(context).size.width >= 720;
    // Rebuild every page when the app language changes.
    final body = KeyedSubtree(
      key: ValueKey(app.settings.appLanguage),
      child: IndexedStack(index: index, children: pages),
    );
    if (wide) {
      return Scaffold(
        body: SafeArea(
          child: Row(children: [
            NavigationRail(
              selectedIndex: index,
              labelType: NavigationRailLabelType.all,
              onDestinationSelected: (i) => setState(() => index = i),
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
        onDestinationSelected: (i) => setState(() => index = i),
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
