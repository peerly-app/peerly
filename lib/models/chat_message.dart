import 'package:uuid/uuid.dart';

enum MessageKind { text, voice, file }

class ChatMessage {
  final String id;
  final String fromId;
  final String fromAlias;
  final String text;
  final DateTime timestamp;
  final bool isMine;
  final MessageKind kind;

  final int? voiceDurationMs;

  final String? fileName;
  final int? fileSizeBytes;

  ChatMessage({
    String? id,
    required this.fromId,
    required this.fromAlias,
    required this.text,
    required this.timestamp,
    required this.isMine,
    this.kind = MessageKind.text,
    this.voiceDurationMs,
    this.fileName,
    this.fileSizeBytes,
  }) : id = id ?? const Uuid().v4();

  Map<String, dynamic> toJson() => {
    'id': id,
    'fromId': fromId,
    'fromAlias': fromAlias,
    'text': text,
    'timestamp': timestamp.toIso8601String(),
    'kind': kind.name,
    if (voiceDurationMs != null) 'voiceDurationMs': voiceDurationMs,
    if (fileName != null) 'fileName': fileName,
    if (fileSizeBytes != null) 'fileSizeBytes': fileSizeBytes,
  };

  static ChatMessage fromJson(
    Map<String, dynamic> json, {
    required bool isMine,
  }) {
    return ChatMessage(
      id: json['id'] as String?,
      fromId: json['fromId'] as String,
      fromAlias: json['fromAlias'] as String,
      text: json['text'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      isMine: isMine,
      kind: MessageKind.values.firstWhere(
        (k) => k.name == json['kind'],
        orElse: () => MessageKind.text,
      ),
      voiceDurationMs: json['voiceDurationMs'] as int?,
      fileName: json['fileName'] as String?,
      fileSizeBytes: json['fileSizeBytes'] as int?,
    );
  }
}
