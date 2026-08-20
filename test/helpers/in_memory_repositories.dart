import 'dart:io';
import 'dart:typed_data';

import 'package:peero/models/chat_message.dart';
import 'package:peero/services/audio_repository.dart';
import 'package:peero/services/avatar_repository.dart';
import 'package:peero/services/chat_repository.dart';
import 'package:peero/services/file_repository.dart';

class InMemoryChatRepository implements ChatRepository {
  final Map<String, List<ChatMessage>> messages = {};
  final Map<String, Map<String, dynamic>> index = {};

  @override
  Future<void> init({String? testStoragePath}) async {}

  @override
  Future<List<ChatMessage>> loadMessages(String peerId) async =>
      List.of(messages[peerId] ?? const []);

  @override
  Future<void> appendMessage(String peerId, ChatMessage message) async {
    messages.putIfAbsent(peerId, () => []).add(message);
  }

  @override
  List<ConversationSummary> allSummaries() {
    return [
      for (final entry in index.entries)
        ConversationSummary(
          peerId: entry.key,
          alias: entry.value['alias'] as String,
          lastText: entry.value['lastText'] as String,
          lastTimestamp: DateTime.parse(entry.value['lastTimestamp'] as String),
          unreadCount: entry.value['unread'] as int,
          status: ConversationStatus.values.byName(
            entry.value['status'] as String? ??
                ConversationStatus.accepted.name,
          ),
        ),
    ];
  }

  @override
  Future<void> recordInIndex(
    String peerId, {
    required String alias,
    required ChatMessage message,
    required bool incrementUnread,
  }) async {
    final currentUnread = index[peerId]?['unread'] as int? ?? 0;
    index[peerId] = {
      'alias': alias,
      'lastText': message.text,
      'lastTimestamp': message.timestamp.toIso8601String(),
      'unread': incrementUnread ? currentUnread + 1 : currentUnread,
      'status': ConversationStatus.accepted.name,
    };
  }

  @override
  Future<void> setStatus(
    String peerId, {
    required String alias,
    required ConversationStatus status,
  }) async {
    final entry =
        index[peerId] ??
        {
          'lastText': '',
          'lastTimestamp': DateTime.now().toIso8601String(),
          'unread': 0,
        };
    entry['alias'] = alias;
    entry['status'] = status.name;
    index[peerId] = entry;
  }

  @override
  Future<void> removeFromIndex(String peerId) async {
    index.remove(peerId);
  }

  @override
  Future<void> deleteConversation(String peerId) async {
    messages.remove(peerId);
    index.remove(peerId);
  }

  @override
  Future<void> deleteAllConversations() async {
    messages.clear();
    index.clear();
  }

  @override
  Future<void> markConversationRead(String peerId) async {
    index[peerId]?['unread'] = 0;
  }

  @override
  Future<int> storageBytesUsed() async {
    var total = 0;
    for (final conversation in messages.values) {
      for (final message in conversation) {
        total += message.text.length + 64;
      }
    }
    return total;
  }
}

class InMemoryAvatarRepository implements AvatarRepository {
  final Map<String, CachedAvatar> photos = {};

  @override
  Future<void> init() async {}

  @override
  Map<String, CachedAvatar> all() => Map.of(photos);

  @override
  CachedAvatar? photoFor(String peerId) => photos[peerId];

  @override
  Future<void> setPhoto(String peerId, Uint8List bytes, String version) async {
    photos[peerId] = CachedAvatar(bytes: bytes, version: version);
  }

  @override
  Future<void> removePhoto(String peerId) async {
    photos.remove(peerId);
  }

  @override
  Future<void> clearAll({required String exceptPeerId}) async {
    photos.removeWhere((key, _) => key != exceptPeerId);
  }
}

class InMemoryAudioRepository implements AudioRepository {
  final Map<String, Uint8List> clips = {};

  @override
  Future<void> init() async {}

  @override
  Uint8List? bytesFor(String messageId) => clips[messageId];

  @override
  Future<void> save(String messageId, Uint8List bytes) async {
    clips[messageId] = bytes;
  }

  @override
  Future<void> delete(String messageId) async {
    clips.remove(messageId);
  }
}

class InMemoryFileRepository implements FileRepository {
  final Map<String, FileRecord> records = {};

  @override
  Future<void> init() async {}

  @override
  FileRecord? recordFor(String messageId) => records[messageId];

  @override
  Future<void> save(
    String messageId, {
    required String fileName,
    required int sizeBytes,
    required FileTransferStatus status,
    String? localPath,
  }) async {
    records[messageId] = FileRecord(
      fileName: fileName,
      sizeBytes: sizeBytes,
      status: status,
      localPath: localPath,
    );
  }

  @override
  Future<void> delete(String messageId) async {
    final path = records[messageId]?.localPath;
    if (path != null) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
    records.remove(messageId);
  }
}
