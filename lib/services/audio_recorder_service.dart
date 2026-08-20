import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

@visibleForTesting
AudioRecorderService Function()? debugAudioRecorderFactory;

AudioRecorderService createAudioRecorder() =>
    debugAudioRecorderFactory?.call() ?? AudioRecorderService();

class AudioRecorderService {
  final _recorder = AudioRecorder();

  Future<bool> hasPermission() => _recorder.hasPermission();

  Future<void> start() async {
    final dir = await getTemporaryDirectory();

    await dir.create(recursive: true);
    final path = '${dir.path}/${const Uuid().v4()}.m4a';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: path,
    );
  }

  Future<Uint8List?> stop() async {
    final path = await _recorder.stop();
    if (path == null) return null;
    final file = File(path);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    await file.delete();
    return bytes.isEmpty ? null : bytes;
  }

  Future<void> cancel() => _recorder.cancel();

  void dispose() => _recorder.dispose();
}
