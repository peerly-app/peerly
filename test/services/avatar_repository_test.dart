import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:peero/services/avatar_repository.dart';

void main() {
  late Directory tempDir;
  late AvatarRepository repository;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('peero_avatar_test_');
    Hive.init(tempDir.path);
    repository = AvatarRepository();
    await repository.init();
  });

  tearDown(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  test('setPhoto + photoFor round-trips bytes and version', () async {
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    await repository.setPhoto('peer-1', bytes, 'v1');

    final cached = repository.photoFor('peer-1');

    expect(cached, isNotNull);
    expect(cached!.bytes, bytes);
    expect(cached.version, 'v1');
  });

  test('photoFor returns null for an unknown peer', () {
    expect(repository.photoFor('nobody'), isNull);
  });

  test('removePhoto deletes just that peer', () async {
    await repository.setPhoto('peer-1', Uint8List.fromList([1]), 'v1');
    await repository.setPhoto('peer-2', Uint8List.fromList([2]), 'v1');

    await repository.removePhoto('peer-1');

    expect(repository.photoFor('peer-1'), isNull);
    expect(repository.photoFor('peer-2'), isNotNull);
  });

  test('clearAll removes every photo except exceptPeerId', () async {
    await repository.setPhoto('me', Uint8List.fromList([0]), 'v1');
    await repository.setPhoto('peer-1', Uint8List.fromList([1]), 'v1');
    await repository.setPhoto('peer-2', Uint8List.fromList([2]), 'v1');

    await repository.clearAll(exceptPeerId: 'me');

    expect(repository.photoFor('me'), isNotNull);
    expect(repository.photoFor('peer-1'), isNull);
    expect(repository.photoFor('peer-2'), isNull);
  });

  test('all returns every cached entry keyed by peer id', () async {
    await repository.setPhoto('peer-1', Uint8List.fromList([1]), 'v1');
    await repository.setPhoto('peer-2', Uint8List.fromList([2]), 'v2');

    final all = repository.all();

    expect(all.keys, containsAll(['peer-1', 'peer-2']));
    expect(all['peer-1']!.version, 'v1');
  });
}
