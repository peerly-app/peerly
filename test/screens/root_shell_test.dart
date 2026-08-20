import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peero/models/chat_message.dart';
import 'package:peero/screens/chat_screen.dart';
import 'package:peero/screens/conversations_screen.dart';
import 'package:peero/screens/nearby_screen.dart';
import 'package:peero/screens/root_shell.dart';
import 'package:peero/screens/settings_screen.dart';
import 'package:peero/utils/platform_info.dart';

import '../helpers/test_harness.dart';

void main() {
  late TestStores stores;
  late FakeDiscoveryService discovery;

  setUp(() {
    useInMemoryPreferences();
    stores = TestStores.inMemory();
    discovery = FakeDiscoveryService();
    useFakeAudioRecorder();
  });
  tearDown(() async {
    debugIsDesktopPlatformOverride = null;
    await stores.dispose();
  });

  Future<void> pumpShell(WidgetTester tester, {required bool desktop}) async {
    debugIsDesktopPlatformOverride = desktop;
    await setLargeSurface(tester);
    await tester.pumpWidget(
      wrapWithApp(const RootShell(), stores: stores, discovery: discovery),
    );
    await tester.pump();
  }

  Future<void> addConversation(String peerId, String alias, {DateTime? at}) {
    return stores.chatStore.add(
      peerId,
      alias,
      ChatMessage(
        fromId: peerId,
        fromAlias: alias,
        text: 'Salut',
        timestamp: at ?? DateTime(2026, 1, 1, 10),
        isMine: false,
      ),
    );
  }

  group('mobile', () {
    testWidgets('opens on the conversations tab', (tester) async {
      await pumpShell(tester, desktop: false);

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(ConversationsScreen), findsOneWidget);
    });

    testWidgets('switches between the three tabs', (tester) async {
      await pumpShell(tester, desktop: false);

      await tester.tap(find.text(l10nFr.navNearby));
      await tester.pump();
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        1,
      );

      await tester.tap(find.text(l10nFr.navSettings));
      await tester.pump();
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        2,
      );
    });

    testWidgets('keeps all three screens alive in an IndexedStack', (
      tester,
    ) async {
      await pumpShell(tester, desktop: false);

      expect(find.byType(IndexedStack), findsOneWidget);

      expect(find.byType(ConversationsScreen), findsOneWidget);
      expect(find.byType(NearbyScreen, skipOffstage: false), findsOneWidget);
      expect(find.byType(SettingsScreen, skipOffstage: false), findsOneWidget);
    });

    testWidgets('has no desktop sidebar', (tester) async {
      await pumpShell(tester, desktop: false);

      expect(find.text(l10nFr.selectConversation), findsNothing);
    });
  });

  group('desktop', () {
    testWidgets('shows the sidebar with the discovered-device count', (
      tester,
    ) async {
      discovery.setPeers([testPeer(id: 'peer-1'), testPeer(id: 'peer-2')]);
      await pumpShell(tester, desktop: true);

      expect(
        find.text('${l10nFr.navNearby.toUpperCase()} · 2'),
        findsOneWidget,
      );
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('prompts to pick a conversation when none is selected', (
      tester,
    ) async {
      await pumpShell(tester, desktop: true);

      expect(find.text(l10nFr.selectConversation), findsOneWidget);
      expect(find.text(l10nFr.conversationsEmptySidebar), findsOneWidget);
    });

    testWidgets('lists conversations in the sidebar', (tester) async {
      await addConversation('peer-1', 'Bob');
      await pumpShell(tester, desktop: true);

      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Salut'), findsOneWidget);
    });

    testWidgets('selecting a conversation opens it inline', (tester) async {
      await addConversation('peer-1', 'Bob');
      await pumpShell(tester, desktop: true);

      await tester.tap(find.text('Bob'));
      await tester.pump();

      expect(find.byType(ChatScreen), findsOneWidget);
      expect(find.text(l10nFr.selectConversation), findsNothing);
    });

    testWidgets('the add button opens Nearby as a page', (tester) async {
      await pumpShell(tester, desktop: true);

      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await pumpRouteTransition(tester);

      expect(find.byType(NearbyScreen), findsOneWidget);
    });

    testWidgets('the settings button opens Settings as a page', (tester) async {
      await pumpShell(tester, desktop: true);

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();

      expect(find.byType(SettingsScreen), findsOneWidget);
    });

    group('deleting from the sidebar', () {
      testWidgets('asks first, then removes the conversation', (tester) async {
        await addConversation('peer-1', 'Bob');
        await pumpShell(tester, desktop: true);

        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();
        expect(find.text(l10nFr.deleteConversationTitle), findsOneWidget);

        await tester.tap(find.text(l10nFr.delete));
        await tester.pumpAndSettle();

        expect(stores.chatStore.conversations, isEmpty);
        expect(find.text(l10nFr.conversationsEmptySidebar), findsOneWidget);
      });

      testWidgets('cancelling keeps it', (tester) async {
        await addConversation('peer-1', 'Bob');
        await pumpShell(tester, desktop: true);

        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10nFr.cancel));
        await tester.pumpAndSettle();

        expect(stores.chatStore.conversations, hasLength(1));
      });

      testWidgets('clears the pane when the open conversation is deleted', (
        tester,
      ) async {
        await addConversation('peer-1', 'Bob');
        await pumpShell(tester, desktop: true);
        await tester.tap(find.text('Bob'));
        await tester.pump();
        expect(find.byType(ChatScreen), findsOneWidget);

        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10nFr.delete));
        await tester.pumpAndSettle();

        expect(find.byType(ChatScreen), findsNothing);
        expect(find.text(l10nFr.selectConversation), findsOneWidget);
      });

      testWidgets(
        'leaves the open conversation alone when another is deleted',
        (tester) async {
          await addConversation('peer-1', 'Bob', at: DateTime(2026, 1, 1));
          await addConversation('peer-2', 'Carol', at: DateTime(2026, 1, 2));
          await pumpShell(tester, desktop: true);
          await tester.tap(find.text('Bob'));
          await tester.pump();

          await tester.tap(find.byIcon(Icons.close).first);
          await tester.pumpAndSettle();
          await tester.tap(find.text(l10nFr.delete));
          await tester.pumpAndSettle();

          expect(find.byType(ChatScreen), findsOneWidget);
        },
      );
    });
  });
}
