import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:peero/design/colors.dart';
import 'package:peero/widgets/avatar.dart';

import '../helpers/test_harness.dart';

Uint8List realPng() {
  final image = img.Image(width: 8, height: 8);
  img.fill(image, color: img.ColorRgb8(255, 0, 0));
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  late TestStores stores;

  setUp(() => stores = TestStores.inMemory());
  tearDown(() async => stores.dispose());

  Future<void> pumpAvatar(
    WidgetTester tester, {
    required String id,
    required String name,
    double diameter = 48,
  }) {
    return tester.pumpWidget(
      wrapWithApp(
        Scaffold(
          body: Center(
            child: Avatar(id: id, name: name, diameter: diameter),
          ),
        ),
        stores: stores,
      ),
    );
  }

  group('initials', () {
    testWidgets('a single name shows one letter', (tester) async {
      await pumpAvatar(tester, id: 'p1', name: 'bob');
      expect(find.text('B'), findsOneWidget);
    });

    testWidgets('a full name shows first and last initials', (tester) async {
      await pumpAvatar(tester, id: 'p1', name: 'Alice Martin');
      expect(find.text('AM'), findsOneWidget);
    });

    testWidgets('middle names are skipped', (tester) async {
      await pumpAvatar(tester, id: 'p1', name: 'Jean Paul Sartre');
      expect(find.text('JS'), findsOneWidget);
    });

    testWidgets('extra whitespace is ignored', (tester) async {
      await pumpAvatar(tester, id: 'p1', name: '  Alice   Martin  ');
      expect(find.text('AM'), findsOneWidget);
    });

    testWidgets('an empty name falls back to a question mark', (tester) async {
      await pumpAvatar(tester, id: 'p1', name: '   ');
      expect(find.text('?'), findsOneWidget);
    });
  });

  testWidgets('the background colour is the deterministic per-id hue', (
    tester,
  ) async {
    await pumpAvatar(tester, id: 'peer-42', name: 'Bob');

    final container = tester.widget<Container>(
      find.descendant(
        of: find.byType(Avatar),
        matching: find.byType(Container),
      ),
    );
    final decoration = container.decoration! as BoxDecoration;

    expect(decoration.color, AppColors.avatarColorFor('peer-42'));
    expect(decoration.shape, BoxShape.circle);
    expect(decoration.image, isNull);
  });

  testWidgets('the font scales with the requested diameter', (tester) async {
    await pumpAvatar(tester, id: 'p1', name: 'Bob', diameter: 100);

    expect(tester.widget<Text>(find.text('B')).style!.fontSize, 34);
  });

  testWidgets('a cached photo replaces the initials', (tester) async {
    await persist(tester, () async {
      await stores.avatarRepository.setPhoto('peer-1', realPng(), 'v1');
      stores.avatarStore.load();
    });

    await pumpAvatar(tester, id: 'peer-1', name: 'Bob');

    expect(find.text('B'), findsNothing);
    final container = tester.widget<Container>(
      find.descendant(
        of: find.byType(Avatar),
        matching: find.byType(Container),
      ),
    );
    expect((container.decoration! as BoxDecoration).image, isNotNull);
  });

  testWidgets('it swaps to the photo as soon as one is cached', (tester) async {
    await pumpAvatar(tester, id: 'peer-1', name: 'Bob');
    expect(find.text('B'), findsOneWidget);

    await persist(
      tester,
      () => stores.avatarStore.setOwnPhoto('peer-1', realPng()),
    );

    expect(find.text('B'), findsNothing);
  });
}
