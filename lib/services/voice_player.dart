import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

abstract class VoicePlayer {
  Stream<Duration> get onPositionChanged;

  Stream<void> get onComplete;

  Future<void> playFile(String path);

  Future<void> pause();

  Future<void> setPlaybackRate(double rate);

  void dispose();
}

@visibleForTesting
VoicePlayer Function()? debugVoicePlayerFactory;

VoicePlayer createVoicePlayer() =>
    debugVoicePlayerFactory?.call() ?? AudioPlayersVoicePlayer();

class AudioPlayersVoicePlayer implements VoicePlayer {
  final _player = AudioPlayer();

  @override
  Stream<Duration> get onPositionChanged => _player.onPositionChanged;

  @override
  Stream<void> get onComplete => _player.onPlayerComplete;

  @override
  Future<void> playFile(String path) => _player.play(DeviceFileSource(path));

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> setPlaybackRate(double rate) => _player.setPlaybackRate(rate);

  @override
  void dispose() => _player.dispose();
}
