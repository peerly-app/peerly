import 'package:flutter/material.dart';

import 'design/colors.dart';

ThemeData buildAppTheme() {
  final colorScheme =
      ColorScheme.fromSeed(
        seedColor: AppColors.accent,
        brightness: Brightness.dark,
      ).copyWith(
        surface: AppColors.bg,
        primary: AppColors.accent,
        onPrimary: AppColors.onAccent,
        secondaryContainer: AppColors.panel2,
        outline: AppColors.border,
        outlineVariant: AppColors.borderSubtle,
      );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: 'Inter',
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: colorScheme,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      surfaceTintColor: Colors.transparent,
      foregroundColor: AppColors.text,
      elevation: 0,
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.borderSubtle,
      thickness: 1,
      space: 1,
    ),
    textTheme: const TextTheme(
      bodyMedium: TextStyle(fontFamily: 'Inter', color: AppColors.text),
    ).apply(bodyColor: AppColors.text, displayColor: AppColors.text),
  );
}
