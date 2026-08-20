import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:peero/models/chat_message.dart';
import 'package:peero/services/chat_repository.dart';

void main() {
  late Directory tempDir;
  late ChatRepository repository;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('peero_test_');
    repository = ChatRepository();
    await repository.init(testStoragePath: tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  test(
    'appendMessage + loadMessages round-trips message content and order',
    () async {
      final first = ChatMessage(
        fromId: 'me',
        fromAlias: 'Alice',
        text: 'Salut',
        timestamp: DateTime.utc(2026, 1, 1, 10),
        isMine: true,
      );
      final second = ChatMessage(
        fromId: 'peer-1',
        fromAlias: 'Bob',
        text: 'Yo',
        timestamp: DateTime.utc(2026, 1, 1, 10, 1),
        isMine: false,
      );

      await repository.appendMessage('peer-1', first);
      await repository.appendMessage('peer-1', second);

      final loaded = await repository.loadMessages('peer-1');

      expect(loaded, hasLength(2));
      expect(loaded[0].text, 'Salut');
      expect(loaded[0].isMine, isTrue);
      expect(loaded[1].text, 'Yo');
      expect(loaded[1].isMine, isFalse);
    },
  );

  test(
    'recordInIndex increments unread only when asked, markConversationRead resets it',
    () async {
      final message = ChatMessage(
        fromId: 'peer-1',
        fromAlias: 'Bob',
        text: 'Hey',
        timestamp: DateTime.utc(2026, 1, 1),
        isMine: false,
      );

      await repository.recordInIndex(
        'peer-1',
        alias: 'Bob',
        message: message,
        incrementUnread: true,
      );
      await repository.recordInIndex(
        'peer-1',
        alias: 'Bob',
        message: message,
        incrementUnread: true,
      );

      var summaries = repository.allSummaries();
      expect(summaries.single.unreadCount, 2);

      await repository.markConversationRead('peer-1');
      summaries = repository.allSummaries();
      expect(summaries.single.unreadCount, 0);
    },
  );

  test(
    'storageBytesUsed reports a positive size once data has been written',
    () async {
      final message = ChatMessage(
        fromId: 'peer-1',
        fromAlias: 'Bob',
        text: 'Hey',
        timestamp: DateTime.utc(2026, 1, 1),
        isMine: false,
      );
      await repository.appendMessage('peer-1', message);

      final bytes = await repository.storageBytesUsed();
      expect(bytes, greaterThan(0));
    },
  );

  test(
    'deleteConversation removes messages and the index entry for that peer only',
    () async {
      final message = ChatMessage(
        fromId: 'peer-1',
        fromAlias: 'Bob',
        text: 'Hey',
        timestamp: DateTime.utc(2026, 1, 1),
        isMine: false,
      );
      await repository.appendMessage('peer-1', message);
      await repository.recordInIndex(
        'peer-1',
        alias: 'Bob',
        message: message,
        incrementUnread: true,
      );
      await repository.appendMessage('peer-2', message);
      await repository.recordInIndex(
        'peer-2',
        alias: 'Carol',
        message: message,
        incrementUnread: true,
      );

      await repository.deleteConversation('peer-1');

      expect(await repository.loadMessages('peer-1'), isEmpty);
      final summaries = repository.allSummaries();
      expect(summaries.map((s) => s.peerId), ['peer-2']);
    },
  );

  test(
    'setStatus creates a pending entry, then upserts alias/status on it',
    () async {
      await repository.setStatus(
        'peer-1',
        alias: 'Bob',
        status: ConversationStatus.pendingOutgoing,
      );

      var summaries = repository.allSummaries();
      expect(summaries.single.status, ConversationStatus.pendingOutgoing);
      expect(summaries.single.alias, 'Bob');
      expect(summaries.single.lastText, '');

      await repository.setStatus(
        'peer-1',
        alias: 'Bobby',
        status: ConversationStatus.accepted,
      );

      summaries = repository.allSummaries();
      expect(summaries.single.status, ConversationStatus.accepted);
      expect(summaries.single.alias, 'Bobby');
    },
  );

  test(
    'allSummaries reports blocked peers alongside the rest, with their status',
    () async {
      await repository.setStatus(
        'peer-1',
        alias: 'Bob',
        status: ConversationStatus.accepted,
      );
      await repository.setStatus(
        'peer-2',
        alias: 'Carol',
        status: ConversationStatus.blocked,
      );

      final byId = {
        for (final s in repository.allSummaries()) s.peerId: s.status,
      };

      expect(byId, {
        'peer-1': ConversationStatus.accepted,
        'peer-2': ConversationStatus.blocked,
      });
    },
  );

  test(
    'an index entry written before the handshake existed reads as accepted',
    () async {
      final message = ChatMessage(
        fromId: 'peer-1',
        fromAlias: 'Bob',
        text: 'Hey',
        timestamp: DateTime.utc(2026, 1, 1),
        isMine: false,
      );

      await repository.recordInIndex(
        'peer-1',
        alias: 'Bob',
        message: message,
        incrementUnread: false,
      );

      expect(
        repository.allSummaries().single.status,
        ConversationStatus.accepted,
      );
    },
  );

  test('markConversationRead is a no-op for an unknown peer', () async {
    await repository.markConversationRead('nobody');
    expect(repository.allSummaries(), isEmpty);
  });

  test('storageBytesUsed counts every box file in the directory', () async {
    await repository.appendMessage(
      'peer-1',
      ChatMessage(
        fromId: 'peer-1',
        fromAlias: 'Bob',
        text: 'Hey',
        timestamp: DateTime.utc(2026, 1, 1),
        isMine: false,
      ),
    );
    final withOne = await repository.storageBytesUsed();

    await repository.appendMessage(
      'peer-2',
      ChatMessage(
        fromId: 'peer-2',
        fromAlias: 'Carol',
        text: 'Encore un message bien plus long que le premier',
        timestamp: DateTime.utc(2026, 1, 1),
        isMine: false,
      ),
    );

    expect(await repository.storageBytesUsed(), greaterThan(withOne));
  });

  test(
    'removeFromIndex drops the relationship but keeps message history',
    () async {
      final message = ChatMessage(
        fromId: 'peer-1',
        fromAlias: 'Bob',
        text: 'Hey',
        timestamp: DateTime.utc(2026, 1, 1),
        isMine: false,
      );
      await repository.appendMessage('peer-1', message);
      await repository.recordInIndex(
        'peer-1',
        alias: 'Bob',
        message: message,
        incrementUnread: true,
      );

      await repository.removeFromIndex('peer-1');

      expect(repository.allSummaries(), isEmpty);
      expect(await repository.loadMessages('peer-1'), hasLength(1));
    },
  );

  test('deleteAllConversations clears every conversation', () async {
    final message = ChatMessage(
      fromId: 'peer-1',
      fromAlias: 'Bob',
      text: 'Hey',
      timestamp: DateTime.utc(2026, 1, 1),
      isMine: false,
    );
    await repository.appendMessage('peer-1', message);
    await repository.recordInIndex(
      'peer-1',
      alias: 'Bob',
      message: message,
      incrementUnread: true,
    );
    await repository.appendMessage('peer-2', message);
    await repository.recordInIndex(
      'peer-2',
      alias: 'Carol',
      message: message,
      incrementUnread: true,
    );

    await repository.deleteAllConversations();

    expect(repository.allSummaries(), isEmpty);
    expect(await repository.loadMessages('peer-1'), isEmpty);
    expect(await repository.loadMessages('peer-2'), isEmpty);
  });
}
