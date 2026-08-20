import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peero/l10n/app_localizations.dart';
import 'package:peero/utils/formatting.dart';

void main() {
  group('formatClockDuration', () {
    test('pads seconds to two digits', () {
      expect(formatClockDuration(const Duration(seconds: 5)), '0:05');
      expect(formatClockDuration(const Duration(seconds: 42)), '0:42');
    });

    test('rolls over into minutes', () {
      expect(formatClockDuration(const Duration(seconds: 60)), '1:00');
      expect(formatClockDuration(const Duration(seconds: 91)), '1:31');
      expect(
        formatClockDuration(const Duration(minutes: 12, seconds: 7)),
        '12:07',
      );
    });

    test('keeps counting past an hour rather than wrapping', () {
      expect(
        formatClockDuration(const Duration(hours: 1, seconds: 3)),
        '60:03',
      );
    });

    test('renders zero', () {
      expect(formatClockDuration(Duration.zero), '0:00');
    });
  });

  group('formatByteSize', () {
    final l10n = lookupAppLocalizations(const Locale('fr'));

    test('reports KB below a megabyte, rounded to a whole number', () {
      expect(formatByteSize(l10n, 0), '0 ${l10n.storageUnitKB}');
      expect(formatByteSize(l10n, 1024), '1 ${l10n.storageUnitKB}');
      expect(formatByteSize(l10n, 1536), '2 ${l10n.storageUnitKB}');
    });

    test('switches to MB with one decimal at a megabyte', () {
      expect(formatByteSize(l10n, 1024 * 1024), '1.0 ${l10n.storageUnitMB}');
      expect(
        formatByteSize(l10n, (2.5 * 1024 * 1024).round()),
        '2.5 ${l10n.storageUnitMB}',
      );
    });

    test('the boundary byte below a megabyte still reads as KB', () {
      expect(
        formatByteSize(l10n, 1024 * 1024 - 1),
        '1024 ${l10n.storageUnitKB}',
      );
    });
  });

  group('isSameDay', () {
    test('is true only within the same calendar day', () {
      expect(
        isSameDay(DateTime(2026, 3, 5, 0, 1), DateTime(2026, 3, 5, 23, 59)),
        isTrue,
      );
      expect(isSameDay(DateTime(2026, 3, 5), DateTime(2026, 3, 6)), isFalse);
      expect(isSameDay(DateTime(2026, 3, 5), DateTime(2026, 4, 5)), isFalse);
      expect(isSameDay(DateTime(2026, 3, 5), DateTime(2025, 3, 5)), isFalse);
    });
  });

  group('formatConversationTimestamp', () {
    test('shows a zero-padded time for today', () {
      final now = DateTime(2026, 3, 5, 18, 30);
      expect(
        formatConversationTimestamp(DateTime(2026, 3, 5, 9, 4), now: now),
        '09:04',
      );
    });

    test('shows a zero-padded date for any other day', () {
      final now = DateTime(2026, 3, 5, 18, 30);
      expect(
        formatConversationTimestamp(DateTime(2026, 3, 4, 9, 4), now: now),
        '04/03',
      );
    });

    test('defaults to the real clock when no reference is given', () {
      final result = formatConversationTimestamp(DateTime.now());
      expect(result, matches(RegExp(r'^\d{2}:\d{2}$')));
    });
  });

  group('shortPeerId', () {
    test('formats the first six hex characters as colon-separated pairs', () {
      expect(shortPeerId('7f3a9c12-1234-5678-9abc-def012345678'), '7F:3A:9C');
    });

    test('handles ids shorter than six characters', () {
      expect(shortPeerId('ab'), 'AB');
      expect(shortPeerId('abc'), 'AB:C');
      expect(shortPeerId(''), '');
    });

    test('is deterministic', () {
      expect(shortPeerId('peer-1'), shortPeerId('peer-1'));
    });
  });
}
