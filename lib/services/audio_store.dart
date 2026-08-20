import 'package:flutter/foundation.dart';

import '../models/peer.dart';
import 'audio_client.dart';
import 'audio_repository.dart';

class AudioStore extends ChangeNotifier {
  final AudioRepository repository;
  final AudioClient _client;

  final Map<String, Uint8List> _bytes = {};
  final Set<String> _fetching = {};

  AudioStore({required this.repository, AudioClient? client})
    : _client = client ?? AudioClient();

  Uint8List? bytesFor(String messageId) {
    final cached = _bytes[messageId];
    if (cached != null) return cached;
    final stored = repository.bytesFor(messageId);
    if (stored != null) _bytes[messageId] = stored;
    return stored;
  }

  Future<void> saveOwnRecording(String messageId, Uint8List bytes) async {
    await repository.save(messageId, bytes);
    _bytes[messageId] = bytes;
    notifyListeners();
  }

  Future<void> ensureFetched(String messageId, Peer peer) async {
    if (_bytes.containsKey(messageId)) return;
    if (!_fetching.add(messageId)) return;
    try {
      final bytes = await _client.fetch(peer, messageId);
      if (bytes == null) return;
      await repository.save(messageId, bytes);
      _bytes[messageId] = bytes;
      notifyListeners();
    } finally {
      _fetching.remove(messageId);
    }
  }

  Future<void> deleteMessages(Iterable<String> messageIds) async {
    if (messageIds.isEmpty) return;
    for (final id in messageIds) {
      await repository.delete(id);
      _bytes.remove(id);
    }
    notifyListeners();
  }
}
