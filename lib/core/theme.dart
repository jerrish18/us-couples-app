import 'package:flutter/material.dart';

ThemeData usTheme(Brightness brightness) {
  final colors = ColorScheme.fromSeed(seedColor: const Color(0xffb94d65), brightness: brightness);
  return ThemeData(
    useMaterial3: true,
    colorScheme: colors,
    scaffoldBackgroundColor: brightness == Brightness.light ? const Color(0xfffff8f3) : const Color(0xff21191d),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.all(18),
    ),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
      minimumSize: const Size(48, 52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    )),
  );
}
