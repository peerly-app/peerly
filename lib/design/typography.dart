import 'package:flutter/material.dart';

import 'colors.dart';

abstract final class AppTypography {
  static const _inter = 'Inter';
  static const _mono = 'JetBrains Mono';

  static const wordmark = TextStyle(
    fontFamily: _inter,
    fontSize: 60,
    fontWeight: FontWeight.w800,
    letterSpacing: -1.2,
    color: AppColors.text,
  );

  static const screenTitle = TextStyle(
    fontFamily: _inter,
    fontSize: 34,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.7,
    color: AppColors.text,
  );

  static const sectionHeader = TextStyle(
    fontFamily: _inter,
    fontSize: 30,
    fontWeight: FontWeight.w700,
    color: AppColors.text,
  );

  static const dialogHeading = TextStyle(
    fontFamily: _inter,
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: AppColors.text,
  );

  static const profileName = TextStyle(
    fontFamily: _inter,
    fontSize: 17,
    fontWeight: FontWeight.w700,
    color: AppColors.text,
  );

  static const listTitle = TextStyle(
    fontFamily: _inter,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.text,
  );

  static const chatNameHeader = TextStyle(
    fontFamily: _inter,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: AppColors.text,
  );

  static const bubbleText = TextStyle(
    fontFamily: _inter,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.35,
  );

  static const body = TextStyle(
    fontFamily: _inter,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textDim,
  );

  static const eyebrow = TextStyle(
    fontFamily: _inter,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.7,
    color: AppColors.textDim,
  );

  static const monoCaption = TextStyle(
    fontFamily: _mono,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.textDim,
  );

  static const monoFinePrint = TextStyle(
    fontFamily: _mono,
    fontSize: 11,
    fontWeight: FontWeight.w400,
    color: AppColors.textDim,
  );
}
