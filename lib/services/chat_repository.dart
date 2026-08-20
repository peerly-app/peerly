import 'dart:io';

import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../models/chat_message.dart';

enum ConversationStatus { pendingOutgoing, pendingIncoming, accepted, blocked }

class ConversationSummary {
  final String peerId;
  final String alias;
  final String lastText;
  final DateTime lastTimestamp;
  final int unreadCount;
  final ConversationStatus status;

  ConversationSummary({
    required this.peerId,
    required this.alias,
    required this.lastText,
    required this.lastTimestamp,
    required this.unreadCount,
    required this.status,
  });
}

class ChatRepository {
  static const _hiveSubDir = 'hive_boxes';
  static const _indexBoxName = 'conversations_index';

  late final Box<Map> _indexBox;

  Future<void> init({String? testStoragePath}) async {
    if (testStoragePath != null) {
      Hive.init(testStoragePath);
    } else {
      await Hive.initFlutter(_hiveSubDir);
    }
    _indexBox = await Hive.openBox<Map>(_indexBoxName);
  }

  Future<Box<Map>> _chatBox(String peerId) {
    final name = 'chat_$peerId';
    if (Hive.isBoxOpen(name)) return Future.value(Hive.box<Map>(name));
    return Hive.openBox<Map>(name);
  }

  Future<List<ChatMessage>> loadMessages(String peerId) async {
    final box = await _chatBox(peerId);
    return box.values.map((raw) {
      final m = Map<String, dynamic>.from(raw);
      return ChatMessage.fromJson(m, isMine: m['isMine'] as bool);
    }).toList();
  }

  Future<void> appendMessage(String peerId, ChatMessage message) async {
    final box = await _chatBox(peerId);
    await box.add({...message.toJson(), 'isMine': message.isMine});
  }

  ConversationSummary _summaryFor(dynamic key) {
    final m = Map<String, dynamic>.from(_indexBox.get(key) as Map);
    return ConversationSummary(
      peerId: key as String,
      alias: m['alias'] as String,
      lastText: m['lastText'] as String,
      lastTimestamp: DateTime.parse(m['lastTimestamp'] as String),
      unreadCount: m['unread'] as int,

      status: ConversationStatus.values.byName(
        m['status'] as String? ?? ConversationStatus.accepted.name,
      ),
    );
  }

  List<ConversationSummary> allSummaries() =>
      _indexBox.keys.map(_summaryFor).toList();

  Future<void> recordInIndex(
    String peerId, {
    required String alias,
    required ChatMessage message,
    required bool incrementUnread,
  }) async {
    final existing = _indexBox.get(peerId);
    final currentUnread = existing != null ? existing['unread'] as int : 0;
    await _indexBox.put(peerId, {
      'alias': alias,
      'lastText': message.text,
      'lastTimestamp': message.timestamp.toIso8601String(),
      'unread': incrementUnread ? currentUnread + 1 : currentUnread,
      'status': ConversationStatus.accepted.name,
    });
  }

  Future<void> setStatus(
    String peerId, {
    required String alias,
    required ConversationStatus status,
  }) async {
    final existing = _indexBox.get(peerId);
    final m = existing != null
        ? Map<String, dynamic>.from(existing)
        : <String, dynamic>{
            'lastText': '',
            'lastTimestamp': DateTime.now().toIso8601String(),
            'unread': 0,
          };
    m['alias'] = alias;
    m['status'] = status.name;
    await _indexBox.put(peerId, m);
  }

  Future<void> removeFromIndex(String peerId) async {
    await _indexBox.delete(peerId);
  }

  Future<void> deleteConversation(String peerId) async {
    await Hive.deleteBoxFromDisk('chat_$peerId');
    await _indexBox.delete(peerId);
  }

  Future<void> deleteAllConversations() async {
    for (final peerId in _indexBox.keys.toList()) {
      await Hive.deleteBoxFromDisk('chat_$peerId');
    }
    await _indexBox.clear();
  }

  Future<void> markConversationRead(String peerId) async {
    final existing = _indexBox.get(peerId);
    if (existing == null) return;
    final m = Map<String, dynamic>.from(existing);
    m['unread'] = 0;
    await _indexBox.put(peerId, m);
  }

  Future<int> storageBytesUsed() async {
    final boxPath = _indexBox.path;
    if (boxPath == null) return 0;
    final dir = Directory(boxPath).parent;
    if (!await dir.exists()) return 0;

    var total = 0;
    await for (final entity in dir.list()) {
      if (entity is File) {
        total += await entity.length();
      }
    }
    return total;
  }
}
