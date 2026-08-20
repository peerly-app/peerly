import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_harness.dart';

void main() {
  late TestStores stores;

  setUp(() async => stores = await TestStores.create());
  tearDown(() async => stores.dispose());

  group('bytesFor', () {
    test('is null for a message we have no audio for', () {
      expect(stores.audioStore.bytesFor('nobody'), isNull);
    });

    test('falls back to disk and caches the result', () async {
      await stores.audioRepository.save('m1', Uint8List.fromList([1, 2, 3]));

      expect(stores.audioStore.bytesFor('m1'), [1, 2, 3]);

      await stores.audioRepository.delete('m1');
      expect(stores.audioStore.bytesFor('m1'), [1, 2, 3]);
    });
  });

  test('saveOwnRecording persists and caches the clip', () async {
    await stores.audioStore.saveOwnRecording('m1', Uint8List.fromList([4, 5]));

    expect(stores.audioStore.bytesFor('m1'), [4, 5]);
    expect(stores.audioRepository.bytesFor('m1'), [4, 5]);
  });

  group('ensureFetched', () {
    test('downloads and stores audio we do not have', () async {
      stores.audioClient.responses['m1'] = Uint8List.fromList([7, 8]);

      await stores.audioStore.ensureFetched('m1', testPeer());

      expect(stores.audioStore.bytesFor('m1'), [7, 8]);
      expect(stores.audioRepository.bytesFor('m1'), [7, 8]);
    });

    test('does nothing when the clip is already cached', () async {
      await stores.audioStore.saveOwnRecording('m1', Uint8List.fromList([1]));

      await stores.audioStore.ensureFetched('m1', testPeer());

      expect(stores.audioClient.requestedMessageIds, isEmpty);
    });

    test('does not start a second fetch while one is in flight', () async {
      stores.audioClient.responses['m1'] = Uint8List.fromList([1]);

      await Future.wait([
        stores.audioStore.ensureFetched('m1', testPeer()),
        stores.audioStore.ensureFetched('m1', testPeer()),
      ]);

      expect(stores.audioClient.requestedMessageIds, ['m1']);
    });

    test('a failed fetch caches nothing and can be retried', () async {
      await stores.audioStore.ensureFetched('m1', testPeer());
      expect(stores.audioStore.bytesFor('m1'), isNull);

      stores.audioClient.responses['m1'] = Uint8List.fromList([9]);
      await stores.audioStore.ensureFetched('m1', testPeer());

      expect(stores.audioStore.bytesFor('m1'), [9]);
    });

    test('notifies listeners once the audio has arrived', () async {
      stores.audioClient.responses['m1'] = Uint8List.fromList([1]);
      var notifications = 0;
      stores.audioStore.addListener(() => notifications++);

      await stores.audioStore.ensureFetched('m1', testPeer());

      expect(notifications, 1);
    });
  });

  group('deleteMessages', () {
    test('purges the listed clips from memory and disk', () async {
      await stores.audioStore.saveOwnRecording('m1', Uint8List.fromList([1]));
      await stores.audioStore.saveOwnRecording('m2', Uint8List.fromList([2]));

      await stores.audioStore.deleteMessages(['m1']);

      expect(stores.audioStore.bytesFor('m1'), isNull);
      expect(stores.audioRepository.bytesFor('m1'), isNull);
      expect(stores.audioStore.bytesFor('m2'), [2]);
    });

    test('tolerates ids it knows nothing about', () async {
      await stores.audioStore.deleteMessages(['ghost']);
      expect(stores.audioStore.bytesFor('ghost'), isNull);
    });
  });
}
