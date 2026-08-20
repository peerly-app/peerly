import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:peero/models/peer.dart';
import 'package:peero/services/audio_client.dart';
import 'package:peero/services/avatar_client.dart';
import 'package:peero/services/file_client.dart';

import '../helpers/test_harness.dart';

class StubServer {
  final HttpServer server;

  StubServer(this.server);

  int statusCode = 200;
  List<int> body = const [];

  final List<String> requestedPaths = [];

  static Future<StubServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final stub = StubServer(server);
    unawaited(stub._serve());
    addTearDown(() async => server.close(force: true));
    return stub;
  }

  Future<void> _serve() async {
    await for (final request in server) {
      requestedPaths.add(request.uri.path);
      request.response.statusCode = statusCode;
      request.response.add(body);
      await request.response.close();
    }
  }

  Peer get asPeer => testPeer(ip: '127.0.0.1', port: server.port);

  Peer get deadPeer => testPeer(ip: '127.0.0.1', port: 1);
}

Future<Peer> startTruncatingServer({required int announced}) async {
  final socketServer = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(() async => socketServer.close());

  socketServer.listen((socket) {
    socket.listen(
      (_) {
        socket.add(
          'HTTP/1.1 200 OK\r\nContent-Length: $announced\r\n\r\n'.codeUnits,
        );
        socket.add(List.filled(announced ~/ 4, 1));
        socket.flush().then((_) => socket.destroy(), onError: (_) {});
      },
      onError: (_) {},
      cancelOnError: true,
    );
  });

  return testPeer(ip: '127.0.0.1', port: socketServer.port);
}

void main() {
  late StubServer stub;

  setUp(() async => stub = await StubServer.start());

  group('AvatarClient', () {
    test('returns the bytes on 200', () async {
      stub.body = [1, 2, 3];

      expect(await AvatarClient().fetch(stub.asPeer), [1, 2, 3]);
      expect(stub.requestedPaths.single, '/avatar');
    });

    test('returns null on a non-200', () async {
      stub.statusCode = 404;

      expect(await AvatarClient().fetch(stub.asPeer), isNull);
    });

    test('returns null when the peer is unreachable', () async {
      expect(await AvatarClient().fetch(stub.deadPeer), isNull);
    });
  });

  group('AudioClient', () {
    test('returns the bytes on 200', () async {
      stub.body = [4, 5, 6];

      expect(await AudioClient().fetch(stub.asPeer, 'voice-1'), [4, 5, 6]);
      expect(stub.requestedPaths.single, '/audio/voice-1');
    });

    test('returns null on a non-200', () async {
      stub.statusCode = 500;

      expect(await AudioClient().fetch(stub.asPeer, 'voice-1'), isNull);
    });

    test('returns null when the peer is unreachable', () async {
      expect(await AudioClient().fetch(stub.deadPeer, 'voice-1'), isNull);
    });
  });

  group('FileClient', () {
    late Directory tempDir;
    late String destination;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('peero_download_');
      destination = '${tempDir.path}/downloaded.bin';
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });
    });

    test('streams the file to disk and reports progress', () async {
      stub.body = List.filled(2048, 7);
      final progress = <int>[];

      final ok = await FileClient().download(
        stub.asPeer,
        'file-1',
        destination,
        onProgress: progress.add,
      );

      expect(ok, isTrue);
      expect(await File(destination).readAsBytes(), hasLength(2048));
      expect(progress, isNotEmpty);
      expect(progress.last, 2048);
      expect(stub.requestedPaths.single, '/file/file-1');
    });

    test('works without a progress callback', () async {
      stub.body = [1, 2, 3];

      expect(
        await FileClient().download(stub.asPeer, 'file-1', destination),
        isTrue,
      );
    });

    test('writes nothing on a non-200', () async {
      stub.statusCode = 404;

      final ok = await FileClient().download(
        stub.asPeer,
        'file-1',
        destination,
      );

      expect(ok, isFalse);
      expect(await File(destination).exists(), isFalse);
    });

    test(
      'leaves no partial file behind when the peer is unreachable',
      () async {
        final ok = await FileClient().download(
          stub.deadPeer,
          'file-1',
          destination,
        );

        expect(ok, isFalse);
        expect(await File(destination).exists(), isFalse);
      },
    );

    test('cleans up the partial file when the transfer is cut short', () async {
      final peer = await startTruncatingServer(announced: 4096);

      final ok = await FileClient().download(peer, 'file-1', destination);

      expect(ok, isFalse);
      expect(await File(destination).exists(), isFalse);
    });

    test('an unwritable destination fails without throwing', () async {
      stub.body = [1, 2, 3];

      final ok = await FileClient().download(
        stub.asPeer,
        'file-1',
        '${tempDir.path}/missing-dir/file.bin',
      );

      expect(ok, isFalse);
    });
  });
}
