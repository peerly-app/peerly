import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/chat_message.dart';
import '../models/peer.dart';

class MessageClient {
  Future<bool> send(Peer peer, ChatMessage message) =>
      _post(peer.messageUri(), message.toJson());

  Future<bool> sendRequest(
    Peer peer, {
    required String id,
    required String alias,
    required String platform,
  }) => _post(peer.requestUri(), {
    'id': id,
    'alias': alias,
    'platform': platform,
  });

  Future<bool> sendRequestResponse(
    Peer peer, {
    required String id,
    required String alias,
    required bool accepted,
  }) => _post(peer.requestResponseUri(), {
    'id': id,
    'alias': alias,
    'accepted': accepted,
  });

  Future<bool> _post(Uri uri, Map<String, dynamic> body) async {
    try {
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
