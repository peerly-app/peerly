import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peero/models/chat_message.dart';
import 'package:peero/screens/chat_screen.dart';
import 'package:peero/screens/conversations_screen.dart';
import 'package:peero/screens/nearby_screen.dart';
import 'package:peero/services/chat_repository.dart';

import '../helpers/test_harness.dart';

ConversationSummary summary({
  String peerId = 'peer-1',
  String alias = 'Bob',
  String lastText = 'Salut',
  DateTime? lastTimestamp,
  int unreadCount = 0,
  ConversationStatus status = ConversationStatus.accepted,
}) {
  return ConversationSummary(
    peerId: peerId,
    alias: alias,
    lastText: lastText,
    lastTimestamp: lastTimestamp ?? DateTime(2026, 1, 1, 10),
    unreadCount: unreadCount,
    status: status,
  );
}

void main() {
  late TestStores stores;

  setUp(() {
    stores = TestStores.inMemory();
    useFakeAudioRecorder();
  });
  tearDown(() async => stores.dispose());

  Future<void> pumpScreen(WidgetTester tester) async {
    await setLargeSurface(tester);
    await tester.pumpWidget(
      wrapWithApp(const ConversationsScreen(), stores: stores),
    );
    await tester.pump();
  }

  Future<void> addConversation(
    String peerId,
    String alias, {
    String text = 'Salut',
    DateTime? at,
    bool incoming = true,
  }) {
    return stores.chatStore.add(
      peerId,
      alias,
      ChatMessage(
        fromId: incoming ? peerId : 'me',
        fromAlias: alias,
        text: text,
        timestamp: at ?? DateTime(2026, 1, 1, 10),
        isMine: !incoming,
      ),
    );
  }

  group('conversationSubtitle', () {
    test('shows the handshake state while a request is outstanding', () {
      expect(
        conversationSubtitle(
          l10nFr,
          summary(status: ConversationStatus.pendingOutgoing),
        ),
        l10nFr.conversationsRequestSentSubtitle,
      );
      expect(
        conversationSubtitle(
          l10nFr,
          summary(status: ConversationStatus.pendingIncoming),
        ),
        l10nFr.conversationsRequestReceivedSubtitle,
      );
    });

    test('shows the last message once the conversation is open', () {
      expect(
        conversationSubtitle(l10nFr, summary(lastText: 'Le dernier')),
        'Le dernier',
      );
    });

    test('shows a placeholder for a conversation with no messages yet', () {
      expect(
        conversationSubtitle(l10nFr, summary(lastText: '')),
        l10nFr.conversationsNewSubtitle,
      );
      expect(
        conversationSubtitle(
          l10nFr,
          summary(lastText: '', status: ConversationStatus.blocked),
        ),
        l10nFr.conversationsNewSubtitle,
      );
    });
  });

  testWidgets('shows an empty state with no conversations', (tester) async {
    await pumpScreen(tester);

    expect(find.text(l10nFr.conversationsEmpty), findsOneWidget);
    expect(find.byType(ListView), findsNothing);
  });

  testWidgets('lists conversations newest first', (tester) async {
    await addConversation('peer-1', 'Bob', at: DateTime(2026, 1, 1));
    await addConversation('peer-2', 'Carol', at: DateTime(2026, 1, 3));
    await pumpScreen(tester);

    final tiles = tester.widgetList<Text>(find.byType(Text)).toList();
    final aliases = tiles
        .map((t) => t.data)
        .where((d) => d == 'Bob' || d == 'Carol')
        .toList();

    expect(aliases, ['Carol', 'Bob']);
  });

  testWidgets('hides blocked conversations', (tester) async {
    await addConversation('peer-1', 'Bob');
    await stores.chatStore.setStatus(
      'peer-2',
      'Zoe',
      ConversationStatus.blocked,
    );
    await pumpScreen(tester);

    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Zoe'), findsNothing);
  });

  testWidgets('shows the unread badge only when there is unread mail', (
    tester,
  ) async {
    await addConversation('peer-1', 'Bob');
    await addConversation('peer-1', 'Bob', text: 'Encore');
    await pumpScreen(tester);

    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('shows no badge for a read conversation', (tester) async {
    await addConversation('peer-1', 'Bob', incoming: false);
    await pumpScreen(tester);

    expect(find.text('0'), findsNothing);
  });

  testWidgets('shows the time for today and the date for older messages', (
    tester,
  ) async {
    await addConversation('peer-1', 'Bob', at: DateTime(2020, 3, 4, 15, 9));
    await pumpScreen(tester);

    expect(find.text('04/03'), findsOneWidget);
  });

  testWidgets('opens the chat when a conversation is tapped', (tester) async {
    await addConversation('peer-1', 'Bob');
    await pumpScreen(tester);

    await tester.tap(find.text('Bob'));
    await tester.pumpAndSettle();

    expect(find.byType(ChatScreen), findsOneWidget);
  });

  testWidgets('the + button opens Nearby', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.byIcon(Icons.add));
    await pumpRouteTransition(tester);

    expect(find.byType(NearbyScreen), findsOneWidget);
  });

  group('swipe to delete', () {
    testWidgets('asks for confirmation and deletes on confirm', (tester) async {
      await addConversation('peer-1', 'Bob');
      await pumpScreen(tester);

      await tester.drag(find.text('Bob'), const Offset(-1200, 0));
      await tester.pumpAndSettle();

      expect(find.text(l10nFr.deleteConversationTitle), findsOneWidget);
      await tester.tap(find.text(l10nFr.delete));
      await tester.pumpAndSettle();

      expect(stores.chatStore.conversations, isEmpty);
      expect(find.text(l10nFr.conversationsEmpty), findsOneWidget);
    });

    testWidgets('keeps the conversation when cancelled', (tester) async {
      await addConversation('peer-1', 'Bob');
      await pumpScreen(tester);

      await tester.drag(find.text('Bob'), const Offset(-1200, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10nFr.cancel));
      await tester.pumpAndSettle();

      expect(stores.chatStore.conversations, hasLength(1));
      expect(find.text('Bob'), findsOneWidget);
    });
  });
}
