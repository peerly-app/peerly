import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:peero/models/chat_message.dart';
import 'package:peero/models/peer.dart';
import 'package:peero/services/chat_repository.dart';
import 'package:peero/services/chat_server.dart';
import 'package:peero/services/file_repository.dart';
import 'package:peero/services/message_client.dart';
import 'package:peero/services/notification_service.dart';

import '../helpers/test_harness.dart';

class RecordingNotificationService extends NotificationService {
  final List<({String title, String body})> shown = [];

  @override
  Future<void> showMessage({
    required String title,
    required String body,
  }) async {
    shown.add((title: title, body: body));
  }
}

void main() {
  late TestStores stores;
  late TestPathProvider paths;
  late RecordingNotificationService notifications;
  late ChatServer server;
  late Peer serverAsPeer;

  setUp(() async {
    paths = TestPathProvider.install();
    stores = await TestStores.create();
    notifications = RecordingNotificationService();
    server = ChatServer(
      chatStore: stores.chatStore,
      notificationService: notifications,
      avatarStore: stores.avatarStore,
      audioStore: stores.audioStore,
      fileStore: stores.fileStore,
      ownId: 'me',
    );
    await server.start();
    serverAsPeer = testPeer(ip: '127.0.0.1', port: server.port);
  });

  tearDown(() async {
    await server.stop();
    await stores.dispose();
  });

  Future<http.Response> post(String path, Object body) {
    return http.post(
      Uri.parse('http://127.0.0.1:${server.port}/$path'),
      headers: {'Content-Type': 'application/json'},
      body: body is String ? body : jsonEncode(body),
    );
  }

  Future<http.Response> get(String path) =>
      http.get(Uri.parse('http://127.0.0.1:${server.port}/$path'));

  ChatMessage incoming({
    String text = 'Salut',
    MessageKind kind = MessageKind.text,
    String? fileName,
    int? fileSizeBytes,
    String? id,
  }) {
    return ChatMessage(
      id: id,
      fromId: 'peer-1',
      fromAlias: 'Bob',
      text: text,
      timestamp: DateTime.utc(2026, 1, 1, 10),
      isMine: false,
      kind: kind,
      fileName: fileName,
      fileSizeBytes: fileSizeBytes,
    );
  }

  Future<void> acceptPeer() =>
      stores.chatStore.setStatus('peer-1', 'Bob', ConversationStatus.accepted);

  test('the server binds to a real port', () {
    expect(server.port, greaterThan(0));
  });

  group('POST /message', () {
    test('stores an accepted peer\'s message and notifies', () async {
      await acceptPeer();

      final response = await post('message', incoming().toJson());

      expect(response.statusCode, 200);
      expect(stores.chatStore.messagesFor('peer-1').single.text, 'Salut');
      expect(stores.chatStore.messagesFor('peer-1').single.isMine, isFalse);
      expect(notifications.shown.single.title, 'Bob');
      expect(notifications.shown.single.body, 'Salut');
    });

    test('stays quiet while that conversation is on screen', () async {
      await acceptPeer();
      stores.chatStore.setViewing('peer-1');

      await post('message', incoming().toJson());

      expect(notifications.shown, isEmpty);
      expect(stores.chatStore.messagesFor('peer-1'), hasLength(1));
    });

    test('refuses a message from a peer we never accepted', () async {
      final response = await post('message', incoming().toJson());

      expect(response.statusCode, 403);
      expect(stores.chatStore.messagesFor('peer-1'), isEmpty);
    });

    test('refuses a message from a blocked peer', () async {
      await stores.chatStore.setStatus(
        'peer-1',
        'Bob',
        ConversationStatus.blocked,
      );

      final response = await post('message', incoming().toJson());

      expect(response.statusCode, 403);
      expect(stores.chatStore.messagesFor('peer-1'), isEmpty);
    });

    test('refuses a message while the request is still pending', () async {
      await stores.chatStore.setStatus(
        'peer-1',
        'Bob',
        ConversationStatus.pendingIncoming,
      );

      expect((await post('message', incoming().toJson())).statusCode, 403);
    });

    test('rejects a malformed body', () async {
      final response = await post('message', 'not json at all');

      expect(response.statusCode, 400);
      expect(stores.chatStore.messagesFor('peer-1'), isEmpty);
    });

    test('rejects a payload missing required fields', () async {
      await acceptPeer();

      final response = await post('message', {'fromId': 'peer-1'});

      expect(response.statusCode, 400);
    });

    test('registers a file offer before the message lands', () async {
      await acceptPeer();

      final response = await post(
        'message',
        incoming(
          id: 'file-1',
          kind: MessageKind.file,
          fileName: 'rapport.pdf',
          fileSizeBytes: 2048,
        ).toJson(),
      );

      expect(response.statusCode, 200);
      final record = stores.fileStore.recordFor('file-1')!;
      expect(record.fileName, 'rapport.pdf');
      expect(record.sizeBytes, 2048);
      expect(record.status, FileTransferStatus.pending);
      expect(stores.chatStore.messagesFor('peer-1'), hasLength(1));
    });

    test('rejects a file offer with no metadata, storing nothing', () async {
      await acceptPeer();

      final response = await post('message', {
        ...incoming(id: 'file-1', kind: MessageKind.file).toJson(),
        'kind': MessageKind.file.name,
      });

      expect(response.statusCode, 400);

      expect(stores.chatStore.messagesFor('peer-1'), isEmpty);
      expect(stores.fileStore.recordFor('file-1'), isNull);
    });

    test('accepts a voice message', () async {
      await acceptPeer();

      final response = await post('message', {
        ...incoming(id: 'voice-1', text: '', kind: MessageKind.voice).toJson(),
        'voiceDurationMs': 3000,
      });

      expect(response.statusCode, 200);
      final message = stores.chatStore.messagesFor('peer-1').single;
      expect(message.kind, MessageKind.voice);
      expect(message.voiceDurationMs, 3000);
    });
  });

  group('POST /request', () {
    test('turns an unknown peer into a pending incoming request', () async {
      final response = await post('request', {
        'id': 'peer-1',
        'alias': 'Bob',
        'platform': 'linux',
      });

      expect(response.statusCode, 200);
      expect(
        stores.chatStore.statusFor('peer-1'),
        ConversationStatus.pendingIncoming,
      );
    });

    test(
      'refuses a request from a blocked peer and keeps them blocked',
      () async {
        await stores.chatStore.setStatus(
          'peer-1',
          'Bob',
          ConversationStatus.blocked,
        );

        final response = await post('request', {
          'id': 'peer-1',
          'alias': 'Bob',
          'platform': 'linux',
        });

        expect(response.statusCode, 403);
        expect(
          stores.chatStore.statusFor('peer-1'),
          ConversationStatus.blocked,
        );
      },
    );

    test('leaves an already-accepted conversation alone', () async {
      await acceptPeer();

      final response = await post('request', {
        'id': 'peer-1',
        'alias': 'Bob',
        'platform': 'linux',
      });

      expect(response.statusCode, 200);
      expect(stores.chatStore.statusFor('peer-1'), ConversationStatus.accepted);
    });

    test('rejects a malformed body', () async {
      expect((await post('request', {'alias': 'Bob'})).statusCode, 400);
    });
  });

  group('POST /request-response', () {
    test('accepting our outstanding request opens the conversation', () async {
      await stores.chatStore.setStatus(
        'peer-1',
        'Bob',
        ConversationStatus.pendingOutgoing,
      );

      final response = await post('request-response', {
        'id': 'peer-1',
        'alias': 'Bob',
        'accepted': true,
      });

      expect(response.statusCode, 200);
      expect(stores.chatStore.statusFor('peer-1'), ConversationStatus.accepted);
    });

    test('declining clears the relationship', () async {
      await stores.chatStore.setStatus(
        'peer-1',
        'Bob',
        ConversationStatus.pendingOutgoing,
      );

      await post('request-response', {
        'id': 'peer-1',
        'alias': 'Bob',
        'accepted': false,
      });

      expect(stores.chatStore.statusFor('peer-1'), isNull);
    });

    test('a response we never asked for is ignored', () async {
      await stores.chatStore.setStatus(
        'peer-1',
        'Bob',
        ConversationStatus.blocked,
      );

      final response = await post('request-response', {
        'id': 'peer-1',
        'alias': 'Bob',
        'accepted': true,
      });

      expect(response.statusCode, 200);
      expect(stores.chatStore.statusFor('peer-1'), ConversationStatus.blocked);
    });

    test('rejects a malformed body', () async {
      final response = await post('request-response', {
        'id': 'peer-1',
        'alias': 'Bob',
      });

      expect(response.statusCode, 400);
    });
  });

  group('GET /avatar', () {
    test('serves our own photo as JPEG', () async {
      await stores.avatarRepository.setPhoto(
        'me',
        Uint8List.fromList([1, 2, 3]),
        'v1',
      );
      stores.avatarStore.load();

      final response = await get('avatar');

      expect(response.statusCode, 200);
      expect(response.bodyBytes, [1, 2, 3]);
      expect(response.headers['content-type'], contains('image/jpeg'));
    });

    test('404s when we have no photo', () async {
      expect((await get('avatar')).statusCode, 404);
    });

    test('never serves a peer\'s cached photo as our own', () async {
      await stores.avatarRepository.setPhoto(
        'peer-1',
        Uint8List.fromList([9]),
        'v1',
      );
      stores.avatarStore.load();

      expect((await get('avatar')).statusCode, 404);
    });
  });

  group('GET /audio/<id>', () {
    test('serves a stored voice clip', () async {
      await stores.audioStore.saveOwnRecording(
        'voice-1',
        Uint8List.fromList([4, 5, 6]),
      );

      final response = await get('audio/voice-1');

      expect(response.statusCode, 200);
      expect(response.bodyBytes, [4, 5, 6]);
      expect(response.headers['content-type'], contains('audio/mp4'));
    });

    test('404s for an unknown clip', () async {
      expect((await get('audio/nope')).statusCode, 404);
    });
  });

  group('GET /file/<id>', () {
    Future<void> registerOwnFile(String id, List<int> bytes) async {
      final source = File('${paths.root.path}/source-$id.pdf');
      await source.parent.create(recursive: true);
      await source.writeAsBytes(bytes);
      await stores.fileStore.registerOwnFile(
        id,
        sourcePath: source.path,
        fileName: 'rapport.pdf',
        sizeBytes: bytes.length,
      );
    }

    test('streams the file with its length and filename', () async {
      await registerOwnFile('file-1', [1, 2, 3, 4, 5]);

      final response = await get('file/file-1');

      expect(response.statusCode, 200);
      expect(response.bodyBytes, [1, 2, 3, 4, 5]);
      expect(response.headers['content-length'], '5');
      expect(
        response.headers['content-disposition'],
        contains('filename="rapport.pdf"'),
      );
    });

    test('404s for an unknown message', () async {
      expect((await get('file/nope')).statusCode, 404);
    });

    test('404s for an offer that has no local copy yet', () async {
      await stores.fileStore.registerIncoming(
        'pending-1',
        fileName: 'rapport.pdf',
        sizeBytes: 10,
      );

      expect((await get('file/pending-1')).statusCode, 404);
    });

    test('404s when the record points at a file that is gone', () async {
      await registerOwnFile('file-1', [1, 2, 3]);
      await File(stores.fileStore.recordFor('file-1')!.localPath!).delete();

      expect((await get('file/file-1')).statusCode, 404);
    });
  });

  group('routing', () {
    test('404s unknown paths on every verb it handles', () async {
      expect((await get('nope')).statusCode, 404);
      expect((await get('audio')).statusCode, 404);
      expect((await get('a/b/c')).statusCode, 404);
      expect((await post('nope', {})).statusCode, 404);
    });

    test('404s methods other than GET and POST', () async {
      final response = await http.delete(
        Uri.parse('http://127.0.0.1:${server.port}/message'),
      );

      expect(response.statusCode, 404);
    });
  });

  group('via MessageClient', () {
    test('a full send/receive round trip over the real client', () async {
      await acceptPeer();
      final client = MessageClient();
      final message = ChatMessage(
        fromId: 'peer-1',
        fromAlias: 'Bob',
        text: 'Par le vrai client',
        timestamp: DateTime.utc(2026, 1, 1),
        isMine: true,
      );

      final ok = await client.send(serverAsPeer, message);

      expect(ok, isTrue);
      expect(
        stores.chatStore.messagesFor('peer-1').single.text,
        'Par le vrai client',
      );
    });

    test('the request handshake round trips', () async {
      final client = MessageClient();

      final requested = await client.sendRequest(
        serverAsPeer,
        id: 'peer-1',
        alias: 'Bob',
        platform: 'linux',
      );

      expect(requested, isTrue);
      expect(
        stores.chatStore.statusFor('peer-1'),
        ConversationStatus.pendingIncoming,
      );
    });

    test('the request response round trips', () async {
      await stores.chatStore.setStatus(
        'peer-1',
        'Bob',
        ConversationStatus.pendingOutgoing,
      );
      final client = MessageClient();

      final sent = await client.sendRequestResponse(
        serverAsPeer,
        id: 'peer-1',
        alias: 'Bob',
        accepted: true,
      );

      expect(sent, isTrue);
      expect(stores.chatStore.statusFor('peer-1'), ConversationStatus.accepted);
    });

    test('reports failure when the conversation is refused', () async {
      final client = MessageClient();
      final message = ChatMessage(
        fromId: 'peer-1',
        fromAlias: 'Bob',
        text: 'Salut',
        timestamp: DateTime.utc(2026, 1, 1),
        isMine: true,
      );

      expect(await client.send(serverAsPeer, message), isFalse);
    });

    test('reports failure when nobody is listening', () async {
      await server.stop();
      final client = MessageClient();

      final ok = await client.sendRequest(
        serverAsPeer,
        id: 'peer-1',
        alias: 'Bob',
        platform: 'linux',
      );

      expect(ok, isFalse);
    });
  });

  group('stop', () {
    test('releases the port', () async {
      final port = server.port;
      await server.stop();

      await expectLater(
        http.get(Uri.parse('http://127.0.0.1:$port/avatar')),
        throwsA(anyOf(isA<http.ClientException>(), isA<SocketException>())),
      );
    });

    test('can be called twice', () async {
      await server.stop();
      await server.stop();

      expect(server.port, 0);
    });
  });
}
