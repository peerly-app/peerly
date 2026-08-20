import 'package:flutter_test/flutter_test.dart';
import 'package:peero/screens/chat_screen.dart';
import 'package:peero/screens/nearby_screen.dart';
import 'package:peero/services/chat_repository.dart';
import 'package:peero/widgets/peer_tile.dart';
import 'package:peero/widgets/radar_pulse.dart';

import '../helpers/test_harness.dart';

void main() {
  late TestStores stores;
  late FakeDiscoveryService discovery;

  setUp(() {
    stores = TestStores.inMemory();
    discovery = FakeDiscoveryService();
    useFakeAudioRecorder();
  });
  tearDown(() async => stores.dispose());

  Future<void> pumpScreen(WidgetTester tester) async {
    await setLargeSurface(tester);
    await tester.pumpWidget(
      wrapWithApp(const NearbyScreen(), stores: stores, discovery: discovery),
    );
    await tester.pump();
  }

  testWidgets('shows the radar and a generic search line', (tester) async {
    await pumpScreen(tester);

    expect(find.byType(RadarPulse), findsOneWidget);

    expect(find.text(l10nFr.nearbySearchingGeneric), findsOneWidget);
  });

  testWidgets('shows an empty state with nobody around', (tester) async {
    await pumpScreen(tester);

    expect(find.text(l10nFr.nearbyEmpty), findsOneWidget);
    expect(
      find.text(l10nFr.nearbyDevicesFound(0).toUpperCase()),
      findsOneWidget,
    );
  });

  testWidgets('lists discovered peers with a count', (tester) async {
    discovery.setPeers([
      testPeer(id: 'peer-1', alias: 'Bob'),
      testPeer(id: 'peer-2', alias: 'Carol'),
    ]);
    await pumpScreen(tester);

    expect(find.byType(PeerTile), findsNWidgets(2));
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Carol'), findsOneWidget);
    expect(
      find.text(l10nFr.nearbyDevicesFound(2).toUpperCase()),
      findsOneWidget,
    );
  });

  testWidgets('hides blocked peers', (tester) async {
    discovery.setPeers([
      testPeer(id: 'peer-1', alias: 'Bob'),
      testPeer(id: 'peer-2', alias: 'Zoe'),
    ]);
    await stores.chatStore.setStatus(
      'peer-2',
      'Zoe',
      ConversationStatus.blocked,
    );
    await pumpScreen(tester);

    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Zoe'), findsNothing);
    expect(
      find.text(l10nFr.nearbyDevicesFound(1).toUpperCase()),
      findsOneWidget,
    );
  });

  testWidgets('labels a peer we already asked to talk to', (tester) async {
    discovery.setPeers([testPeer(id: 'peer-1', alias: 'Bob')]);
    await stores.chatStore.setStatus(
      'peer-1',
      'Bob',
      ConversationStatus.pendingOutgoing,
    );
    await pumpScreen(tester);

    expect(find.text(l10nFr.conversationsRequestSentSubtitle), findsOneWidget);
  });

  testWidgets('labels a peer who asked to talk to us', (tester) async {
    discovery.setPeers([testPeer(id: 'peer-1', alias: 'Bob')]);
    await stores.chatStore.setStatus(
      'peer-1',
      'Bob',
      ConversationStatus.pendingIncoming,
    );
    await pumpScreen(tester);

    expect(
      find.text(l10nFr.conversationsRequestReceivedSubtitle),
      findsOneWidget,
    );
  });

  testWidgets('an accepted peer shows the plain device line', (tester) async {
    discovery.setPeers([testPeer(id: 'peer-1', alias: 'Bob')]);
    await stores.chatStore.setStatus(
      'peer-1',
      'Bob',
      ConversationStatus.accepted,
    );
    await pumpScreen(tester);

    expect(find.textContaining(l10nFr.deviceTypeDesktop), findsOneWidget);
  });

  group('tapping a peer', () {
    testWidgets('sends a request the first time and opens the chat', (
      tester,
    ) async {
      discovery.setPeers([
        testPeer(id: 'peer-1', alias: 'Bob', ip: '127.0.0.1', port: 1),
      ]);
      await pumpScreen(tester);

      await tapAndSettle(tester, find.text('Bob'));
      await pumpRouteTransition(tester);

      expect(
        stores.chatStore.statusFor('peer-1'),
        ConversationStatus.pendingOutgoing,
      );
      expect(find.byType(ChatScreen), findsOneWidget);
    });

    testWidgets('does not re-send a request for a known peer', (tester) async {
      discovery.setPeers([
        testPeer(id: 'peer-1', alias: 'Bob', ip: '127.0.0.1', port: 1),
      ]);
      await stores.chatStore.setStatus(
        'peer-1',
        'Bob',
        ConversationStatus.accepted,
      );
      await pumpScreen(tester);

      await tapAndSettle(tester, find.text('Bob'));
      await pumpRouteTransition(tester);

      expect(stores.chatStore.statusFor('peer-1'), ConversationStatus.accepted);
      expect(find.byType(ChatScreen), findsOneWidget);
    });
  });
}
