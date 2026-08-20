import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peero/widgets/confirm_dialog.dart';

import '../helpers/test_harness.dart';

void main() {
  late TestStores stores;

  setUp(() => stores = TestStores.inMemory());
  tearDown(() async => stores.dispose());

  Future<List<bool>> pumpOpener(
    WidgetTester tester,
    Future<bool> Function(BuildContext) open,
  ) async {
    final results = <bool>[];
    await tester.pumpWidget(
      wrapWithApp(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => results.add(await open(context)),
              child: const Text('ouvrir'),
            ),
          ),
        ),
        stores: stores,
      ),
    );
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
    return results;
  }

  Future<bool> openDelete(BuildContext context) =>
      confirmDelete(context, title: 'Supprimer ?', body: 'Irréversible.');

  Future<bool> openBlock(BuildContext context) =>
      confirmBlock(context, title: 'Bloquer Bob ?', body: 'Plus de messages.');

  group('confirmDelete', () {
    testWidgets('shows the title, body and both actions', (tester) async {
      await pumpOpener(tester, openDelete);

      expect(find.text('Supprimer ?'), findsOneWidget);
      expect(find.text('Irréversible.'), findsOneWidget);
      expect(find.text(l10nFr.cancel), findsOneWidget);
      expect(find.text(l10nFr.delete), findsOneWidget);
    });

    testWidgets('confirming resolves true', (tester) async {
      final results = await pumpOpener(tester, openDelete);

      await tester.tap(find.text(l10nFr.delete));
      await tester.pumpAndSettle();

      expect(results, [true]);
    });

    testWidgets('cancelling resolves false', (tester) async {
      final results = await pumpOpener(tester, openDelete);

      await tester.tap(find.text(l10nFr.cancel));
      await tester.pumpAndSettle();

      expect(results, [false]);
    });

    testWidgets('dismissing by tapping outside resolves false', (tester) async {
      final results = await pumpOpener(tester, openDelete);

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(results, [false]);
    });
  });

  group('confirmBlock', () {
    testWidgets('offers block rather than delete', (tester) async {
      await pumpOpener(tester, openBlock);

      expect(find.text('Bloquer Bob ?'), findsOneWidget);
      expect(find.text(l10nFr.block), findsOneWidget);
      expect(find.text(l10nFr.delete), findsNothing);
    });

    testWidgets('confirming resolves true', (tester) async {
      final results = await pumpOpener(tester, openBlock);

      await tester.tap(find.text(l10nFr.block));
      await tester.pumpAndSettle();

      expect(results, [true]);
    });

    testWidgets('cancelling resolves false', (tester) async {
      final results = await pumpOpener(tester, openBlock);

      await tester.tap(find.text(l10nFr.cancel));
      await tester.pumpAndSettle();

      expect(results, [false]);
    });
  });
}
