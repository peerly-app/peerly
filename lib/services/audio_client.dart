import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/peer.dart';

class AudioClient {
  Future<Uint8List?> fetch(Peer peer, String messageId) async {
    try {
      final response = await http
          .get(peer.audioUri(messageId))
          .timeout(const Duration(seconds: 10));
      return response.statusCode == 200 ? response.bodyBytes : null;
    } catch (_) {
      return null;
    }
  }
}
