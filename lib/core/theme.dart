// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import 'settings.dart';

const _seed = Color(0xFF4A7BD0);

ThemeData buildTheme(AppTheme t) {
  switch (t) {
    case AppTheme.light:
      return _base(ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.light));
    case AppTheme.dark:
      // Neutral gray (no blue/purple tint) dark theme.
      const bg = Color(0xFF2B2B2B);
      const surface = Color(0xFF333333);
      const surfaceHigh = Color(0xFF3D3D3D);
      final cs = ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.dark).copyWith(
        surface: bg,
        onSurface: const Color(0xFFE6E6E6),
        surfaceContainerLowest: const Color(0xFF262626),
        surfaceContainerLow: const Color(0xFF2F2F2F),
        surfaceContainer: surface,
        surfaceContainerHigh: surfaceHigh,
        surfaceContainerHighest: const Color(0xFF474747),
        onSurfaceVariant: const Color(0xFFBDBDBD),
        outline: const Color(0xFF8A8A8A),
        outlineVariant: const Color(0xFF4F4F4F),
        surfaceTint: Colors.transparent,
      );
      return _base(cs, scaffold: bg);
    case AppTheme.oled:
      // Pure black for OLED screens.
      final cs = ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.dark).copyWith(
        surface: Colors.black,
        onSurface: const Color(0xFFE0E0E0),
        surfaceContainerLowest: Colors.black,
        surfaceContainerLow: const Color(0xFF0A0A0A),
        surfaceContainer: const Color(0xFF101010),
        surfaceContainerHigh: const Color(0xFF161616),
        surfaceContainerHighest: const Color(0xFF1E1E1E),
        onSurfaceVariant: const Color(0xFFB0B0B0),
        outline: const Color(0xFF6E6E6E),
        outlineVariant: const Color(0xFF2A2A2A),
        surfaceTint: Colors.transparent,
      );
      return _base(cs, scaffold: Colors.black);
  }
}

ThemeData _base(ColorScheme cs, {Color? scaffold}) => ThemeData(
      colorScheme: cs,
      useMaterial3: true,
      scaffoldBackgroundColor: scaffold ?? cs.surface,
      canvasColor: scaffold ?? cs.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scaffold ?? cs.surface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      // Visible focus for keyboard / TV remote navigation.
      focusColor: cs.primary.withOpacity(0.28),
      cardTheme: CardThemeData(
        color: cs.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 6),
      ),
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
    );
