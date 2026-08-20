import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peero/widgets/peer_tile.dart';

import '../helpers/test_harness.dart';

void main() {
  late TestStores stores;

  setUp(() => stores = TestStores.inMemory());
  tearDown(() async => stores.dispose());

  Future<void> pumpTile(
    WidgetTester tester, {
    String platform = 'linux',
    String? subtitleOverride,
    VoidCallback? onTap,
  }) {
    return tester.pumpWidget(
      wrapWithApp(
        Scaffold(
          body: PeerTile(
            peer: testPeer(
              id: '7f3a9c12-0000-0000-0000-000000000000',
              alias: 'Bob',
              platform: platform,
            ),
            subtitleOverride: subtitleOverride,
            onTap: onTap ?? () {},
          ),
        ),
        stores: stores,
      ),
    );
  }

  group('deviceTypeFor', () {
    test('phones and tablets read as mobile, everything else as desktop', () {
      expect(deviceTypeFor(l10nFr, 'android'), l10nFr.deviceTypeMobile);
      expect(deviceTypeFor(l10nFr, 'ios'), l10nFr.deviceTypeMobile);
      expect(deviceTypeFor(l10nFr, 'linux'), l10nFr.deviceTypeDesktop);
      expect(deviceTypeFor(l10nFr, 'macos'), l10nFr.deviceTypeDesktop);
      expect(deviceTypeFor(l10nFr, 'windows'), l10nFr.deviceTypeDesktop);
      expect(deviceTypeFor(l10nFr, 'wat'), l10nFr.deviceTypeDesktop);
    });
  });

  testWidgets('shows the alias, device type and short id', (tester) async {
    await pumpTile(tester);

    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('${l10nFr.deviceTypeDesktop} · 7F:3A:9C'), findsOneWidget);
  });

  testWidgets('a mobile peer is labelled as such', (tester) async {
    await pumpTile(tester, platform: 'android');

    expect(find.textContaining(l10nFr.deviceTypeMobile), findsOneWidget);
  });

  testWidgets('a subtitle override replaces the device line', (tester) async {
    await pumpTile(tester, subtitleOverride: 'Demande envoyée…');

    expect(find.text('Demande envoyée…'), findsOneWidget);
    expect(find.textContaining('7F:3A:9C'), findsNothing);
  });

  testWidgets('tapping calls back', (tester) async {
    var taps = 0;
    await pumpTile(tester, onTap: () => taps++);

    await tester.tap(find.byType(PeerTile));

    expect(taps, 1);
  });
}
