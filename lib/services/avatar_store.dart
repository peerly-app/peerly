import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../models/peer.dart';
import 'avatar_client.dart';
import 'avatar_repository.dart';

const _maxAvatarDimension = 480;

Uint8List resizeAndEncodeAvatar(Uint8List input) {
  final decoded = img.decodeImage(input);
  if (decoded == null) {
    throw const FormatException('Unsupported image format');
  }
  final longestSide = decoded.width > decoded.height
      ? decoded.width
      : decoded.height;
  final resized = longestSide <= _maxAvatarDimension
      ? decoded
      : decoded.width >= decoded.height
      ? img.copyResize(decoded, width: _maxAvatarDimension)
      : img.copyResize(decoded, height: _maxAvatarDimension);
  return Uint8List.fromList(img.encodeJpg(resized, quality: 85));
}

class AvatarStore extends ChangeNotifier {
  final AvatarRepository repository;
  final AvatarClient _client;

  final Map<String, Uint8List> _bytes = {};
  final Map<String, String> _versions = {};
  final Set<String> _fetching = {};

  AvatarStore({required this.repository, AvatarClient? client})
    : _client = client ?? AvatarClient();

  Uint8List? photoBytes(String peerId) => _bytes[peerId];

  String? versionFor(String peerId) => _versions[peerId];

  void load() {
    for (final entry in repository.all().entries) {
      _bytes[entry.key] = entry.value.bytes;
      _versions[entry.key] = entry.value.version;
    }
  }

  Future<void> setOwnPhoto(String ownId, Uint8List rawBytes) async {
    final encoded = await compute(resizeAndEncodeAvatar, rawBytes);
    final version = DateTime.now().microsecondsSinceEpoch.toString();
    await repository.setPhoto(ownId, encoded, version);
    _bytes[ownId] = encoded;
    _versions[ownId] = version;
    notifyListeners();
  }

  Future<void> removeOwnPhoto(String ownId) async {
    await repository.removePhoto(ownId);
    _bytes.remove(ownId);
    _versions.remove(ownId);
    notifyListeners();
  }

  Future<void> removePeerPhoto(String peerId) async {
    await repository.removePhoto(peerId);
    _bytes.remove(peerId);
    _versions.remove(peerId);
    notifyListeners();
  }

  Future<void> clearCachedPhotos({required String exceptPeerId}) async {
    await repository.clearAll(exceptPeerId: exceptPeerId);
    _bytes.removeWhere((key, _) => key != exceptPeerId);
    notifyListeners();
  }

  void syncFromPeers(List<Peer> peers) {
    for (final peer in peers) {
      final remoteVersion = peer.avatarVersion;
      if (remoteVersion == null) continue;
      if (_versions[peer.id] == remoteVersion) continue;
      if (!_fetching.add(peer.id)) continue;
      unawaited(_fetch(peer, remoteVersion));
    }
  }

  Future<void> _fetch(Peer peer, String version) async {
    try {
      final bytes = await _client.fetch(peer);
      if (bytes == null) return;
      await repository.setPhoto(peer.id, bytes, version);
      _bytes[peer.id] = bytes;
      _versions[peer.id] = version;
      notifyListeners();
    } finally {
      _fetching.remove(peer.id);
    }
  }
}
