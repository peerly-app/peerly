import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peero/design/colors.dart';
import 'package:peero/design/typography.dart';
import 'package:peero/theme.dart';

void main() {
  group('buildAppTheme', () {
    final theme = buildAppTheme();

    test('is a dark Material 3 theme on the design background', () {
      expect(theme.useMaterial3, isTrue);
      expect(theme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, AppColors.bg);
      expect(theme.colorScheme.surface, AppColors.bg);
    });

    test('maps the accent onto the colour scheme', () {
      expect(theme.colorScheme.primary, AppColors.accent);
      expect(theme.colorScheme.onPrimary, AppColors.onAccent);
      expect(theme.colorScheme.secondaryContainer, AppColors.panel2);
      expect(theme.colorScheme.outline, AppColors.border);
      expect(theme.colorScheme.outlineVariant, AppColors.borderSubtle);
    });

    test('uses Inter throughout', () {
      expect(theme.textTheme.bodyMedium!.fontFamily, 'Inter');
      expect(theme.textTheme.bodyMedium!.color, AppColors.text);
    });

    test('flattens the app bar onto the background', () {
      expect(theme.appBarTheme.backgroundColor, AppColors.bg);
      expect(theme.appBarTheme.elevation, 0);
      expect(theme.appBarTheme.surfaceTintColor, Colors.transparent);
      expect(theme.appBarTheme.foregroundColor, AppColors.text);
    });

    test('dividers are hairline and subtle', () {
      expect(theme.dividerTheme.color, AppColors.borderSubtle);
      expect(theme.dividerTheme.thickness, 1);
      expect(theme.dividerTheme.space, 1);
    });

    test('two builds produce equivalent themes', () {
      expect(buildAppTheme().colorScheme.primary, theme.colorScheme.primary);
    });
  });

  group('AppTypography', () {
    test('every style declares a family from the design system', () {
      const styles = {
        'wordmark': AppTypography.wordmark,
        'screenTitle': AppTypography.screenTitle,
        'sectionHeader': AppTypography.sectionHeader,
        'dialogHeading': AppTypography.dialogHeading,
        'profileName': AppTypography.profileName,
        'listTitle': AppTypography.listTitle,
        'chatNameHeader': AppTypography.chatNameHeader,
        'bubbleText': AppTypography.bubbleText,
        'body': AppTypography.body,
        'eyebrow': AppTypography.eyebrow,
        'monoCaption': AppTypography.monoCaption,
        'monoFinePrint': AppTypography.monoFinePrint,
      };

      styles.forEach((name, style) {
        expect(
          style.fontFamily,
          anyOf('Inter', 'JetBrains Mono'),
          reason: name,
        );
        expect(style.fontSize, greaterThan(0), reason: name);
      });
    });

    test('the scale runs largest to smallest', () {
      expect(
        AppTypography.wordmark.fontSize,
        greaterThan(AppTypography.screenTitle.fontSize!),
      );
      expect(
        AppTypography.screenTitle.fontSize,
        greaterThan(AppTypography.listTitle.fontSize!),
      );
      expect(
        AppTypography.body.fontSize,
        greaterThan(AppTypography.monoCaption.fontSize!),
      );
      expect(
        AppTypography.monoCaption.fontSize,
        greaterThan(AppTypography.monoFinePrint.fontSize!),
      );
    });

    test('the mono styles are the only ones using JetBrains Mono', () {
      expect(AppTypography.monoCaption.fontFamily, 'JetBrains Mono');
      expect(AppTypography.monoFinePrint.fontFamily, 'JetBrains Mono');
      expect(AppTypography.body.fontFamily, 'Inter');
    });
  });

  group('AppColors', () {
    test('avatarColorFor is deterministic and stays in the palette', () {
      for (final id in ['a', 'peer-1', 'peer-2', 'some-uuid-4321', '']) {
        final colour = AppColors.avatarColorFor(id);
        expect(AppColors.avatarHues, contains(colour));
        expect(AppColors.avatarColorFor(id), colour);
      }
    });

    test('spreads ids across the whole palette', () {
      final used = {
        for (var i = 0; i < 200; i++) AppColors.avatarColorFor('peer-$i'),
      };

      expect(used.length, AppColors.avatarHues.length);
    });
  });
}
