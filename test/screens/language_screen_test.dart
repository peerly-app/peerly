import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peero/screens/language_screen.dart';
import 'package:peero/services/locale_service.dart';

import '../helpers/test_harness.dart';

void main() {
  late TestStores stores;
  late LocaleService localeService;

  setUp(() {
    useInMemoryPreferences();
    stores = TestStores.inMemory();
    localeService = LocaleService();
  });
  tearDown(() async => stores.dispose());

  Future<void> pumpScreen(WidgetTester tester) async {
    await setLargeSurface(tester);
    await tester.pumpWidget(
      wrapWithApp(
        const LanguageScreen(),
        stores: stores,
        localeService: localeService,
      ),
    );
    await tester.pump();
  }

  group('languageDisplayName', () {
    test('names every supported language natively', () {
      expect(languageDisplayName(const Locale('en')), 'English');
      expect(languageDisplayName(const Locale('fr')), 'Français');
      expect(languageDisplayName(const Locale('es')), 'Español');
      expect(languageDisplayName(const Locale('de')), 'Deutsch');
      expect(languageDisplayName(const Locale('it')), 'Italiano');
      expect(languageDisplayName(const Locale('pt')), 'Português');
    });

    test('falls back to the raw code for anything else', () {
      expect(languageDisplayName(const Locale('ja')), 'ja');
    });
  });

  testWidgets('lists every supported language', (tester) async {
    await pumpScreen(tester);

    for (final locale in supportedLocales) {
      expect(find.text(languageDisplayName(locale)), findsOneWidget);
    }
  });

  testWidgets('ticks the current language only', (tester) async {
    await localeService.setLocale(const Locale('de'));
    await pumpScreen(tester);

    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('choosing a language switches the app over', (tester) async {
    await localeService.setLocale(const Locale('fr'));
    await pumpScreen(tester);
    expect(find.text(l10nFr.settingsLanguage), findsOneWidget);

    await tester.tap(find.text('English'));
    await tester.pump();

    expect(localeService.locale, const Locale('en'));

    expect(find.text('Language'), findsOneWidget);
  });

  testWidgets('the choice is persisted', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Italiano'));
    await tester.pump();

    final reloaded = LocaleService();
    await tester.runAsync(reloaded.load);

    expect(reloaded.locale, const Locale('it'));
  });
}
