import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/peer.dart';

const _idleTimeout = Duration(seconds: 30);

class FileClient {
  Future<bool> download(
    Peer peer,
    String messageId,
    String destinationPath, {
    void Function(int receivedBytes)? onProgress,
  }) async {
    final client = http.Client();
    final destination = File(destinationPath);
    try {
      final request = http.Request('GET', peer.fileUri(messageId));
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return false;

      final sink = destination.openWrite();
      var received = 0;
      try {
        await for (final chunk in response.stream.timeout(_idleTimeout)) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received);
        }
      } finally {
        await sink.close();
      }
      return true;
    } catch (_) {
      await _deleteQuietly(destination);
      return false;
    } finally {
      client.close();
    }
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
