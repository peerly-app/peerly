import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../models/chat_message.dart';
import 'audio_store.dart';
import 'avatar_store.dart';
import 'chat_repository.dart';
import 'file_store.dart';

class ChatStore extends ChangeNotifier {
  final ChatRepository repository;
  final AvatarStore avatarStore;
  final AudioStore audioStore;
  final FileStore fileStore;

  ChatStore(this.repository, this.avatarStore, this.audioStore, this.fileStore);

  final Map<String, List<ChatMessage>> _messagesByPeerId = {};

  final Map<String, Future<void>> _loading = {};

  Map<String, ConversationSummary> _summaries = {};

  List<ConversationSummary>? _conversationsView;
  List<ConversationSummary>? _blockedView;

  String? currentlyViewedPeerId;

  List<ConversationSummary> get conversations =>
      _conversationsView ??= _sortedSummaries(
        keep: (s) => s.status != ConversationStatus.blocked,
        by: (a, b) => b.lastTimestamp.compareTo(a.lastTimestamp),
      );

  List<ConversationSummary> get blockedConversations =>
      _blockedView ??= _sortedSummaries(
        keep: (s) => s.status == ConversationStatus.blocked,
        by: (a, b) => a.alias.compareTo(b.alias),
      );

  List<ConversationSummary> _sortedSummaries({
    required bool Function(ConversationSummary) keep,
    required int Function(ConversationSummary, ConversationSummary) by,
  }) {
    final list = _summaries.values.where(keep).toList()..sort(by);
    return List.unmodifiable(list);
  }

  void loadSummaries() {
    _refreshSummaries();
    notifyListeners();
  }

  void _refreshSummaries() {
    _summaries = {for (final s in repository.allSummaries()) s.peerId: s};
    _conversationsView = null;
    _blockedView = null;
  }

  List<ChatMessage> messagesFor(String peerId) =>
      UnmodifiableListView(_messagesByPeerId[peerId] ?? const []);

  Future<void> ensureLoaded(String peerId) {
    if (_messagesByPeerId.containsKey(peerId)) return Future.value();
    return _loading[peerId] ??= _load(peerId);
  }

  Future<void> _load(String peerId) async {
    try {
      final messages = await repository.loadMessages(peerId);

      if (!_loading.containsKey(peerId)) return;
      _messagesByPeerId[peerId] = messages;
      notifyListeners();
    } finally {
      _loading.remove(peerId);
    }
  }

  Future<void> add(String peerId, String peerAlias, ChatMessage message) async {
    await ensureLoaded(peerId);
    _messagesByPeerId[peerId]!.add(message);
    final incrementUnread = !message.isMine && currentlyViewedPeerId != peerId;
    await repository.appendMessage(peerId, message);
    await repository.recordInIndex(
      peerId,
      alias: peerAlias,
      message: message,
      incrementUnread: incrementUnread,
    );
    _refreshSummaries();
    notifyListeners();
  }

  Future<({List<String> voiceIds, List<String> fileIds})> _mediaMessageIdsFor(
    String peerId,
  ) async {
    final messages = await _messagesOf(peerId);
    final voiceIds = <String>[];
    final fileIds = <String>[];
    for (final m in messages) {
      if (m.kind == MessageKind.voice) voiceIds.add(m.id);
      if (m.kind == MessageKind.file) fileIds.add(m.id);
    }
    return (voiceIds: voiceIds, fileIds: fileIds);
  }

  Future<List<ChatMessage>> _messagesOf(String peerId) async =>
      _messagesByPeerId[peerId] ?? await repository.loadMessages(peerId);

  Future<void> deleteConversation(String peerId) async {
    final media = await _mediaMessageIdsFor(peerId);
    _messagesByPeerId.remove(peerId);
    _loading.remove(peerId);
    await repository.deleteConversation(peerId);
    await avatarStore.removePeerPhoto(peerId);
    await audioStore.deleteMessages(media.voiceIds);
    await fileStore.deleteMessages(media.fileIds);
    _refreshSummaries();
    notifyListeners();
  }

  Future<void> deleteAllConversations() async {
    final peerIds = _summaries.keys.toList();
    final voiceIds = <String>[];
    final fileIds = <String>[];
    for (final peerId in peerIds) {
      final media = await _mediaMessageIdsFor(peerId);
      voiceIds.addAll(media.voiceIds);
      fileIds.addAll(media.fileIds);
    }
    _messagesByPeerId.clear();
    _loading.clear();
    await repository.deleteAllConversations();
    for (final peerId in peerIds) {
      await avatarStore.removePeerPhoto(peerId);
    }
    await audioStore.deleteMessages(voiceIds);
    await fileStore.deleteMessages(fileIds);
    _refreshSummaries();
    notifyListeners();
  }

  void setViewing(String? peerId) {
    currentlyViewedPeerId = peerId;
    if (peerId == null) return;

    unawaited(repository.markConversationRead(peerId));
    loadSummaries();
  }

  Future<int> storageBytesUsed() async =>
      await repository.storageBytesUsed() + await fileStore.storageBytesUsed();

  ConversationStatus? statusFor(String peerId) => _summaries[peerId]?.status;

  bool isKnownContact(String peerId) {
    final status = statusFor(peerId);
    return status != null && status != ConversationStatus.blocked;
  }

  Future<void> setStatus(
    String peerId,
    String alias,
    ConversationStatus status,
  ) async {
    await repository.setStatus(peerId, alias: alias, status: status);
    loadSummaries();
  }

  Future<void> resetRelationship(String peerId) async {
    await repository.removeFromIndex(peerId);
    loadSummaries();
  }

  Future<List<String>> receivedFileIdsForAllConversations() async {
    final ids = <String>[];
    for (final peerId in _summaries.keys) {
      for (final m in await _messagesOf(peerId)) {
        if (m.kind == MessageKind.file && !m.isMine) ids.add(m.id);
      }
    }
    return ids;
  }
}
