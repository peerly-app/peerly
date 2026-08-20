import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:peero/services/avatar_store.dart';

import '../helpers/test_harness.dart';

Uint8List pngOf({required int width, required int height}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(10, 200, 210));
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  group('resizeAndEncodeAvatar', () {
    test('re-encodes as JPEG', () {
      final result = resizeAndEncodeAvatar(pngOf(width: 100, height: 100));
      expect(img.findFormatForData(result), img.ImageFormat.jpg);
    });

    test('leaves an already-small image at its original size', () {
      final decoded = img.decodeImage(
        resizeAndEncodeAvatar(pngOf(width: 100, height: 60)),
      )!;

      expect(decoded.width, 100);
      expect(decoded.height, 60);
    });

    test('caps a wide image on its width, keeping the aspect ratio', () {
      final decoded = img.decodeImage(
        resizeAndEncodeAvatar(pngOf(width: 1200, height: 600)),
      )!;

      expect(decoded.width, 480);
      expect(decoded.height, 240);
    });

    test('caps a tall image on its height instead', () {
      final decoded = img.decodeImage(
        resizeAndEncodeAvatar(pngOf(width: 600, height: 1200)),
      )!;

      expect(decoded.height, 480);
      expect(decoded.width, 240);
    });

    test('a square image at the cap is left alone', () {
      final decoded = img.decodeImage(
        resizeAndEncodeAvatar(pngOf(width: 480, height: 480)),
      )!;

      expect(decoded.width, 480);
    });

    test('rejects bytes in no recognised image format', () {
      expect(
        () => resizeAndEncodeAvatar(Uint8List(64)),
        throwsA(isA<FormatException>()),
      );
    });

    test('surfaces an error rather than a broken avatar on junk input', () {
      expect(
        () => resizeAndEncodeAvatar(Uint8List.fromList([1, 2, 3, 4])),
        throwsA(anything),
      );
    });
  });

  group('AvatarStore', () {
    late TestStores stores;

    setUp(() async => stores = await TestStores.create());
    tearDown(() async => stores.dispose());

    test('has nothing cached to begin with', () {
      expect(stores.avatarStore.photoBytes('peer-1'), isNull);
      expect(stores.avatarStore.versionFor('peer-1'), isNull);
    });

    test('load() warms the cache from disk', () async {
      await stores.avatarRepository.setPhoto(
        'peer-1',
        Uint8List.fromList([1, 2, 3]),
        'v1',
      );

      stores.avatarStore.load();

      expect(stores.avatarStore.photoBytes('peer-1'), [1, 2, 3]);
      expect(stores.avatarStore.versionFor('peer-1'), 'v1');
    });

    test('setOwnPhoto downscales, stores and stamps a version', () async {
      await stores.avatarStore.setOwnPhoto(
        'me',
        pngOf(width: 900, height: 900),
      );

      final stored = stores.avatarStore.photoBytes('me');
      expect(stored, isNotNull);
      expect(img.decodeImage(stored!)!.width, 480);
      expect(stores.avatarStore.versionFor('me'), isNotNull);
      expect(stores.avatarRepository.photoFor('me'), isNotNull);
    });

    test(
      'removeOwnPhoto clears the bytes, the version and the disk copy',
      () async {
        await stores.avatarStore.setOwnPhoto(
          'me',
          pngOf(width: 40, height: 40),
        );

        await stores.avatarStore.removeOwnPhoto('me');

        expect(stores.avatarStore.photoBytes('me'), isNull);
        expect(stores.avatarStore.versionFor('me'), isNull);
        expect(stores.avatarRepository.photoFor('me'), isNull);
      },
    );

    test(
      'removePeerPhoto also forgets the version, so it can be refetched',
      () async {
        stores.avatarClient.responses['peer-1'] = Uint8List.fromList([9]);
        stores.avatarStore.syncFromPeers([testPeer(avatarVersion: 'v1')]);
        await pumpEventQueue();

        await stores.avatarStore.removePeerPhoto('peer-1');
        expect(stores.avatarStore.versionFor('peer-1'), isNull);

        stores.avatarStore.syncFromPeers([testPeer(avatarVersion: 'v1')]);
        await pumpEventQueue();

        expect(stores.avatarStore.photoBytes('peer-1'), [9]);
      },
    );

    test(
      'clearCachedPhotos keeps our own photo and the remembered versions',
      () async {
        stores.avatarClient.responses['peer-1'] = Uint8List.fromList([9]);
        await stores.avatarStore.setOwnPhoto(
          'me',
          pngOf(width: 40, height: 40),
        );
        stores.avatarStore.syncFromPeers([testPeer(avatarVersion: 'v1')]);
        await pumpEventQueue();

        await stores.avatarStore.clearCachedPhotos(exceptPeerId: 'me');

        expect(stores.avatarStore.photoBytes('me'), isNotNull);
        expect(stores.avatarStore.photoBytes('peer-1'), isNull);

        expect(stores.avatarStore.versionFor('peer-1'), 'v1');

        stores.avatarStore.syncFromPeers([testPeer(avatarVersion: 'v1')]);
        await pumpEventQueue();
        expect(stores.avatarStore.photoBytes('peer-1'), isNull);
      },
    );

    group('syncFromPeers', () {
      test('fetches a peer photo it has never seen', () async {
        stores.avatarClient.responses['peer-1'] = Uint8List.fromList([1, 2]);

        stores.avatarStore.syncFromPeers([testPeer(avatarVersion: 'v1')]);
        await pumpEventQueue();

        expect(stores.avatarStore.photoBytes('peer-1'), [1, 2]);
        expect(stores.avatarStore.versionFor('peer-1'), 'v1');
        expect(stores.avatarRepository.photoFor('peer-1'), isNotNull);
      });

      test('ignores peers advertising no photo', () async {
        stores.avatarStore.syncFromPeers([testPeer()]);
        await pumpEventQueue();

        expect(stores.avatarClient.requestedPeerIds, isEmpty);
      });

      test('skips a peer whose advertised version we already hold', () async {
        stores.avatarClient.responses['peer-1'] = Uint8List.fromList([1]);
        stores.avatarStore.syncFromPeers([testPeer(avatarVersion: 'v1')]);
        await pumpEventQueue();

        stores.avatarStore.syncFromPeers([testPeer(avatarVersion: 'v1')]);
        await pumpEventQueue();

        expect(stores.avatarClient.requestedPeerIds, ['peer-1']);
      });

      test('refetches when the peer changes their photo', () async {
        stores.avatarClient.responses['peer-1'] = Uint8List.fromList([1]);
        stores.avatarStore.syncFromPeers([testPeer(avatarVersion: 'v1')]);
        await pumpEventQueue();

        stores.avatarClient.responses['peer-1'] = Uint8List.fromList([2]);
        stores.avatarStore.syncFromPeers([testPeer(avatarVersion: 'v2')]);
        await pumpEventQueue();

        expect(stores.avatarStore.photoBytes('peer-1'), [2]);
        expect(stores.avatarStore.versionFor('peer-1'), 'v2');
      });

      test('does not start a second fetch while one is in flight', () async {
        stores.avatarClient.responses['peer-1'] = Uint8List.fromList([1]);

        stores.avatarStore.syncFromPeers([testPeer(avatarVersion: 'v1')]);
        stores.avatarStore.syncFromPeers([testPeer(avatarVersion: 'v1')]);
        await pumpEventQueue();

        expect(stores.avatarClient.requestedPeerIds, ['peer-1']);
      });

      test('a failed fetch caches nothing and is retried next time', () async {
        stores.avatarStore.syncFromPeers([testPeer(avatarVersion: 'v1')]);
        await pumpEventQueue();

        expect(stores.avatarStore.photoBytes('peer-1'), isNull);
        expect(stores.avatarStore.versionFor('peer-1'), isNull);

        stores.avatarClient.responses['peer-1'] = Uint8List.fromList([7]);
        stores.avatarStore.syncFromPeers([testPeer(avatarVersion: 'v1')]);
        await pumpEventQueue();

        expect(stores.avatarStore.photoBytes('peer-1'), [7]);
      });

      test('handles several peers in one pass', () async {
        stores.avatarClient.responses['peer-1'] = Uint8List.fromList([1]);
        stores.avatarClient.responses['peer-2'] = Uint8List.fromList([2]);

        stores.avatarStore.syncFromPeers([
          testPeer(id: 'peer-1', avatarVersion: 'v1'),
          testPeer(id: 'peer-2', avatarVersion: 'v1'),
        ]);
        await pumpEventQueue();

        expect(stores.avatarStore.photoBytes('peer-1'), [1]);
        expect(stores.avatarStore.photoBytes('peer-2'), [2]);
      });
    });
  });
}
