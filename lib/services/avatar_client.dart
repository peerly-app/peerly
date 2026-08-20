import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/peer.dart';

class AvatarClient {
  Future<Uint8List?> fetch(Peer peer) async {
    try {
      final response = await http
          .get(peer.avatarUri())
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200 ? response.bodyBytes : null;
    } catch (_) {
      return null;
    }
  }
}
