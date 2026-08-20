import 'dart:typed_data';

import 'package:hive_ce_flutter/hive_ce_flutter.dart';

class AudioRepository {
  static const _boxName = 'voice_notes';

  late final Box<Uint8List> _box;

  Future<void> init() async {
    _box = await Hive.openBox<Uint8List>(_boxName);
  }

  Uint8List? bytesFor(String messageId) => _box.get(messageId);

  Future<void> save(String messageId, Uint8List bytes) =>
      _box.put(messageId, bytes);

  Future<void> delete(String messageId) => _box.delete(messageId);
}
