import 'package:flutter_test/flutter_test.dart';
import 'package:peero/services/audio_recorder_service.dart';
import 'package:peero/services/voice_player.dart';

import '../helpers/test_harness.dart';

void main() {
  tearDown(() {
    debugAudioRecorderFactory = null;
    debugVoicePlayerFactory = null;
  });

  test('createAudioRecorder returns the override when one is installed', () {
    final fake = FakeAudioRecorder();
    debugAudioRecorderFactory = () => fake;

    expect(createAudioRecorder(), same(fake));
  });

  test('createVoicePlayer returns the override when one is installed', () {
    final fake = FakeVoicePlayer();
    debugVoicePlayerFactory = () => fake;

    expect(createVoicePlayer(), same(fake));
  });

  test(
    'the overrides are null by default, so production gets the real ones',
    () {
      expect(debugAudioRecorderFactory, isNull);
      expect(debugVoicePlayerFactory, isNull);
    },
  );
}
