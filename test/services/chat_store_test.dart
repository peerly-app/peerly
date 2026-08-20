import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:peero/models/chat_message.dart';
import 'package:peero/services/chat_repository.dart';

import '../helpers/test_harness.dart';

ChatMessage message({
  String fromId = 'peer-1',
  String alias = 'Bob',
  String text = 'Hey',
  DateTime? timestamp,
  bool isMine = false,
  MessageKind kind = MessageKind.text,
  String? id,
}) {
  return ChatMessage(
    id: id,
    fromId: fromId,
    fromAlias: alias,
    text: text,
    timestamp: timestamp ?? DateTime.utc(2026, 1, 1, 10),
    isMine: isMine,
    kind: kind,
    fileName: kind == MessageKind.file ? 'rapport.pdf' : null,
    fileSizeBytes: kind == MessageKind.file ? 1024 : null,
    voiceDurationMs: kind == MessageKind.voice ? 3000 : null,
  );
}

void main() {
  late TestStores stores;

  setUp(() async {
    TestPathProvider.install();
    stores = await TestStores.create();
  });
  tearDown(() async => stores.dispose());

  group('status', () {
    test('is null for a peer we have never interacted with', () {
      expect(stores.chatStore.statusFor('stranger'), isNull);
    });

    test('a blocked peer keeps reporting as blocked', () async {
      await stores.chatStore.setStatus(
        'peer-1',
        'Bob',
        ConversationStatus.blocked,
      );

      expect(stores.chatStore.statusFor('peer-1'), ConversationStatus.blocked);
    });

    test('survives a reload from disk', () async {
      await stores.chatStore.setStatus(
        'peer-1',
        'Bob',
        ConversationStatus.blocked,
      );

      stores.chatStore.loadSummaries();

      expect(stores.chatStore.statusFor('peer-1'), ConversationStatus.blocked);
    });

    test('resetRelationship clears it', () async {
      await stores.chatStore.setStatus(
        'peer-1',
        'Bob',
        ConversationStatus.blocked,
      );
      await stores.chatStore.resetRelationship('peer-1');

      expect(stores.chatStore.statusFor('peer-1'), isNull);
      expect(stores.chatStore.blockedConversations, isEmpty);
    });
  });

  group('conversation lists', () {
    setUp(() async {
      await stores.chatStore.add(
        'peer-1',
        'Bob',
        message(timestamp: DateTime.utc(2026, 1, 1)),
      );
      await stores.chatStore.add(
        'peer-2',
        'Carol',
        message(fromId: 'peer-2', timestamp: DateTime.utc(2026, 1, 3)),
      );
      await stores.chatStore.setStatus(
        'peer-3',
        'Zoe',
        ConversationStatus.blocked,
      );
      await stores.chatStore.setStatus(
        'peer-4',
        'Alice',
        ConversationStatus.blocked,
      );
    });

    test('conversations excludes blocked peers, newest first', () {
      expect(stores.chatStore.conversations.map((c) => c.peerId), [
        'peer-2',
        'peer-1',
      ]);
    });

    test('blockedConversations lists only blocked peers, alias-sorted', () {
      expect(stores.chatStore.blockedConversations.map((c) => c.alias), [
        'Alice',
        'Zoe',
      ]);
    });

    test('the two lists are disjoint and cover every relationship', () {
      final all = {
        ...stores.chatStore.conversations.map((c) => c.peerId),
        ...stores.chatStore.blockedConversations.map((c) => c.peerId),
      };
      expect(all, {'peer-1', 'peer-2', 'peer-3', 'peer-4'});
    });
  });

  group('add', () {
    test('appends to memory and to disk', () async {
      await stores.chatStore.add('peer-1', 'Bob', message(text: 'Salut'));

      expect(stores.chatStore.messagesFor('peer-1').single.text, 'Salut');
      expect(
        (await stores.chatRepository.loadMessages('peer-1')).single.text,
        'Salut',
      );
    });

    test(
      'counts an incoming message as unread when the chat is not open',
      () async {
        await stores.chatStore.add('peer-1', 'Bob', message());

        expect(stores.chatStore.conversations.single.unreadCount, 1);
      },
    );

    test('does not count it while that chat is being viewed', () async {
      stores.chatStore.setViewing('peer-1');
      await stores.chatStore.add('peer-1', 'Bob', message());

      expect(stores.chatStore.conversations.single.unreadCount, 0);
    });

    test('never counts our own messages as unread', () async {
      await stores.chatStore.add(
        'peer-1',
        'Bob',
        message(isMine: true, fromId: 'me'),
      );

      expect(stores.chatStore.conversations.single.unreadCount, 0);
    });

    test('notifies listeners exactly once per message', () async {
      await stores.chatStore.ensureLoaded('peer-1');
      var notifications = 0;
      stores.chatStore.addListener(() => notifications++);

      await stores.chatStore.add('peer-1', 'Bob', message());
      await stores.chatStore.add('peer-1', 'Bob', message(text: 'encore'));

      expect(notifications, 2);
    });

    test(
      'a cold conversation notifies once more, for the history it loaded',
      () async {
        var notifications = 0;
        stores.chatStore.addListener(() => notifications++);

        await stores.chatStore.add('peer-1', 'Bob', message());

        expect(notifications, 2);
      },
    );
  });

  group('messagesFor', () {
    test('is empty for an unknown peer', () {
      expect(stores.chatStore.messagesFor('nobody'), isEmpty);
    });

    test('cannot be mutated by callers', () async {
      await stores.chatStore.add('peer-1', 'Bob', message());
      final messages = stores.chatStore.messagesFor('peer-1');

      expect(() => messages.add(message()), throwsUnsupportedError);
    });

    test('reflects later additions without needing another call', () async {
      await stores.chatStore.add('peer-1', 'Bob', message());
      final view = stores.chatStore.messagesFor('peer-1');
      await stores.chatStore.add('peer-1', 'Bob', message(text: 'second'));

      expect(view, hasLength(2));
    });
  });

  group('cold conversations', () {
    test(
      'an arriving message does not hide the history already on disk',
      () async {
        await stores.chatRepository.appendMessage(
          'peer-1',
          message(text: 'ancien'),
        );

        await stores.chatStore.add('peer-1', 'Bob', message(text: 'nouveau'));
        await stores.chatStore.ensureLoaded('peer-1');

        expect(stores.chatStore.messagesFor('peer-1').map((m) => m.text), [
          'ancien',
          'nouveau',
        ]);
      },
    );

    test(
      'the warmed history is complete straight after the message lands',
      () async {
        await stores.chatRepository.appendMessage(
          'peer-1',
          message(text: 'ancien'),
        );

        await stores.chatStore.add('peer-1', 'Bob', message(text: 'nouveau'));

        expect(stores.chatStore.messagesFor('peer-1'), hasLength(2));
      },
    );

    test('a first message to a brand-new conversation still works', () async {
      await stores.chatStore.add('peer-1', 'Bob', message(text: 'premier'));

      expect(stores.chatStore.messagesFor('peer-1').single.text, 'premier');
    });
  });

  group('ensureLoaded', () {
    test('pulls a conversation off disk the first time', () async {
      await stores.chatRepository.appendMessage(
        'peer-1',
        message(text: 'depuis le disque'),
      );

      await stores.chatStore.ensureLoaded('peer-1');

      expect(
        stores.chatStore.messagesFor('peer-1').single.text,
        'depuis le disque',
      );
    });

    test('does not re-read a conversation already in memory', () async {
      await stores.chatStore.ensureLoaded('peer-1');
      await stores.chatRepository.appendMessage('peer-1', message());

      await stores.chatStore.ensureLoaded('peer-1');

      expect(stores.chatStore.messagesFor('peer-1'), isEmpty);
    });

    test(
      'concurrent callers share one read instead of clobbering each other',
      () async {
        await stores.chatRepository.appendMessage(
          'peer-1',
          message(text: 'depuis le disque'),
        );

        await Future.wait([
          stores.chatStore.ensureLoaded('peer-1'),
          stores.chatStore.ensureLoaded('peer-1'),
          stores.chatStore.ensureLoaded('peer-1'),
        ]);

        expect(stores.chatStore.messagesFor('peer-1'), hasLength(1));
      },
    );

    test(
      'a read still in flight does not resurrect a deleted conversation',
      () async {
        await stores.chatRepository.appendMessage('peer-1', message());
        final loading = stores.chatStore.ensureLoaded('peer-1');

        await stores.chatStore.deleteConversation('peer-1');
        await loading;

        expect(stores.chatStore.messagesFor('peer-1'), isEmpty);
      },
    );
  });

  group('isKnownContact', () {
    test('is false for a stranger on the network', () {
      expect(stores.chatStore.isKnownContact('peer-1'), isFalse);
    });

    test('is true for any live relationship', () async {
      for (final status in [
        ConversationStatus.pendingOutgoing,
        ConversationStatus.pendingIncoming,
        ConversationStatus.accepted,
      ]) {
        await stores.chatStore.setStatus('peer-1', 'Bob', status);
        expect(
          stores.chatStore.isKnownContact('peer-1'),
          isTrue,
          reason: status.name,
        );
      }
    });

    test('is false once the peer is blocked', () async {
      await stores.chatStore.setStatus(
        'peer-1',
        'Bob',
        ConversationStatus.blocked,
      );

      expect(stores.chatStore.isKnownContact('peer-1'), isFalse);
    });
  });

  group('conversation list caching', () {
    test('hands back the same list until something changes', () async {
      await stores.chatStore.add('peer-1', 'Bob', message());

      expect(
        identical(
          stores.chatStore.conversations,
          stores.chatStore.conversations,
        ),
        isTrue,
      );
    });

    test('rebuilds the list after a change', () async {
      await stores.chatStore.add('peer-1', 'Bob', message());
      final before = stores.chatStore.conversations;

      await stores.chatStore.add('peer-2', 'Carol', message(fromId: 'peer-2'));

      expect(identical(before, stores.chatStore.conversations), isFalse);
      expect(stores.chatStore.conversations, hasLength(2));
    });

    test('the lists it hands out cannot be mutated', () async {
      await stores.chatStore.add('peer-1', 'Bob', message());

      expect(
        () => stores.chatStore.conversations.clear(),
        throwsUnsupportedError,
      );
      expect(
        () => stores.chatStore.blockedConversations.clear(),
        throwsUnsupportedError,
      );
    });
  });

  group('setViewing', () {
    test(
      'clears the unread counter for the conversation being opened',
      () async {
        await stores.chatStore.add('peer-1', 'Bob', message());
        expect(stores.chatStore.conversations.single.unreadCount, 1);

        stores.chatStore.setViewing('peer-1');

        expect(stores.chatStore.conversations.single.unreadCount, 0);
      },
    );

    test('clearing the viewed peer touches nothing', () async {
      await stores.chatStore.add('peer-1', 'Bob', message());

      stores.chatStore.setViewing(null);

      expect(stores.chatStore.currentlyViewedPeerId, isNull);
      expect(stores.chatStore.conversations.single.unreadCount, 1);
    });
  });

  group('deleteConversation', () {
    test('drops the messages, the index entry and the cached photo', () async {
      await stores.avatarRepository.setPhoto(
        'peer-1',
        Uint8List.fromList([1, 2]),
        'v1',
      );
      stores.avatarStore.load();
      await stores.chatStore.add('peer-1', 'Bob', message());

      await stores.chatStore.deleteConversation('peer-1');

      expect(stores.chatStore.conversations, isEmpty);
      expect(stores.chatStore.messagesFor('peer-1'), isEmpty);
      expect(await stores.chatRepository.loadMessages('peer-1'), isEmpty);
      expect(stores.avatarStore.photoBytes('peer-1'), isNull);
    });

    test('purges the voice and file media of that conversation only', () async {
      final voice = message(kind: MessageKind.voice, id: 'voice-1');
      final file = message(kind: MessageKind.file, id: 'file-1');
      final otherVoice = message(kind: MessageKind.voice, id: 'voice-2');
      await stores.audioStore.saveOwnRecording(
        'voice-1',
        Uint8List.fromList([1]),
      );
      await stores.audioStore.saveOwnRecording(
        'voice-2',
        Uint8List.fromList([2]),
      );
      await stores.fileStore.registerIncoming(
        'file-1',
        fileName: 'rapport.pdf',
        sizeBytes: 1024,
      );
      await stores.chatStore.add('peer-1', 'Bob', voice);
      await stores.chatStore.add('peer-1', 'Bob', file);
      await stores.chatStore.add('peer-2', 'Carol', otherVoice);

      await stores.chatStore.deleteConversation('peer-1');

      expect(stores.audioStore.bytesFor('voice-1'), isNull);
      expect(stores.fileStore.recordFor('file-1'), isNull);
      expect(stores.audioStore.bytesFor('voice-2'), isNotNull);
    });

    test('finds the media of a conversation that was never opened', () async {
      await stores.chatRepository.appendMessage(
        'peer-1',
        message(kind: MessageKind.voice, id: 'voice-1'),
      );
      await stores.audioStore.saveOwnRecording(
        'voice-1',
        Uint8List.fromList([1]),
      );

      await stores.chatStore.deleteConversation('peer-1');

      expect(stores.audioStore.bytesFor('voice-1'), isNull);
    });
  });

  group('deleteAllConversations', () {
    test('wipes accepted and blocked conversations alike', () async {
      await stores.chatStore.add('peer-1', 'Bob', message());
      await stores.chatStore.setStatus(
        'peer-2',
        'Carol',
        ConversationStatus.blocked,
      );

      await stores.chatStore.deleteAllConversations();

      expect(stores.chatStore.conversations, isEmpty);
      expect(stores.chatStore.blockedConversations, isEmpty);
      expect(stores.chatStore.statusFor('peer-2'), isNull);
    });

    test('purges media across every conversation', () async {
      await stores.audioStore.saveOwnRecording(
        'voice-1',
        Uint8List.fromList([1]),
      );
      await stores.fileStore.registerIncoming(
        'file-1',
        fileName: 'a.pdf',
        sizeBytes: 1,
      );
      await stores.chatStore.add(
        'peer-1',
        'Bob',
        message(kind: MessageKind.voice, id: 'voice-1'),
      );
      await stores.chatStore.add(
        'peer-2',
        'Carol',
        message(kind: MessageKind.file, id: 'file-1'),
      );

      await stores.chatStore.deleteAllConversations();

      expect(stores.audioStore.bytesFor('voice-1'), isNull);
      expect(stores.fileStore.recordFor('file-1'), isNull);
    });
  });

  group('receivedFileIdsForAllConversations', () {
    test('returns received files only, never our own', () async {
      await stores.chatStore.add(
        'peer-1',
        'Bob',
        message(kind: MessageKind.file, id: 'theirs'),
      );
      await stores.chatStore.add(
        'peer-1',
        'Bob',
        message(kind: MessageKind.file, id: 'mine', isMine: true),
      );
      await stores.chatStore.add('peer-1', 'Bob', message(id: 'text'));

      expect(await stores.chatStore.receivedFileIdsForAllConversations(), [
        'theirs',
      ]);
    });

    test('includes files from blocked conversations', () async {
      await stores.chatStore.add(
        'peer-1',
        'Bob',
        message(kind: MessageKind.file, id: 'theirs'),
      );
      await stores.chatStore.setStatus(
        'peer-1',
        'Bob',
        ConversationStatus.blocked,
      );

      expect(await stores.chatStore.receivedFileIdsForAllConversations(), [
        'theirs',
      ]);
    });
  });

  test(
    'storageBytesUsed covers the Hive boxes and the transferred files',
    () async {
      await stores.chatStore.add('peer-1', 'Bob', message());

      expect(await stores.chatStore.storageBytesUsed(), greaterThan(0));
    },
  );
}
