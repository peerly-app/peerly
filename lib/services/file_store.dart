import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/peer.dart';
import 'file_client.dart';
import 'file_repository.dart';

class FileStore extends ChangeNotifier {
  final FileRepository repository;
  final FileClient _client;

  final Map<String, FileRecord> _records = {};

  final Map<String, double> _downloadProgress = {};

  FileStore({required this.repository, FileClient? client})
    : _client = client ?? FileClient();

  FileRecord? recordFor(String messageId) {
    final cached = _records[messageId];
    if (cached != null) return cached;
    final stored = repository.recordFor(messageId);
    if (stored != null) _records[messageId] = stored;
    return stored;
  }

  double? progressFor(String messageId) => _downloadProgress[messageId];

  Future<void> registerOwnFile(
    String messageId, {
    required String sourcePath,
    required String fileName,
    required int sizeBytes,
  }) async {
    final sentDir = await _sentFilesDirectory();
    final destinationPath = await _uniquePath(
      sentDir,
      '${messageId}_$fileName',
    );
    await File(sourcePath).copy(destinationPath);

    await repository.save(
      messageId,
      fileName: fileName,
      sizeBytes: sizeBytes,
      status: FileTransferStatus.accepted,
      localPath: destinationPath,
    );
    _records[messageId] = FileRecord(
      fileName: fileName,
      sizeBytes: sizeBytes,
      status: FileTransferStatus.accepted,
      localPath: destinationPath,
    );
    notifyListeners();
  }

  Future<void> registerIncoming(
    String messageId, {
    required String fileName,
    required int sizeBytes,
  }) async {
    await repository.save(
      messageId,
      fileName: fileName,
      sizeBytes: sizeBytes,
      status: FileTransferStatus.pending,
    );
    _records[messageId] = FileRecord(
      fileName: fileName,
      sizeBytes: sizeBytes,
      status: FileTransferStatus.pending,
    );
    notifyListeners();
  }

  Future<void> decline(String messageId) async {
    final record = recordFor(messageId);
    if (record == null) return;
    await repository.save(
      messageId,
      fileName: record.fileName,
      sizeBytes: record.sizeBytes,
      status: FileTransferStatus.declined,
    );
    _records[messageId] = FileRecord(
      fileName: record.fileName,
      sizeBytes: record.sizeBytes,
      status: FileTransferStatus.declined,
    );
    notifyListeners();
  }

  Future<String> suggestedSaveDirectoryPath() async =>
      (await _downloadsDirectory()).path;

  Future<bool> accept(String messageId, Peer peer) async {
    final record = recordFor(messageId);
    if (record == null || record.status != FileTransferStatus.pending) {
      return false;
    }

    if (_downloadProgress.containsKey(messageId)) return false;
    _downloadProgress[messageId] = 0;
    notifyListeners();

    final dir = await _receivedFilesDirectory();
    final destinationPath = await _uniquePath(
      dir,
      '${messageId}_${record.fileName}',
    );

    final ok = await _client.download(
      peer,
      messageId,
      destinationPath,
      onProgress: (received) {
        final value = record.sizeBytes == 0
            ? 1.0
            : (received / record.sizeBytes).clamp(0.0, 1.0);

        if (value < 1 && value - (_downloadProgress[messageId] ?? 0) < 0.01) {
          return;
        }
        _downloadProgress[messageId] = value;
        notifyListeners();
      },
    );
    _downloadProgress.remove(messageId);

    if (!ok) {
      notifyListeners();
      return false;
    }
    await repository.save(
      messageId,
      fileName: record.fileName,
      sizeBytes: record.sizeBytes,
      status: FileTransferStatus.accepted,
      localPath: destinationPath,
    );
    _records[messageId] = FileRecord(
      fileName: record.fileName,
      sizeBytes: record.sizeBytes,
      status: FileTransferStatus.accepted,
      localPath: destinationPath,
    );
    notifyListeners();
    return true;
  }

  Future<void> deleteMessages(Iterable<String> messageIds) async {
    if (messageIds.isEmpty) return;
    for (final id in messageIds) {
      await repository.delete(id);
      _records.remove(id);
    }
    notifyListeners();
  }

  Future<Directory> _sentFilesDirectory() => _supportSubdirectory('sent_files');

  Future<Directory> _receivedFilesDirectory() =>
      _supportSubdirectory('received_files');

  Future<Directory> _supportSubdirectory(String name) async {
    final supportDir = await getApplicationSupportDirectory();
    final dir = Directory('${supportDir.path}/$name');
    await dir.create(recursive: true);
    return dir;
  }

  Future<int> storageBytesUsed() async {
    var total = 0;
    for (final dir in [
      await _sentFilesDirectory(),
      await _receivedFilesDirectory(),
    ]) {
      await for (final entity in dir.list()) {
        if (entity is File) total += await entity.length();
      }
    }
    return total;
  }

  Future<Directory> _downloadsDirectory() async {
    try {
      final dir = await getDownloadsDirectory();
      if (dir != null) {
        await dir.create(recursive: true);
        return dir;
      }
    } catch (_) {}
    final fallback = await getApplicationDocumentsDirectory();
    await fallback.create(recursive: true);
    return fallback;
  }

  Future<String> _uniquePath(Directory dir, String fileName) async {
    var candidate = '${dir.path}/$fileName';
    if (!await File(candidate).exists()) return candidate;

    final dotIndex = fileName.lastIndexOf('.');
    final base = dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName;
    final ext = dotIndex > 0 ? fileName.substring(dotIndex) : '';
    var counter = 1;
    while (true) {
      candidate = '${dir.path}/$base ($counter)$ext';
      if (!await File(candidate).exists()) return candidate;
      counter++;
    }
  }
}
