import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:peero/services/file_repository.dart';

import '../helpers/test_harness.dart';

void main() {
  late TestStores stores;
  late TestPathProvider paths;

  setUp(() async {
    paths = TestPathProvider.install();
    stores = await TestStores.create();
  });
  tearDown(() async => stores.dispose());

  Future<String> writeSourceFile(String name, List<int> bytes) async {
    final file = File('${paths.root.path}/$name');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
    return file.path;
  }

  group('recordFor', () {
    test('is null for an unknown message', () {
      expect(stores.fileStore.recordFor('nobody'), isNull);
    });

    test('falls back to disk and caches the result', () async {
      await stores.fileRepository.save(
        'm1',
        fileName: 'rapport.pdf',
        sizeBytes: 10,
        status: FileTransferStatus.pending,
      );

      expect(stores.fileStore.recordFor('m1')!.fileName, 'rapport.pdf');
    });
  });

  group('registerOwnFile', () {
    test('copies the file into app storage and marks it accepted', () async {
      final source = await writeSourceFile('source.pdf', [1, 2, 3]);

      await stores.fileStore.registerOwnFile(
        'm1',
        sourcePath: source,
        fileName: 'rapport.pdf',
        sizeBytes: 3,
      );

      final record = stores.fileStore.recordFor('m1')!;
      expect(record.status, FileTransferStatus.accepted);
      expect(record.fileName, 'rapport.pdf');
      expect(await File(record.localPath!).readAsBytes(), [1, 2, 3]);

      expect(record.localPath, isNot(source));
    });

    test('keeps the copy when the original is deleted', () async {
      final source = await writeSourceFile('source.pdf', [1, 2, 3]);
      await stores.fileStore.registerOwnFile(
        'm1',
        sourcePath: source,
        fileName: 'rapport.pdf',
        sizeBytes: 3,
      );

      await File(source).delete();

      final record = stores.fileStore.recordFor('m1')!;
      expect(await File(record.localPath!).exists(), isTrue);
    });

    test('does not clobber an earlier file of the same name', () async {
      final first = await writeSourceFile('a.pdf', [1]);
      final second = await writeSourceFile('b.pdf', [2]);

      await stores.fileStore.registerOwnFile(
        'm1',
        sourcePath: first,
        fileName: 'rapport.pdf',
        sizeBytes: 1,
      );
      final firstPath = stores.fileStore.recordFor('m1')!.localPath!;

      await stores.fileStore.registerOwnFile(
        'm1',
        sourcePath: second,
        fileName: 'rapport.pdf',
        sizeBytes: 1,
      );
      final secondPath = stores.fileStore.recordFor('m1')!.localPath!;

      expect(secondPath, isNot(firstPath));
      expect(secondPath, contains('(1)'));
      expect(await File(firstPath).readAsBytes(), [1]);
      expect(await File(secondPath).readAsBytes(), [2]);
    });
  });

  group('registerIncoming', () {
    test('records the offer as pending without downloading anything', () async {
      await stores.fileStore.registerIncoming(
        'm1',
        fileName: 'rapport.pdf',
        sizeBytes: 2048,
      );

      final record = stores.fileStore.recordFor('m1')!;
      expect(record.status, FileTransferStatus.pending);
      expect(record.sizeBytes, 2048);
      expect(record.localPath, isNull);
      expect(stores.fileClient.requestedMessageIds, isEmpty);
    });
  });

  group('decline', () {
    test('marks the offer declined without contacting the sender', () async {
      await stores.fileStore.registerIncoming(
        'm1',
        fileName: 'rapport.pdf',
        sizeBytes: 10,
      );

      await stores.fileStore.decline('m1');

      expect(
        stores.fileStore.recordFor('m1')!.status,
        FileTransferStatus.declined,
      );
      expect(stores.fileClient.requestedMessageIds, isEmpty);
    });

    test('is a no-op for an unknown message', () async {
      await stores.fileStore.decline('nobody');
      expect(stores.fileStore.recordFor('nobody'), isNull);
    });
  });

  group('accept', () {
    setUp(() async {
      await stores.fileStore.registerIncoming(
        'm1',
        fileName: 'rapport.pdf',
        sizeBytes: 4,
      );
    });

    test('downloads the file and marks it accepted', () async {
      stores.fileClient.responses['m1'] = [1, 2, 3, 4];

      await stores.fileStore.accept('m1', testPeer());

      final record = stores.fileStore.recordFor('m1')!;
      expect(record.status, FileTransferStatus.accepted);
      expect(await File(record.localPath!).readAsBytes(), [1, 2, 3, 4]);
      expect(
        stores.fileRepository.recordFor('m1')!.localPath,
        record.localPath,
      );
    });

    test('stays pending on failure so the user can retry', () async {
      await stores.fileStore.accept('m1', testPeer());

      expect(
        stores.fileStore.recordFor('m1')!.status,
        FileTransferStatus.pending,
      );
      expect(stores.fileStore.progressFor('m1'), isNull);

      stores.fileClient.responses['m1'] = [1, 2, 3, 4];
      await stores.fileStore.accept('m1', testPeer());

      expect(
        stores.fileStore.recordFor('m1')!.status,
        FileTransferStatus.accepted,
      );
    });

    test('clears the progress indicator once the transfer ends', () async {
      stores.fileClient.responses['m1'] = [1, 2, 3, 4];

      await stores.fileStore.accept('m1', testPeer());

      expect(stores.fileStore.progressFor('m1'), isNull);
    });

    test('refuses to re-download an already accepted file', () async {
      stores.fileClient.responses['m1'] = [1, 2, 3, 4];
      await stores.fileStore.accept('m1', testPeer());

      await stores.fileStore.accept('m1', testPeer());

      expect(stores.fileClient.requestedMessageIds, ['m1']);
    });

    test('is a no-op for an unknown message', () async {
      await stores.fileStore.accept('nobody', testPeer());
      expect(stores.fileClient.requestedMessageIds, isEmpty);
    });

    test('a double tap does not start a second download', () async {
      stores.fileClient.responses['m1'] = [1, 2, 3, 4];
      stores.fileClient.gate = Completer<void>();

      final first = stores.fileStore.accept('m1', testPeer());
      final second = stores.fileStore.accept('m1', testPeer());
      stores.fileClient.gate!.complete();
      await Future.wait([first, second]);

      expect(stores.fileClient.requestedMessageIds, ['m1']);
      final received = Directory(
        '${paths.root.path}/support/received_files',
      ).listSync();
      expect(received, hasLength(1));
    });

    test('only repaints when the progress bar has visibly moved', () async {
      await stores.fileStore.registerIncoming(
        'big',
        fileName: 'film.mp4',
        sizeBytes: 1000,
      );
      stores.fileClient.responses['big'] = List.filled(1000, 0);
      stores.fileClient.progressUpdates['big'] = [
        for (var i = 1; i <= 1000; i++) i,
      ];
      var notifications = 0;
      stores.fileStore.addListener(() => notifications++);

      await stores.fileStore.accept('big', testPeer());

      expect(notifications, lessThan(150));
      expect(notifications, greaterThan(50));
    });

    test('reports full progress immediately for a zero-byte file', () async {
      await stores.fileStore.registerIncoming(
        'empty',
        fileName: 'vide.txt',
        sizeBytes: 0,
      );
      stores.fileClient.responses['empty'] = [];
      final seen = <double>[];
      stores.fileStore.addListener(() {
        final value = stores.fileStore.progressFor('empty');
        if (value != null) seen.add(value);
      });

      await stores.fileStore.accept('empty', testPeer());

      expect(seen, isNotEmpty);
      expect(seen.last, 1.0);
    });
  });

  group('deleteMessages', () {
    test('removes the records and their files on disk', () async {
      final source = await writeSourceFile('source.pdf', [1, 2, 3]);
      await stores.fileStore.registerOwnFile(
        'm1',
        sourcePath: source,
        fileName: 'rapport.pdf',
        sizeBytes: 3,
      );
      final localPath = stores.fileStore.recordFor('m1')!.localPath!;

      await stores.fileStore.deleteMessages(['m1']);

      expect(stores.fileStore.recordFor('m1'), isNull);
      expect(await File(localPath).exists(), isFalse);
    });

    test('tolerates ids it knows nothing about', () async {
      await stores.fileStore.deleteMessages(['ghost']);
      expect(stores.fileStore.recordFor('ghost'), isNull);
    });
  });

  group('storageBytesUsed', () {
    test('is zero before anything has been transferred', () async {
      expect(await stores.fileStore.storageBytesUsed(), 0);
    });

    test('counts both the files we sent and the ones we downloaded', () async {
      final source = await writeSourceFile('source.pdf', List.filled(500, 1));
      await stores.fileStore.registerOwnFile(
        'sent',
        sourcePath: source,
        fileName: 'rapport.pdf',
        sizeBytes: 500,
      );
      final afterSending = await stores.fileStore.storageBytesUsed();
      expect(afterSending, 500);

      await stores.fileStore.registerIncoming(
        'received',
        fileName: 'photo.png',
        sizeBytes: 300,
      );
      stores.fileClient.responses['received'] = List.filled(300, 2);
      await stores.fileStore.accept('received', testPeer());

      expect(await stores.fileStore.storageBytesUsed(), 800);
    });

    test('drops back down once the files are deleted', () async {
      final source = await writeSourceFile('source.pdf', List.filled(500, 1));
      await stores.fileStore.registerOwnFile(
        'sent',
        sourcePath: source,
        fileName: 'rapport.pdf',
        sizeBytes: 500,
      );

      await stores.fileStore.deleteMessages(['sent']);

      expect(await stores.fileStore.storageBytesUsed(), 0);
    });

    test('the store total includes transferred files, not just Hive', () async {
      final hiveOnly = await stores.chatStore.storageBytesUsed();

      final source = await writeSourceFile('big.bin', List.filled(4096, 7));
      await stores.fileStore.registerOwnFile(
        'sent',
        sourcePath: source,
        fileName: 'big.bin',
        sizeBytes: 4096,
      );

      expect(
        await stores.chatStore.storageBytesUsed(),
        greaterThanOrEqualTo(hiveOnly + 4096),
      );
    });
  });

  group('suggestedSaveDirectoryPath', () {
    test('is the real Downloads folder where the platform has one', () async {
      final path = await stores.fileStore.suggestedSaveDirectoryPath();

      expect(path, endsWith('downloads'));
      expect(await Directory(path).exists(), isTrue);
    });

    test(
      'falls back to documents where there is no Downloads folder',
      () async {
        paths.downloadsSupported = false;

        final path = await stores.fileStore.suggestedSaveDirectoryPath();

        expect(path, endsWith('documents'));
        expect(await Directory(path).exists(), isTrue);
      },
    );

    test('falls back to documents when the platform throws', () async {
      paths.downloadsThrows = true;

      final path = await stores.fileStore.suggestedSaveDirectoryPath();

      expect(path, endsWith('documents'));
    });
  });
}
