import 'package:flutter_test/flutter_test.dart';
import 'package:peero/models/chat_message.dart';

void main() {
  test('toJson/fromJson round-trip preserves message content', () {
    final original = ChatMessage(
      fromId: 'device-123',
      fromAlias: 'Alice',
      text: 'Salut !',
      timestamp: DateTime.utc(2026, 7, 23, 10, 30),
      isMine: true,
    );

    final decoded = ChatMessage.fromJson(original.toJson(), isMine: false);

    expect(decoded.fromId, original.fromId);
    expect(decoded.fromAlias, original.fromAlias);
    expect(decoded.text, original.text);
    expect(decoded.timestamp, original.timestamp);
    expect(decoded.isMine, false);
  });

  test('toJson/fromJson round-trip preserves id, kind and voiceDurationMs', () {
    final original = ChatMessage(
      fromId: 'device-123',
      fromAlias: 'Alice',
      text: '',
      timestamp: DateTime.utc(2026, 7, 23, 10, 30),
      isMine: true,
      kind: MessageKind.voice,
      voiceDurationMs: 4200,
    );

    final decoded = ChatMessage.fromJson(original.toJson(), isMine: true);

    expect(decoded.id, original.id);
    expect(decoded.kind, MessageKind.voice);
    expect(decoded.voiceDurationMs, 4200);
  });

  test('toJson/fromJson round-trip preserves fileName and fileSizeBytes', () {
    final original = ChatMessage(
      fromId: 'device-123',
      fromAlias: 'Alice',
      text: '',
      timestamp: DateTime.utc(2026, 7, 23, 10, 30),
      isMine: true,
      kind: MessageKind.file,
      fileName: 'rapport.pdf',
      fileSizeBytes: 123456,
    );

    final decoded = ChatMessage.fromJson(original.toJson(), isMine: true);

    expect(decoded.id, original.id);
    expect(decoded.kind, MessageKind.file);
    expect(decoded.fileName, 'rapport.pdf');
    expect(decoded.fileSizeBytes, 123456);
  });

  test(
    'fromJson defaults to a text message with a fresh id when id/kind are absent',
    () {
      final legacyJson = {
        'fromId': 'device-123',
        'fromAlias': 'Alice',
        'text': 'Salut !',
        'timestamp': DateTime.utc(2026, 7, 23, 10, 30).toIso8601String(),
      };

      final decoded = ChatMessage.fromJson(legacyJson, isMine: false);

      expect(decoded.id, isNotEmpty);
      expect(decoded.kind, MessageKind.text);
      expect(decoded.voiceDurationMs, isNull);
    },
  );
}
