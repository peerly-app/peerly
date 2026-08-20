import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:peero/services/locale_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_harness.dart';

void main() {
  setUp(useInMemoryPreferences);

  group('resolveDefaultLocale', () {
    test('picks the system language when supported', () {
      expect(
        resolveDefaultLocale(const Locale('fr', 'FR'), supportedLocales),
        const Locale('fr'),
      );
    });

    test('matches on language, ignoring the country', () {
      expect(
        resolveDefaultLocale(const Locale('pt', 'BR'), supportedLocales),
        const Locale('pt'),
      );
    });

    test('falls back to English when unsupported', () {
      expect(
        resolveDefaultLocale(const Locale('ja', 'JP'), supportedLocales),
        const Locale('en'),
      );
    });

    test('falls back to English against an empty supported list', () {
      expect(
        resolveDefaultLocale(const Locale('fr'), const []),
        const Locale('en'),
      );
    });

    test('every supported locale resolves to itself', () {
      for (final locale in supportedLocales) {
        expect(resolveDefaultLocale(locale, supportedLocales), locale);
      }
    });
  });

  group('LocaleService', () {
    test('defaults to English before anything is loaded', () {
      expect(LocaleService().locale, const Locale('en'));
    });

    test('load() restores a saved language', () async {
      useInMemoryPreferences({'locale_code': 'de'});
      final service = LocaleService();

      await service.load();

      expect(service.locale, const Locale('de'));
    });

    test(
      'load() falls back to the system language when nothing is saved',
      () async {
        final service = LocaleService();

        await service.load();

        expect(supportedLocales, contains(service.locale));
      },
    );

    test('load() notifies listeners', () async {
      final service = LocaleService();
      var notifications = 0;
      service.addListener(() => notifications++);

      await service.load();

      expect(notifications, 1);
    });

    test('setLocale persists the choice and notifies', () async {
      final service = LocaleService();
      var notifications = 0;
      service.addListener(() => notifications++);

      await service.setLocale(const Locale('it'));

      expect(service.locale, const Locale('it'));
      expect(notifications, 1);
      expect(await SharedPreferencesAsync().getString('locale_code'), 'it');
    });

    test('a language set now is the one restored next launch', () async {
      await LocaleService().setLocale(const Locale('es'));

      final restored = LocaleService();
      await restored.load();

      expect(restored.locale, const Locale('es'));
    });
  });
}
