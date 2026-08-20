import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:peero/services/audio_repository.dart';

void main() {
  late Directory tempDir;
  late AudioRepository repository;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('peero_audio_test_');
    Hive.init(tempDir.path);
    repository = AudioRepository();
    await repository.init();
  });

  tearDown(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  test('save + bytesFor round-trips audio bytes', () async {
    final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
    await repository.save('message-1', bytes);

    expect(repository.bytesFor('message-1'), bytes);
  });

  test('bytesFor returns null for an unknown message', () {
    expect(repository.bytesFor('nobody'), isNull);
  });

  test('delete removes just that message', () async {
    await repository.save('message-1', Uint8List.fromList([1]));
    await repository.save('message-2', Uint8List.fromList([2]));

    await repository.delete('message-1');

    expect(repository.bytesFor('message-1'), isNull);
    expect(repository.bytesFor('message-2'), isNotNull);
  });
}
