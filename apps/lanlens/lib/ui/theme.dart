import 'package:flutter/material.dart';

/// LanLens brand: deep teal "lens" on a navy field.
const kBrandSeed = Color(0xFF00897B);
const kBrandNavy = Color(0xFF0B1F33);

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: kBrandSeed, brightness: brightness);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    appBarTheme: AppBarTheme(
      backgroundColor: brightness == Brightness.dark ? kBrandNavy : scheme.surface,
      centerTitle: false,
    ),
    cardTheme: const CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
    ),
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
  );
}
