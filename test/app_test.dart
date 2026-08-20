import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:peero/main.dart';
import 'package:peero/models/peer.dart';
import 'package:peero/screens/conversations_screen.dart';
import 'package:peero/services/chat_repository.dart';
import 'package:peero/screens/root_shell.dart';
import 'package:peero/services/device_identity_service.dart';
import 'package:peero/services/discovery_service.dart';
import 'package:peero/services/locale_service.dart';
import 'package:peero/services/notification_service.dart';
import 'package:peero/utils/platform_info.dart';

import 'helpers/test_harness.dart';

void main() {
  late TestStores stores;
  late FakeDiscoveryService discovery;
  late LocaleService localeService;

  setUp(() {
    useInMemoryPreferences();
    stores = TestStores.inMemory();
    discovery = FakeDiscoveryService();
    localeService = LocaleService();
    useFakeAudioRecorder();
    debugIsDesktopPlatformOverride = false;
  });

  tearDown(() async {
    debugIsDesktopPlatformOverride = null;
    await stores.dispose();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await setLargeSurface(tester);
    await tester.pumpWidget(
      PeeroApp(
        identity: loadedIdentity(),
        discovery: discovery,
        chatStore: stores.chatStore,
        avatarStore: stores.avatarStore,
        audioStore: stores.audioStore,
        fileStore: stores.fileStore,
        notificationService: NotificationService(),
        localeService: localeService,
      ),
    );
    await tester.pump();
  }

  testWidgets('boots into the root shell', (tester) async {
    await pumpApp(tester);

    expect(find.byType(RootShell), findsOneWidget);
    expect(find.byType(ConversationsScreen), findsOneWidget);
  });

  testWidgets('is a dark-only app titled Peero', (tester) async {
    await pumpApp(tester);

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.title, 'Peero');
    expect(app.themeMode, ThemeMode.dark);

    expect(app.theme!.brightness, Brightness.dark);
    expect(app.darkTheme!.brightness, Brightness.dark);
  });

  testWidgets('exposes every service to the tree', (tester) async {
    await pumpApp(tester);

    final context = tester.element(find.byType(RootShell));
    expect(context.read<DeviceIdentityService>().id, isNotEmpty);
    expect(context.read<DiscoveryService>(), same(discovery));
    expect(context.read<LocaleService>(), same(localeService));
  });

  testWidgets('follows the locale service', (tester) async {
    await localeService.setLocale(const Locale('de'));
    await pumpApp(tester);

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).locale,
      const Locale('de'),
    );

    await localeService.setLocale(const Locale('fr'));
    await tester.pump();

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).locale,
      const Locale('fr'),
    );
  });

  group('avatar syncing', () {
    List<Peer> contactsAmong(List<Peer> peers) =>
        peers.where((p) => stores.chatStore.isKnownContact(p.id)).toList();

    test('fetches photos for contacts only, never for strangers', () async {
      await stores.chatStore.setStatus(
        'contact',
        'Bob',
        ConversationStatus.accepted,
      );
      stores.avatarClient.responses['contact'] = pngBytes();
      stores.avatarClient.responses['stranger'] = pngBytes();

      stores.avatarStore.syncFromPeers(
        contactsAmong([
          testPeer(id: 'contact', avatarVersion: 'v1'),
          testPeer(id: 'stranger', avatarVersion: 'v1'),
        ]),
      );
      await pumpEventQueue();

      expect(stores.avatarClient.requestedPeerIds, ['contact']);
    });

    test('stops fetching once a contact is blocked', () async {
      await stores.chatStore.setStatus(
        'peer-1',
        'Bob',
        ConversationStatus.blocked,
      );
      stores.avatarClient.responses['peer-1'] = pngBytes();

      stores.avatarStore.syncFromPeers(
        contactsAmong([testPeer(id: 'peer-1', avatarVersion: 'v1')]),
      );
      await pumpEventQueue();

      expect(stores.avatarClient.requestedPeerIds, isEmpty);
    });
  });

  testWidgets('offers every supported language', (tester) async {
    await pumpApp(tester);

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(
      app.supportedLocales.map((l) => l.languageCode),
      containsAll(supportedLocales.map((l) => l.languageCode)),
    );
  });
}
