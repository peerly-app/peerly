import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peero/design/colors.dart';
import 'package:peero/models/chat_message.dart';
import 'package:peero/services/voice_player.dart';
import 'package:peero/widgets/message_bubble.dart';

import '../helpers/test_harness.dart';

ChatMessage textMessage({bool isMine = false, String text = 'Salut'}) =>
    ChatMessage(
      id: 'text-1',
      fromId: isMine ? 'me' : 'peer-1',
      fromAlias: 'Bob',
      text: text,
      timestamp: DateTime(2026, 1, 1, 10),
      isMine: isMine,
    );

ChatMessage voiceMessage({bool isMine = false, int? durationMs = 5000}) =>
    ChatMessage(
      id: 'voice-1',
      fromId: isMine ? 'me' : 'peer-1',
      fromAlias: 'Bob',
      text: '',
      timestamp: DateTime(2026, 1, 1, 10),
      isMine: isMine,
      kind: MessageKind.voice,
      voiceDurationMs: durationMs,
    );

ChatMessage fileMessage({
  bool isMine = false,
  String fileName = 'rapport.pdf',
  int sizeBytes = 2048,
}) => ChatMessage(
  id: 'file-1',
  fromId: isMine ? 'me' : 'peer-1',
  fromAlias: 'Bob',
  text: '',
  timestamp: DateTime(2026, 1, 1, 10),
  isMine: isMine,
  kind: MessageKind.file,
  fileName: fileName,
  fileSizeBytes: sizeBytes,
);

void main() {
  late TestStores stores;
  late FakeDiscoveryService discovery;
  late FakeVoicePlayer player;

  setUp(() {
    stores = TestStores.inMemory();
    discovery = FakeDiscoveryService();
    player = FakeVoicePlayer();
    debugVoicePlayerFactory = () => player;
  });

  tearDown(() async {
    debugVoicePlayerFactory = null;
    await stores.dispose();
  });

  Future<void> pumpBubble(WidgetTester tester, ChatMessage message) {
    return tester.pumpWidget(
      wrapWithApp(
        Scaffold(body: MessageBubble(message: message)),
        stores: stores,
        discovery: discovery,
      ),
    );
  }

  BoxDecoration decorationOf(WidgetTester tester, Type bubbleType) {
    return tester
            .widgetList<Container>(
              find.descendant(
                of: find.byType(bubbleType),
                matching: find.byType(Container),
              ),
            )
            .firstWhere((c) => c.decoration is BoxDecoration)
            .decoration!
        as BoxDecoration;
  }

  group('text bubble', () {
    testWidgets('shows the text and is selectable', (tester) async {
      await pumpBubble(tester, textMessage(text: 'Bonjour à tous'));

      expect(find.text('Bonjour à tous'), findsOneWidget);
      expect(find.byType(SelectableText), findsOneWidget);
    });

    testWidgets('mine is accent-coloured and right-aligned', (tester) async {
      await pumpBubble(tester, textMessage(isMine: true));

      expect(decorationOf(tester, MessageBubble).color, AppColors.accent);
      expect(
        tester.widget<Align>(find.byType(Align).first).alignment,
        Alignment.centerRight,
      );
    });

    testWidgets('theirs is panel-coloured and left-aligned', (tester) async {
      await pumpBubble(tester, textMessage());

      expect(decorationOf(tester, MessageBubble).color, AppColors.panel2);
      expect(
        tester.widget<Align>(find.byType(Align).first).alignment,
        Alignment.centerLeft,
      );
    });
  });

  group('voice bubble', () {
    testWidgets('routes voice messages to the voice bubble', (tester) async {
      await pumpBubble(tester, voiceMessage(isMine: true));

      expect(find.byType(VoiceMessageBubble), findsOneWidget);
    });

    testWidgets('shows the known duration before any audio is loaded', (
      tester,
    ) async {
      await pumpBubble(tester, voiceMessage(isMine: true));

      expect(find.text('0:05'), findsOneWidget);
    });

    testWidgets('waits with an hourglass until the audio arrives', (
      tester,
    ) async {
      await pumpBubble(tester, voiceMessage(isMine: true));

      expect(find.byIcon(Icons.hourglass_empty), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow), findsNothing);
    });

    testWidgets('offers play once the clip is cached', (tester) async {
      await stores.audioStore.saveOwnRecording(
        'voice-1',
        Uint8List.fromList([1, 2, 3]),
      );

      await pumpBubble(tester, voiceMessage(isMine: true));

      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    });

    testWidgets('fetches a received clip from the sender', (tester) async {
      stores.audioClient.responses['voice-1'] = Uint8List.fromList([1]);
      discovery.setPeers([testPeer(id: 'peer-1')]);

      await pumpBubble(tester, voiceMessage());
      await settleRealWork(tester);

      expect(stores.audioClient.requestedMessageIds, ['voice-1']);
    });

    testWidgets('does not fetch when the sender is not on the network', (
      tester,
    ) async {
      discovery.setPeers([testPeer(id: 'someone-else')]);

      await pumpBubble(tester, voiceMessage());
      await tester.pump();

      expect(stores.audioClient.requestedMessageIds, isEmpty);
    });

    testWidgets('does not fetch our own recordings', (tester) async {
      discovery.setPeers([testPeer(id: 'peer-1')]);

      await pumpBubble(tester, voiceMessage(isMine: true));
      await tester.pump();

      expect(stores.audioClient.requestedMessageIds, isEmpty);
    });

    testWidgets('playing writes the clip out and starts the player', (
      tester,
    ) async {
      TestPathProvider.install();
      await stores.audioStore.saveOwnRecording(
        'voice-1',
        Uint8List.fromList([1, 2, 3]),
      );
      await pumpBubble(tester, voiceMessage(isMine: true));

      await tapAndSettle(tester, find.byIcon(Icons.play_arrow));

      expect(player.playedPaths.single, endsWith('voice-1.m4a'));

      final written = await tester.runAsync(
        () => File(player.playedPaths.single).readAsBytes(),
      );
      expect(written, [1, 2, 3]);
      expect(find.byIcon(Icons.pause), findsOneWidget);
    });

    testWidgets('tapping again pauses', (tester) async {
      TestPathProvider.install();
      await stores.audioStore.saveOwnRecording(
        'voice-1',
        Uint8List.fromList([1]),
      );
      await pumpBubble(tester, voiceMessage(isMine: true));
      await tapAndSettle(tester, find.byIcon(Icons.play_arrow));

      await tapAndSettle(tester, find.byIcon(Icons.pause));

      expect(player.pauseCount, 1);
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    });

    testWidgets('reuses the already-materialized file on replay', (
      tester,
    ) async {
      TestPathProvider.install();
      await stores.audioStore.saveOwnRecording(
        'voice-1',
        Uint8List.fromList([1]),
      );
      await pumpBubble(tester, voiceMessage(isMine: true));

      await tapAndSettle(tester, find.byIcon(Icons.play_arrow));
      await tapAndSettle(tester, find.byIcon(Icons.pause));
      await tapAndSettle(tester, find.byIcon(Icons.play_arrow));

      expect(player.playedPaths, hasLength(2));
      expect(player.playedPaths.first, player.playedPaths.last);
    });

    testWidgets('position updates drive the counter and the progress bar', (
      tester,
    ) async {
      await pumpBubble(tester, voiceMessage(isMine: true));

      player.positions.add(const Duration(seconds: 2));
      await tester.pump();

      expect(find.text('0:02'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        closeTo(0.4, 0.001),
      );
    });

    testWidgets('reaching the end resets to the start', (tester) async {
      TestPathProvider.install();
      await stores.audioStore.saveOwnRecording(
        'voice-1',
        Uint8List.fromList([1]),
      );
      await pumpBubble(tester, voiceMessage(isMine: true));
      await tapAndSettle(tester, find.byIcon(Icons.play_arrow));
      player.positions.add(const Duration(seconds: 3));
      await tester.pump();

      player.completions.add(null);
      await tester.pump();

      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      expect(find.text('0:05'), findsOneWidget);
    });

    testWidgets('the speed control cycles through the presets', (tester) async {
      await pumpBubble(tester, voiceMessage(isMine: true));

      expect(find.text('1x'), findsOneWidget);

      for (final expected in ['1.5x', '2x', '0.5x', '1x']) {
        await tester.tap(find.textContaining('x'));
        await tester.pump();
        expect(find.text(expected), findsOneWidget);
      }

      expect(player.playbackRates, [1.5, 2.0, 0.5, 1.0]);
    });

    testWidgets('a clip with no advertised duration falls back to position 0', (
      tester,
    ) async {
      await pumpBubble(tester, voiceMessage(isMine: true, durationMs: null));

      expect(find.text('0:00'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        0.0,
      );
    });

    testWidgets('disposes its player', (tester) async {
      await pumpBubble(tester, voiceMessage(isMine: true));

      await tester.pumpWidget(const SizedBox());

      expect(player.disposed, isTrue);
    });

    testWidgets('cleans up the temp file it materialized', (tester) async {
      TestPathProvider.install();
      await stores.audioStore.saveOwnRecording(
        'voice-1',
        Uint8List.fromList([1, 2, 3]),
      );
      await pumpBubble(tester, voiceMessage(isMine: true));
      await tapAndSettle(tester, find.byIcon(Icons.play_arrow));
      final tempPath = player.playedPaths.single;
      expect(await tester.runAsync(() => File(tempPath).exists()), isTrue);

      await tester.pumpWidget(const SizedBox());
      await settleRealWork(tester);

      expect(await tester.runAsync(() => File(tempPath).exists()), isFalse);
    });
  });

  group('file bubble', () {
    testWidgets('routes file messages to the file bubble', (tester) async {
      await pumpBubble(tester, fileMessage());

      expect(find.byType(FileMessageBubble), findsOneWidget);
    });

    testWidgets('shows the name, size and a type icon', (tester) async {
      await pumpBubble(tester, fileMessage());

      expect(find.text('rapport.pdf'), findsOneWidget);
      expect(find.text('2 ${l10nFr.storageUnitKB}'), findsOneWidget);
      expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOneWidget);
    });

    testWidgets('falls back to the message metadata with no record yet', (
      tester,
    ) async {
      await pumpBubble(tester, fileMessage(fileName: 'photo.png'));

      expect(find.text('photo.png'), findsOneWidget);
    });

    testWidgets('an incoming offer shows accept and decline', (tester) async {
      await stores.fileStore.registerIncoming(
        'file-1',
        fileName: 'rapport.pdf',
        sizeBytes: 2048,
      );

      await pumpBubble(tester, fileMessage());

      expect(find.text(l10nFr.requestAccept), findsOneWidget);
      expect(find.text(l10nFr.requestDecline), findsOneWidget);
    });

    testWidgets('declining marks it refused', (tester) async {
      await stores.fileStore.registerIncoming(
        'file-1',
        fileName: 'rapport.pdf',
        sizeBytes: 2048,
      );
      await pumpBubble(tester, fileMessage());

      await tapAndSettle(tester, find.text(l10nFr.requestDecline));

      expect(find.text(l10nFr.fileDeclined), findsOneWidget);
      expect(find.text(l10nFr.requestAccept), findsNothing);
    });

    testWidgets('accepting downloads from the sender', (tester) async {
      TestPathProvider.install();
      stores.fileClient.responses['file-1'] = [1, 2, 3];
      discovery.setPeers([testPeer(id: 'peer-1')]);
      await stores.fileStore.registerIncoming(
        'file-1',
        fileName: 'rapport.pdf',
        sizeBytes: 3,
      );
      await pumpBubble(tester, fileMessage());

      await tapAndSettle(tester, find.text(l10nFr.requestAccept));

      expect(stores.fileClient.requestedMessageIds, ['file-1']);
      expect(find.text(l10nFr.fileOpen), findsOneWidget);
      expect(find.text(l10nFr.fileDownload), findsOneWidget);
    });

    testWidgets('accepting while the sender is offline says so', (
      tester,
    ) async {
      await stores.fileStore.registerIncoming(
        'file-1',
        fileName: 'rapport.pdf',
        sizeBytes: 3,
      );
      await pumpBubble(tester, fileMessage());

      await tapAndSettle(tester, find.text(l10nFr.requestAccept));

      expect(stores.fileClient.requestedMessageIds, isEmpty);
      expect(find.text(l10nFr.fileTransferFailed), findsOneWidget);

      expect(find.text(l10nFr.requestAccept), findsOneWidget);
    });

    testWidgets('a failed download says so and stays retryable', (
      tester,
    ) async {
      TestPathProvider.install();
      discovery.setPeers([testPeer(id: 'peer-1')]);
      await stores.fileStore.registerIncoming(
        'file-1',
        fileName: 'rapport.pdf',
        sizeBytes: 3,
      );
      await pumpBubble(tester, fileMessage());

      await tapAndSettle(tester, find.text(l10nFr.requestAccept));

      expect(stores.fileClient.requestedMessageIds, ['file-1']);
      expect(find.text(l10nFr.fileTransferFailed), findsOneWidget);
      expect(find.text(l10nFr.requestAccept), findsOneWidget);
    });

    testWidgets('a successful download stays quiet', (tester) async {
      TestPathProvider.install();
      stores.fileClient.responses['file-1'] = [1, 2, 3];
      discovery.setPeers([testPeer(id: 'peer-1')]);
      await stores.fileStore.registerIncoming(
        'file-1',
        fileName: 'rapport.pdf',
        sizeBytes: 3,
      );
      await pumpBubble(tester, fileMessage());

      await tapAndSettle(tester, find.text(l10nFr.requestAccept));

      expect(find.text(l10nFr.fileTransferFailed), findsNothing);
    });

    testWidgets(
      'a download in flight shows a progress bar instead of buttons',
      (tester) async {
        TestPathProvider.install();
        discovery.setPeers([testPeer(id: 'peer-1')]);
        await stores.fileStore.registerIncoming(
          'file-1',
          fileName: 'rapport.pdf',
          sizeBytes: 100,
        );
        await pumpBubble(tester, fileMessage());

        final gate = Completer<void>();
        stores.fileClient.gate = gate;
        stores.fileClient.progressUpdates['file-1'] = [50];
        stores.fileClient.responses['file-1'] = List.filled(100, 0);
        await tapAndSettle(tester, find.text(l10nFr.requestAccept));

        expect(find.text(l10nFr.requestAccept), findsNothing);
        final bar = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        );
        expect(bar.value, closeTo(0.5, 0.001));

        gate.complete();
        await settleRealWork(tester);

        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(find.text(l10nFr.fileOpen), findsOneWidget);
      },
    );

    testWidgets('a sent file offers open and download, never accept', (
      tester,
    ) async {
      TestPathProvider.install();
      await persist(tester, () async {
        final source = File(
          '${Directory.systemTemp.createTempSync('peero_src_').path}/r.pdf',
        );
        await source.writeAsBytes([1, 2, 3]);
        await stores.fileStore.registerOwnFile(
          'file-1',
          sourcePath: source.path,
          fileName: 'rapport.pdf',
          sizeBytes: 3,
        );
      });

      await pumpBubble(tester, fileMessage(isMine: true));

      expect(find.text(l10nFr.fileOpen), findsOneWidget);
      expect(find.text(l10nFr.fileDownload), findsOneWidget);
      expect(find.text(l10nFr.requestAccept), findsNothing);
    });

    testWidgets('an image shows an inline preview once downloaded', (
      tester,
    ) async {
      TestPathProvider.install();
      await persist(tester, () async {
        final dir = Directory.systemTemp.createTempSync('peero_img_');
        final source = File('${dir.path}/photo.png');
        await source.writeAsBytes(realPngBytes());
        await stores.fileStore.registerOwnFile(
          'file-1',
          sourcePath: source.path,
          fileName: 'photo.png',
          sizeBytes: 3,
        );
      });

      await pumpBubble(
        tester,
        fileMessage(isMine: true, fileName: 'photo.png'),
      );

      expect(find.byType(Image), findsOneWidget);
      expect(find.byIcon(Icons.image_outlined), findsNothing);
    });

    testWidgets('a video shows a play overlay rather than a thumbnail', (
      tester,
    ) async {
      TestPathProvider.install();
      await persist(tester, () async {
        final dir = Directory.systemTemp.createTempSync('peero_vid_');
        final source = File('${dir.path}/clip.mp4');
        await source.writeAsBytes([0, 0, 0]);
        await stores.fileStore.registerOwnFile(
          'file-1',
          sourcePath: source.path,
          fileName: 'clip.mp4',
          sizeBytes: 3,
        );
      });

      await pumpBubble(tester, fileMessage(isMine: true, fileName: 'clip.mp4'));

      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('a pending image offer shows no preview yet', (tester) async {
      await stores.fileStore.registerIncoming(
        'file-1',
        fileName: 'photo.png',
        sizeBytes: 10,
      );

      await pumpBubble(tester, fileMessage(fileName: 'photo.png'));

      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    });
  });
}

Uint8List realPngBytes() {
  return Uint8List.fromList([
    137,
    80,
    78,
    71,
    13,
    10,
    26,
    10,
    0,
    0,
    0,
    13,
    73,
    72,
    68,
    82,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    1,
    8,
    6,
    0,
    0,
    0,
    31,
    21,
    196,
    137,
    0,
    0,
    0,
    10,
    73,
    68,
    65,
    84,
    120,
    156,
    99,
    0,
    1,
    0,
    0,
    5,
    0,
    1,
    13,
    10,
    45,
    180,
    0,
    0,
    0,
    0,
    73,
    69,
    78,
    68,
    174,
    66,
    96,
    130,
  ]);
}
