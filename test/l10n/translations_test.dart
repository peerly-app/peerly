import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:peero/l10n/app_localizations.dart';
import 'package:peero/services/locale_service.dart';

Map<String, String> messagesOf(String languageCode) {
  final raw = File('lib/l10n/app_$languageCode.arb').readAsStringSync();
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  return {
    for (final entry in decoded.entries)
      if (!entry.key.startsWith('@')) entry.key: entry.value as String,
  };
}

Set<String> placeholdersIn(String message) =>
    RegExp(r'\{(\w+)[,}]').allMatches(message).map((m) => m.group(1)!).toSet();

void main() {
  const templateCode = 'en';
  final template = messagesOf(templateCode);
  final localeCodes = supportedLocales.map((l) => l.languageCode).toList();

  test('the template has strings to translate', () {
    expect(template, isNotEmpty);
  });

  test('every supported locale has an ARB file', () {
    for (final code in localeCodes) {
      expect(File('lib/l10n/app_$code.arb').existsSync(), isTrue, reason: code);
    }
  });

  group('completeness', () {
    for (final code in ['fr', 'es', 'de', 'it', 'pt']) {
      test('$code translates every key, and no extra ones', () {
        final messages = messagesOf(code);

        expect(
          template.keys.where((k) => !messages.containsKey(k)),
          isEmpty,
          reason: 'missing from app_$code.arb',
        );
        expect(
          messages.keys.where((k) => !template.containsKey(k)),
          isEmpty,
          reason: 'not in the template any more',
        );
      });

      test('$code keeps the same placeholders as the template', () {
        final messages = messagesOf(code);

        for (final entry in template.entries) {
          final translated = messages[entry.key];
          if (translated == null) continue;
          expect(
            placeholdersIn(translated),
            placeholdersIn(entry.value),
            reason: '${entry.key} in app_$code.arb',
          );
        }
      });

      test('$code leaves nothing untranslated by copy-paste', () {
        final messages = messagesOf(code);

        final copied = template.entries
            .where((e) => e.value.length > 40 && messages[e.key] == e.value)
            .map((e) => e.key);

        expect(copied, isEmpty, reason: 'still English in app_$code.arb');
      });
    }
  });

  group('generated bundles', () {
    test('resolve to their own language, not the English fallback', () {
      for (final code in ['fr', 'es', 'de', 'it', 'pt']) {
        final bundle = lookupAppLocalizations(Locale(code));
        final expected = messagesOf(code);

        expect(bundle.requestAccept, expected['requestAccept'], reason: code);
        expect(bundle.block, expected['block'], reason: code);
        expect(
          bundle.fileTransferFailed,
          expected['fileTransferFailed'],
          reason: code,
        );
        expect(
          bundle.settingsClearMedia,
          expected['settingsClearMedia'],
          reason: code,
        );
      }
    });

    test('interpolate their placeholder', () {
      for (final code in localeCodes) {
        final bundle = lookupAppLocalizations(Locale(code));
        expect(bundle.blockConfirmTitle('Bob'), contains('Bob'), reason: code);
        expect(
          bundle.chatPendingIncomingBanner('Bob'),
          contains('Bob'),
          reason: code,
        );
      }
    });

    test('pluralise the discovered-device count', () {
      for (final code in localeCodes) {
        final bundle = lookupAppLocalizations(Locale(code));
        expect(bundle.nearbyDevicesFound(0), isNotEmpty, reason: code);
        expect(bundle.nearbyDevicesFound(2), contains('2'), reason: code);
      }
    });

    test('an unsupported locale is never looked up', () {
      expect(
        () => lookupAppLocalizations(const Locale('ja')),
        throwsFlutterError,
      );

      final resolved = resolveDefaultLocale(
        const Locale('ja', 'JP'),
        supportedLocales,
      );
      expect(() => lookupAppLocalizations(resolved), returnsNormally);
    });
  });
}
