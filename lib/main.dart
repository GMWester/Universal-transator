// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'dart:io';

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'app_state.dart';
import 'core/theme.dart';
import 'ui/home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Diagnostics: UT_PERF=1 prints every frame that takes longer than 16 ms.
  if (Platform.environment['UT_PERF'] == '1') {
    SchedulerBinding.instance.addTimingsCallback((timings) {
      for (final t in timings) {
        final ms = t.totalSpan.inMicroseconds / 1000;
        if (ms > 16) {
          stdout.writeln('slow frame: total ${ms.toStringAsFixed(1)} ms, '
              'build ${(t.buildDuration.inMicroseconds / 1000).toStringAsFixed(1)} ms');
        }
      }
    });
  }
  final state = await AppState.init();
  runApp(UniversalTranslatorApp(state: state));
}

const _rtl = {'ar', 'he', 'fa', 'ur', 'ps', 'sd', 'ug', 'yi', 'dv', 'ckb', 'ks'};

class UniversalTranslatorApp extends StatelessWidget {
  const UniversalTranslatorApp({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state.settings,
      builder: (context, _) {
        final lang = state.settings.appLanguage.split('-').first;
        return MaterialApp(
          title: state.s.t('appTitle'),
          debugShowCheckedModeBanner: false,
          theme: buildTheme(state.settings.theme),
          // D-pad / TV remote: OK/Select activates the focused control.
          shortcuts: {
            ...WidgetsApp.defaultShortcuts,
            const SingleActivator(LogicalKeyboardKey.select): const ActivateIntent(),
            const SingleActivator(LogicalKeyboardKey.gameButtonA): const ActivateIntent(),
          },
          builder: (context, child) => Directionality(
            textDirection: _rtl.contains(lang) ? TextDirection.rtl : TextDirection.ltr,
            child: child!,
          ),
          home: const HomePage(),
        );
      },
    );
  }
}
