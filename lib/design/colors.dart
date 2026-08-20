import 'package:flutter/material.dart';

abstract final class AppColors {
  static const bg = Color(0xFF0C0D10);
  static const panel = Color(0xFF141619);
  static const panel2 = Color(0xFF1F2226);
  static const border = Color(0xFF303338);
  static const borderSubtle = Color(0xFF26292E);
  static const text = Color(0xFFF3F2EF);
  static const textDim = Color(0xFF8D939B);

  static const accent = Color(0xFF00D4D5);
  static const accentDeep = Color(0xFF00898B);
  static const accentSoft = Color(0xFF002B2B);
  static const onAccent = Color(0xFF031010);

  static const avatarHues = [
    Color(0xFFC8664E),
    Color(0xFFA58100),
    Color(0xFF429C5A),
    Color(0xFF418AD1),
    Color(0xFF9372C8),
  ];

  static Color avatarColorFor(String id) {
    final index = id.hashCode.abs() % avatarHues.length;
    return avatarHues[index];
  }
}
