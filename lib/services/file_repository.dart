import 'dart:io';

import 'package:hive_ce_flutter/hive_ce_flutter.dart';

enum FileTransferStatus { pending, accepted, declined }

class FileRecord {
  final String fileName;
  final int sizeBytes;
  final FileTransferStatus status;

  final String? localPath;

  FileRecord({
    required this.fileName,
    required this.sizeBytes,
    required this.status,
    this.localPath,
  });
}

class FileRepository {
  static const _boxName = 'files';

  late final Box<Map> _box;

  Future<void> init() async {
    _box = await Hive.openBox<Map>(_boxName);
  }

  FileRecord? recordFor(String messageId) {
    final raw = _box.get(messageId);
    if (raw == null) return null;
    final m = Map<String, dynamic>.from(raw);
    return FileRecord(
      fileName: m['fileName'] as String,
      sizeBytes: m['sizeBytes'] as int,
      status: FileTransferStatus.values.byName(m['status'] as String),
      localPath: m['localPath'] as String?,
    );
  }

  Future<void> save(
    String messageId, {
    required String fileName,
    required int sizeBytes,
    required FileTransferStatus status,
    String? localPath,
  }) {
    return _box.put(messageId, {
      'fileName': fileName,
      'sizeBytes': sizeBytes,
      'status': status.name,
      'localPath': localPath,
    });
  }

  Future<void> delete(String messageId) async {
    final record = recordFor(messageId);
    final path = record?.localPath;
    if (path != null) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
    await _box.delete(messageId);
  }
}
