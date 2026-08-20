import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:peero/services/file_repository.dart';

void main() {
  late Directory tempDir;
  late FileRepository repository;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('peero_file_test_');
    Hive.init(tempDir.path);
    repository = FileRepository();
    await repository.init();
  });

  tearDown(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  test('save + recordFor round-trips file metadata', () async {
    await repository.save(
      'message-1',
      fileName: 'rapport.pdf',
      sizeBytes: 1024,
      status: FileTransferStatus.pending,
    );

    final record = repository.recordFor('message-1');

    expect(record, isNotNull);
    expect(record!.fileName, 'rapport.pdf');
    expect(record.sizeBytes, 1024);
    expect(record.status, FileTransferStatus.pending);
    expect(record.localPath, isNull);
  });

  test('save can update status and set localPath once downloaded', () async {
    await repository.save(
      'message-1',
      fileName: 'photo.jpg',
      sizeBytes: 2048,
      status: FileTransferStatus.pending,
    );

    await repository.save(
      'message-1',
      fileName: 'photo.jpg',
      sizeBytes: 2048,
      status: FileTransferStatus.accepted,
      localPath: '${tempDir.path}/photo.jpg',
    );

    final record = repository.recordFor('message-1');
    expect(record!.status, FileTransferStatus.accepted);
    expect(record.localPath, '${tempDir.path}/photo.jpg');
  });

  test('recordFor returns null for an unknown message', () {
    expect(repository.recordFor('nobody'), isNull);
  });

  test('delete removes the record and the on-disk file it points to', () async {
    final filePath = '${tempDir.path}/keep-me.zip';
    await File(filePath).writeAsBytes([1, 2, 3]);
    await repository.save(
      'message-1',
      fileName: 'keep-me.zip',
      sizeBytes: 3,
      status: FileTransferStatus.accepted,
      localPath: filePath,
    );

    await repository.delete('message-1');

    expect(repository.recordFor('message-1'), isNull);
    expect(await File(filePath).exists(), isFalse);
  });

  test('delete is a no-op for a message with no downloaded file yet', () async {
    await repository.save(
      'message-1',
      fileName: 'pending.pdf',
      sizeBytes: 10,
      status: FileTransferStatus.pending,
    );

    await repository.delete('message-1');

    expect(repository.recordFor('message-1'), isNull);
  });
}
