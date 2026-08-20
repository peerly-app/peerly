import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../models/chat_message.dart';
import 'audio_store.dart';
import 'avatar_store.dart';
import 'chat_repository.dart';
import 'chat_store.dart';
import 'file_store.dart';
import 'notification_service.dart';

class ChatServer {
  final ChatStore chatStore;
  final NotificationService notificationService;
  final AvatarStore avatarStore;
  final AudioStore audioStore;
  final FileStore fileStore;
  final String ownId;

  ChatServer({
    required this.chatStore,
    required this.notificationService,
    required this.avatarStore,
    required this.audioStore,
    required this.fileStore,
    required this.ownId,
  });

  HttpServer? _server;

  int get port => _server?.port ?? 0;

  Future<void> start() async {
    _server = await shelf_io.serve(_handler, InternetAddress.anyIPv4, 0);
  }

  Future<shelf.Response> _handler(shelf.Request request) async {
    if (request.method == 'GET') {
      final segments = request.url.pathSegments;
      if (segments.length == 1 && segments[0] == 'avatar') {
        return _handleAvatarGet();
      }
      if (segments.length == 2 && segments[0] == 'audio') {
        return _handleAudioGet(segments[1]);
      }
      if (segments.length == 2 && segments[0] == 'file') {
        return _handleFileGet(segments[1]);
      }
      return shelf.Response.notFound('not found');
    }
    if (request.method != 'POST') {
      return shelf.Response.notFound('not found');
    }
    switch (request.url.path) {
      case 'message':
        return _handleMessage(request);
      case 'request':
        return _handleRequest(request);
      case 'request-response':
        return _handleRequestResponse(request);
      default:
        return shelf.Response.notFound('not found');
    }
  }

  Future<shelf.Response> _handleMessage(shelf.Request request) async {
    try {
      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final message = ChatMessage.fromJson(json, isMine: false);

      if (chatStore.statusFor(message.fromId) != ConversationStatus.accepted) {
        return shelf.Response.forbidden('conversation not accepted');
      }

      final fileName = message.fileName;
      final fileSizeBytes = message.fileSizeBytes;
      if (message.kind == MessageKind.file) {
        if (fileName == null || fileSizeBytes == null) {
          return shelf.Response.badRequest(body: 'invalid payload');
        }

        await fileStore.registerIncoming(
          message.id,
          fileName: fileName,
          sizeBytes: fileSizeBytes,
        );
      }

      await chatStore.add(message.fromId, message.fromAlias, message);

      if (chatStore.currentlyViewedPeerId != message.fromId) {
        await notificationService.showMessage(
          title: message.fromAlias,
          body: message.text,
        );
      }

      return shelf.Response.ok('ok');
    } catch (_) {
      return shelf.Response.badRequest(body: 'invalid payload');
    }
  }

  Future<shelf.Response> _handleRequest(shelf.Request request) async {
    try {
      final json =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final peerId = json['id'] as String;
      final alias = json['alias'] as String;

      if (chatStore.statusFor(peerId) == ConversationStatus.blocked) {
        return shelf.Response.forbidden('blocked');
      }
      if (chatStore.statusFor(peerId) != ConversationStatus.accepted) {
        await chatStore.setStatus(
          peerId,
          alias,
          ConversationStatus.pendingIncoming,
        );
      }
      return shelf.Response.ok('ok');
    } catch (_) {
      return shelf.Response.badRequest(body: 'invalid payload');
    }
  }

  Future<shelf.Response> _handleRequestResponse(shelf.Request request) async {
    try {
      final json =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final peerId = json['id'] as String;
      final alias = json['alias'] as String;
      final accepted = json['accepted'] as bool;

      if (chatStore.statusFor(peerId) == ConversationStatus.pendingOutgoing) {
        if (accepted) {
          await chatStore.setStatus(peerId, alias, ConversationStatus.accepted);
        } else {
          await chatStore.resetRelationship(peerId);
        }
      }
      return shelf.Response.ok('ok');
    } catch (_) {
      return shelf.Response.badRequest(body: 'invalid payload');
    }
  }

  shelf.Response _handleAvatarGet() {
    final bytes = avatarStore.photoBytes(ownId);
    if (bytes == null) return shelf.Response.notFound('no avatar');
    return shelf.Response.ok(bytes, headers: {'Content-Type': 'image/jpeg'});
  }

  shelf.Response _handleAudioGet(String messageId) {
    final bytes = audioStore.bytesFor(messageId);
    if (bytes == null) return shelf.Response.notFound('no audio');
    return shelf.Response.ok(bytes, headers: {'Content-Type': 'audio/mp4'});
  }

  Future<shelf.Response> _handleFileGet(String messageId) async {
    final record = fileStore.recordFor(messageId);
    final path = record?.localPath;
    if (path == null) return shelf.Response.notFound('no file');
    final file = File(path);
    if (!await file.exists()) return shelf.Response.notFound('no file');
    return shelf.Response.ok(
      file.openRead(),
      headers: {
        'Content-Type': 'application/octet-stream',
        'Content-Length': '${await file.length()}',
        'Content-Disposition': 'attachment; filename="${record!.fileName}"',
      },
    );
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }
}
