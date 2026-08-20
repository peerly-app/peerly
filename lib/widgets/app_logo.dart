import 'package:flutter/material.dart';

import '../design/colors.dart';

class AppLogo extends StatelessWidget {
  final double size;

  final bool onDark;

  const AppLogo({super.key, this.size = 104, this.onDark = false});

  @override
  Widget build(BuildContext context) {
    final tileColor = onDark ? AppColors.panel : AppColors.accent;
    final ringColor = onDark ? AppColors.accent : AppColors.bg;
    final radius = size * 0.227;
    final strokeWidth = size * 0.0625;

    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: tileColor,
        borderRadius: BorderRadius.circular(radius),
        border: onDark ? Border.all(color: AppColors.border) : null,
      ),
      child: Stack(
        children: [
          _ring(
            diameter: size * 0.75,
            color: ringColor,
            strokeWidth: strokeWidth,
          ),
          _ring(
            diameter: size * 1.25,
            color: ringColor,
            strokeWidth: strokeWidth,
            opacity: 0.55,
          ),
          _dot(diameter: size * 0.22, color: ringColor),
        ],
      ),
    );
  }

  Widget _ring({
    required double diameter,
    required Color color,
    required double strokeWidth,
    double opacity = 1.0,
  }) {
    return Positioned(
      left: -diameter / 2,
      bottom: -diameter / 2,
      child: Opacity(
        opacity: opacity,
        child: Container(
          width: diameter,
          height: diameter,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color, width: strokeWidth),
          ),
        ),
      ),
    );
  }

  Widget _dot({required double diameter, required Color color}) {
    return Positioned(
      left: -diameter / 2,
      bottom: -diameter / 2,
      child: Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
    );
  }
}

class AppLogoLockup extends StatelessWidget {
  final double iconSize;
  final double wordmarkFontSize;

  const AppLogoLockup({
    super.key,
    this.iconSize = 44,
    this.wordmarkFontSize = 22,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppLogo(size: iconSize),
        const SizedBox(width: 14),
        Text.rich(
          TextSpan(
            style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w800,
              fontSize: wordmarkFontSize,
              letterSpacing: -0.02 * wordmarkFontSize,
              color: AppColors.text,
            ),
            children: [
              const TextSpan(text: 'Local'),
              TextSpan(
                text: 'Msg',
                style: TextStyle(color: AppColors.accent),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
