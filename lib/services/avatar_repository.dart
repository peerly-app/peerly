import 'dart:typed_data';

import 'package:hive_ce_flutter/hive_ce_flutter.dart';

class CachedAvatar {
  final Uint8List bytes;
  final String version;

  CachedAvatar({required this.bytes, required this.version});
}

class AvatarRepository {
  static const _boxName = 'avatars';

  late final Box<Map> _box;

  Future<void> init() async {
    _box = await Hive.openBox<Map>(_boxName);
  }

  Map<String, CachedAvatar> all() {
    return {for (final key in _box.keys) key as String: photoFor(key)!};
  }

  CachedAvatar? photoFor(String peerId) {
    final raw = _box.get(peerId);
    if (raw == null) return null;
    return CachedAvatar(
      bytes: raw['bytes'] as Uint8List,
      version: raw['version'] as String,
    );
  }

  Future<void> setPhoto(String peerId, Uint8List bytes, String version) {
    return _box.put(peerId, {'bytes': bytes, 'version': version});
  }

  Future<void> removePhoto(String peerId) => _box.delete(peerId);

  Future<void> clearAll({required String exceptPeerId}) async {
    for (final key in _box.keys.toList()) {
      if (key != exceptPeerId) await _box.delete(key);
    }
  }
}
