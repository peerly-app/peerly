import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peero/models/chat_message.dart';
import 'package:peero/screens/chat_screen.dart';
import 'package:peero/services/chat_repository.dart';
import 'package:peero/widgets/message_bubble.dart';

import '../helpers/test_harness.dart';

void main() {
  late TestStores stores;
  late FakeDiscoveryService discovery;
  late FakeAudioRecorder recorder;

  setUp(() {
    stores = TestStores.inMemory();
    discovery = FakeDiscoveryService();
    recorder = useFakeAudioRecorder();
    useFakeVoicePlayer();
  });
  tearDown(() async => stores.dispose());

  Future<void> pumpChat(
    WidgetTester tester, {
    String peerId = 'peer-1',
    String alias = 'Bob',
  }) async {
    await setLargeSurface(tester);
    await tester.pumpWidget(
      wrapWithApp(
        ChatScreen(peerId: peerId, peerAlias: alias),
        stores: stores,
        discovery: discovery,
      ),
    );
    await tester.pump();
  }

  Future<void> addMessage(
    String text, {
    bool isMine = false,
    DateTime? at,
    MessageKind kind = MessageKind.text,
  }) {
    return stores.chatStore.add(
      'peer-1',
      'Bob',
      ChatMessage(
        fromId: isMine ? 'me' : 'peer-1',
        fromAlias: 'Bob',
        text: text,
        timestamp: at ?? DateTime.now(),
        isMine: isMine,
        kind: kind,
        voiceDurationMs: kind == MessageKind.voice ? 1000 : null,
      ),
    );
  }

  Future<void> accept() =>
      stores.chatStore.setStatus('peer-1', 'Bob', ConversationStatus.accepted);

  group('header', () {
    testWidgets('shows the peer alias and an offline marker', (tester) async {
      await pumpChat(tester);

      expect(find.text('Bob'), findsOneWidget);
      expect(find.text(l10nFr.chatOffline), findsOneWidget);
    });

    testWidgets('shows online when the peer is on the network', (tester) async {
      discovery.setPeers([testPeer(id: 'peer-1')]);
      await pumpChat(tester);

      expect(find.text(l10nFr.chatActiveNow), findsOneWidget);
    });
  });

  group('message list', () {
    testWidgets('shows an empty state with no messages', (tester) async {
      await pumpChat(tester);

      expect(find.text(l10nFr.chatEmpty), findsOneWidget);
    });

    testWidgets('renders each message as a bubble', (tester) async {
      await addMessage('Salut');
      await addMessage('Ça va ?', isMine: true);
      await pumpChat(tester);

      expect(find.byType(MessageBubble), findsNWidgets(2));
      expect(find.text('Salut'), findsOneWidget);
      expect(find.text('Ça va ?'), findsOneWidget);
    });

    testWidgets('groups messages under a day separator', (tester) async {
      final now = DateTime.now();
      await addMessage('Message A', at: now.subtract(const Duration(days: 1)));
      await addMessage('Message B', at: now);
      await pumpChat(tester);

      expect(find.text(l10nFr.chatYesterday), findsOneWidget);
      expect(find.text(l10nFr.chatToday), findsOneWidget);
    });

    testWidgets('older days get a full date', (tester) async {
      await addMessage('Ancien', at: DateTime(2020, 3, 4));
      await pumpChat(tester);

      expect(find.text(l10nFr.chatToday), findsNothing);
      expect(find.textContaining('2020'), findsOneWidget);
    });

    testWidgets('several messages on one day share a single separator', (
      tester,
    ) async {
      final now = DateTime.now();
      await addMessage('Un', at: now);
      await addMessage('Deux', at: now.add(const Duration(minutes: 1)));
      await pumpChat(tester);

      expect(find.text(l10nFr.chatToday), findsOneWidget);
    });

    testWidgets('marks the conversation as read on open', (tester) async {
      await addMessage('Salut');
      expect(stores.chatStore.conversations.single.unreadCount, 1);

      await pumpChat(tester);
      await tester.pump();

      expect(stores.chatStore.conversations.single.unreadCount, 0);
      expect(stores.chatStore.currentlyViewedPeerId, 'peer-1');
    });

    testWidgets('stops being the viewed conversation once closed', (
      tester,
    ) async {
      await pumpChat(tester);
      await tester.pump();

      await tester.pumpWidget(const SizedBox());

      expect(stores.chatStore.currentlyViewedPeerId, isNull);
    });
  });

  group('buildChatEntries', () {
    ChatMessage at(DateTime timestamp) => ChatMessage(
      fromId: 'peer-1',
      fromAlias: 'Bob',
      text: 'x',
      timestamp: timestamp,
      isMine: false,
    );

    test('is empty for no messages', () {
      expect(buildChatEntries(const [], dayLabel: (d) => 'jour'), isEmpty);
    });

    test('puts a day entry before the first message of each day', () {
      final entries = buildChatEntries([
        at(DateTime(2026, 1, 1, 9)),
        at(DateTime(2026, 1, 1, 18)),
        at(DateTime(2026, 1, 2, 9)),
      ], dayLabel: (day) => '${day.day}/${day.month}');

      expect(entries.map((e) => e.runtimeType.toString()), [
        'ChatDayEntry',
        'ChatMessageEntry',
        'ChatMessageEntry',
        'ChatDayEntry',
        'ChatMessageEntry',
      ]);
      expect((entries.first as ChatDayEntry).label, '1/1');
      expect((entries[3] as ChatDayEntry).label, '2/1');
    });

    test('labels each day from the message date, not the time of day', () {
      final seen = <DateTime>[];
      buildChatEntries(
        [at(DateTime(2026, 1, 1, 23, 59))],
        dayLabel: (day) {
          seen.add(day);
          return '';
        },
      );

      expect(seen.single, DateTime(2026, 1, 1));
    });
  });

  group('composer', () {
    testWidgets('offers the mic while the field is empty', (tester) async {
      await pumpChat(tester);

      expect(find.byType(MicButton), findsOneWidget);
      expect(find.byType(SendButton), findsNothing);
    });

    testWidgets('swaps to send once something is typed', (tester) async {
      await pumpChat(tester);

      await tester.enterText(find.byType(TextField), 'Salut');
      await tester.pump();

      expect(find.byType(SendButton), findsOneWidget);
      expect(find.byType(MicButton), findsNothing);
    });

    testWidgets('goes back to the mic when the text is cleared', (
      tester,
    ) async {
      await pumpChat(tester);
      await tester.enterText(find.byType(TextField), 'Salut');
      await tester.pump();

      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();

      expect(find.byType(MicButton), findsOneWidget);
    });

    testWidgets('sending stores the message and clears the field', (
      tester,
    ) async {
      await pumpChat(tester);
      await tester.enterText(find.byType(TextField), 'Bonjour');
      await tester.pump();

      await tester.tap(find.byType(SendButton));
      await tester.pump();

      expect(stores.chatStore.messagesFor('peer-1').single.text, 'Bonjour');
      expect(stores.chatStore.messagesFor('peer-1').single.isMine, isTrue);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
    });

    testWidgets('warns when the peer is unreachable', (tester) async {
      await pumpChat(tester);
      await tester.enterText(find.byType(TextField), 'Bonjour');
      await tester.pump();

      await tester.tap(find.byType(SendButton));
      await tester.pump();
      await tester.pump();

      expect(find.text(l10nFr.chatSendFailed), findsOneWidget);
    });

    testWidgets('submitting from the keyboard sends too', (tester) async {
      await pumpChat(tester);
      await tester.enterText(find.byType(TextField), 'Depuis le clavier');

      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();

      expect(
        stores.chatStore.messagesFor('peer-1').single.text,
        'Depuis le clavier',
      );
    });

    testWidgets('an empty message is not sent', (tester) async {
      await pumpChat(tester);
      await tester.enterText(find.byType(TextField), '   ');

      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();

      expect(stores.chatStore.messagesFor('peer-1'), isEmpty);
    });
  });

  group('voice recording', () {
    Future<TestGesture> pressMic(WidgetTester tester) async {
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(MicButton)),
      );
      await tester.pump();
      return gesture;
    }

    testWidgets('holding the mic starts a recording', (tester) async {
      await pumpChat(tester);

      await pressMic(tester);
      await tester.pump();

      expect(recorder.startCount, 1);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('0:00'), findsOneWidget);
    });

    testWidgets('the counter ticks while recording', (tester) async {
      await pumpChat(tester);
      await pressMic(tester);
      await tester.pump();

      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('0:00'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('0:01'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('0:02'), findsOneWidget);
    });

    testWidgets('releasing sends the recording', (tester) async {
      await pumpChat(tester);
      final gesture = await pressMic(tester);
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      await gesture.up();
      await tester.pump();
      await tester.pump();

      expect(recorder.stopCount, 1);
      final message = stores.chatStore.messagesFor('peer-1').single;
      expect(message.kind, MessageKind.voice);
      expect(message.voiceDurationMs, 2000);
      expect(stores.audioStore.bytesFor(message.id), [1, 2, 3]);
    });

    testWidgets('a recording shorter than half a second is discarded', (
      tester,
    ) async {
      await pumpChat(tester);
      final gesture = await pressMic(tester);
      await tester.pump();

      await gesture.up();
      await tester.pump();
      await tester.pump();

      expect(recorder.stopCount, 1);
      expect(stores.chatStore.messagesFor('peer-1'), isEmpty);
    });

    testWidgets('a recording that captured nothing is discarded', (
      tester,
    ) async {
      recorder.capturedBytes = null;
      await pumpChat(tester);
      final gesture = await pressMic(tester);
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      await gesture.up();
      await tester.pump();

      expect(stores.chatStore.messagesFor('peer-1'), isEmpty);
    });

    testWidgets('a cancelled hold discards the recording', (tester) async {
      await pumpChat(tester);
      final gesture = await pressMic(tester);
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      await gesture.cancel();
      await tester.pump();

      expect(recorder.cancelCount, 1);
      expect(recorder.stopCount, 0);
      expect(stores.chatStore.messagesFor('peer-1'), isEmpty);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('the bin icon cancels a recording in progress', (tester) async {
      await pumpChat(tester);
      await pressMic(tester);
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);

      await tester.tap(find.byIcon(Icons.delete_outline), pointer: 2);
      await tester.pump();

      expect(recorder.cancelCount, 1);
      expect(stores.chatStore.messagesFor('peer-1'), isEmpty);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('a refused mic permission explains itself', (tester) async {
      recorder.permission = false;
      await pumpChat(tester);

      await pressMic(tester);
      await tester.pump();

      expect(find.text(l10nFr.voiceMicPermissionDenied), findsOneWidget);
      expect(recorder.startCount, 0);
    });

    testWidgets('recording stops on its own after five minutes', (
      tester,
    ) async {
      await pumpChat(tester);
      await pressMic(tester);
      await tester.pump();

      await tester.pump(const Duration(minutes: 5));
      await tester.pump();

      expect(recorder.stopCount, 1);
      expect(
        stores.chatStore.messagesFor('peer-1').single.kind,
        MessageKind.voice,
      );
    });

    testWidgets('a click released before the recorder was ready still sends', (
      tester,
    ) async {
      recorder.startGate = Completer<void>();
      await pumpChat(tester);
      final gesture = await pressMic(tester);

      await gesture.up();
      await tester.pump();
      recorder.startGate!.complete();
      await tester.pump();
      await tester.pump();

      expect(recorder.stopCount, 1);

      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('a cancel during startup stops the recorder immediately', (
      tester,
    ) async {
      recorder.startGate = Completer<void>();
      await pumpChat(tester);
      final gesture = await pressMic(tester);

      await gesture.cancel();
      await tester.pump();
      recorder.startGate!.complete();
      await tester.pump();
      await tester.pump();

      expect(recorder.cancelCount, 1);
      expect(find.byType(TextField), findsOneWidget);
      expect(stores.chatStore.messagesFor('peer-1'), isEmpty);
    });

    testWidgets('a second press while one is starting is ignored', (
      tester,
    ) async {
      recorder.startGate = Completer<void>();
      await pumpChat(tester);
      await pressMic(tester);
      await pressMic(tester);

      recorder.startGate!.complete();
      await tester.pump();

      expect(recorder.startCount, 1);
    });

    testWidgets('the recorder is disposed with the screen', (tester) async {
      await pumpChat(tester);

      await tester.pumpWidget(const SizedBox());

      expect(recorder.disposed, isTrue);
    });
  });

  group('attachments', () {
    testWidgets('the attach button is a no-op when no file is picked', (
      tester,
    ) async {
      await pumpChat(tester);

      await tapAndSettle(tester, find.byType(AttachButton));

      expect(stores.chatStore.messagesFor('peer-1'), isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('attaching is disabled while recording', (tester) async {
      await pumpChat(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(MicButton)),
      );
      await tester.pump();
      await tester.pump();

      expect(
        tester
            .widget<GestureDetector>(
              find
                  .ancestor(
                    of: find.byType(AttachButton),
                    matching: find.byType(GestureDetector),
                  )
                  .first,
            )
            .onTap,
        isNull,
      );

      await gesture.cancel();
      await tester.pump();
    });
  });

  group('relationship banners', () {
    testWidgets('an outgoing request replaces the composer with a notice', (
      tester,
    ) async {
      await stores.chatStore.setStatus(
        'peer-1',
        'Bob',
        ConversationStatus.pendingOutgoing,
      );
      await pumpChat(tester);

      expect(
        find.text(l10nFr.chatPendingOutgoingBanner('Bob')),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('an incoming request offers accept and decline', (
      tester,
    ) async {
      await stores.chatStore.setStatus(
        'peer-1',
        'Bob',
        ConversationStatus.pendingIncoming,
      );
      await pumpChat(tester);

      expect(
        find.text(l10nFr.chatPendingIncomingBanner('Bob')),
        findsOneWidget,
      );
      expect(find.text(l10nFr.requestAccept), findsOneWidget);
      expect(find.text(l10nFr.requestDecline), findsOneWidget);
    });

    testWidgets('accepting opens the conversation', (tester) async {
      await stores.chatStore.setStatus(
        'peer-1',
        'Bob',
        ConversationStatus.pendingIncoming,
      );
      await pumpChat(tester);

      await tester.tap(find.text(l10nFr.requestAccept));
      await tester.pump();

      expect(stores.chatStore.statusFor('peer-1'), ConversationStatus.accepted);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('declining clears the relationship and leaves the screen', (
      tester,
    ) async {
      await stores.chatStore.setStatus(
        'peer-1',
        'Bob',
        ConversationStatus.pendingIncoming,
      );
      await tester.pumpWidget(
        wrapWithApp(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      const ChatScreen(peerId: 'peer-1', peerAlias: 'Bob'),
                ),
              ),
              child: const Text('ouvrir'),
            ),
          ),
          stores: stores,
          discovery: discovery,
        ),
      );
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10nFr.requestDecline));
      await tester.pumpAndSettle();

      expect(stores.chatStore.statusFor('peer-1'), isNull);
      expect(find.byType(ChatScreen), findsNothing);
    });

    testWidgets('declining inline does not take the whole shell down', (
      tester,
    ) async {
      await stores.chatStore.setStatus(
        'peer-1',
        'Bob',
        ConversationStatus.pendingIncoming,
      );
      await pumpChat(tester);

      await tester.tap(find.text(l10nFr.requestDecline));
      await tester.pumpAndSettle();

      expect(stores.chatStore.statusFor('peer-1'), isNull);
      expect(find.byType(ChatScreen), findsOneWidget);

      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('a blocked peer gets a banner and an unblock button', (
      tester,
    ) async {
      await stores.chatStore.setStatus(
        'peer-1',
        'Bob',
        ConversationStatus.blocked,
      );
      await pumpChat(tester);

      expect(find.text(l10nFr.chatBlockedBanner('Bob')), findsOneWidget);
      expect(find.byType(TextField), findsNothing);

      await tester.tap(find.text(l10nFr.unblock));
      await tester.pump();

      expect(stores.chatStore.statusFor('peer-1'), isNull);
      expect(find.byType(TextField), findsOneWidget);
    });
  });

  group('blocking', () {
    testWidgets('the overflow menu can block the peer', (tester) async {
      await accept();
      await pumpChat(tester);

      await tester.tap(find.byType(PopupMenuButton<void>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10nFr.block));
      await tester.pumpAndSettle();

      expect(find.text(l10nFr.blockConfirmTitle('Bob')), findsOneWidget);
      await tester.tap(find.text(l10nFr.block).last);
      await tester.pumpAndSettle();

      expect(stores.chatStore.statusFor('peer-1'), ConversationStatus.blocked);
    });

    testWidgets('cancelling the confirmation leaves the peer alone', (
      tester,
    ) async {
      await accept();
      await pumpChat(tester);

      await tester.tap(find.byType(PopupMenuButton<void>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10nFr.block));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10nFr.cancel));
      await tester.pumpAndSettle();

      expect(stores.chatStore.statusFor('peer-1'), ConversationStatus.accepted);
    });

    testWidgets('the menu is hidden while a request is pending', (
      tester,
    ) async {
      await stores.chatStore.setStatus(
        'peer-1',
        'Bob',
        ConversationStatus.pendingIncoming,
      );
      await pumpChat(tester);

      expect(find.byType(PopupMenuButton<void>), findsNothing);
    });
  });
}
