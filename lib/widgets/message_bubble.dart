import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../design/colors.dart';
import '../design/typography.dart';
import '../l10n/app_localizations.dart';
import '../models/chat_message.dart';
import '../models/peer.dart';
import '../screens/image_viewer_screen.dart';
import '../screens/video_player_screen.dart';
import '../services/audio_store.dart';
import '../services/discovery_service.dart';
import '../services/file_repository.dart';
import '../services/file_store.dart';
import '../services/voice_player.dart';
import '../utils/file_types.dart';
import '../utils/formatting.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final double maxWidthFraction;
  final double radius;

  const MessageBubble({
    super.key,
    required this.message,
    this.maxWidthFraction = 0.76,
    this.radius = 18,
  });

  @override
  Widget build(BuildContext context) {
    if (message.kind == MessageKind.voice) {
      return VoiceMessageBubble(
        message: message,
        maxWidthFraction: maxWidthFraction,
        radius: radius,
      );
    }
    if (message.kind == MessageKind.file) {
      return FileMessageBubble(
        message: message,
        maxWidthFraction: maxWidthFraction,
        radius: radius,
      );
    }

    final isMine = message.isMine;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * maxWidthFraction,
        ),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        decoration: BoxDecoration(
          color: isMine ? AppColors.accent : AppColors.panel2,
          borderRadius: BorderRadius.circular(radius),
        ),
        child: SelectableText(
          message.text,
          style: AppTypography.bubbleText.copyWith(
            color: isMine ? AppColors.onAccent : AppColors.text,
          ),
        ),
      ),
    );
  }
}

const _playbackSpeeds = [0.5, 1.0, 1.5, 2.0];

String _formatSpeed(double speed) {
  return speed == speed.roundToDouble() ? '${speed.toInt()}x' : '${speed}x';
}

class VoiceMessageBubble extends StatefulWidget {
  final ChatMessage message;
  final double maxWidthFraction;
  final double radius;

  const VoiceMessageBubble({
    super.key,
    required this.message,
    required this.maxWidthFraction,
    required this.radius,
  });

  @override
  State<VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<VoiceMessageBubble> {
  final _player = createVoicePlayer();
  int _speedIndex = 1;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<void>? _completeSub;
  String? _tempFilePath;

  @override
  void initState() {
    super.initState();
    _positionSub = _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _completeSub = _player.onComplete.listen((_) {
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _position = Duration.zero;
        });
      }
    });
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _completeSub?.cancel();
    _player.dispose();
    _discardTempFile();
    super.dispose();
  }

  void _discardTempFile() {
    final path = _tempFilePath;
    if (path == null) return;
    _tempFilePath = null;
    unawaited(_deleteQuietly(path));
  }

  Future<void> _deleteQuietly(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  Future<String> _materializedFile(Uint8List bytes) async {
    final existing = _tempFilePath;
    if (existing != null && await File(existing).exists()) return existing;
    final dir = await getTemporaryDirectory();
    await dir.create(recursive: true);
    final file = File('${dir.path}/${widget.message.id}.m4a');
    await file.writeAsBytes(bytes, flush: true);
    _tempFilePath = file.path;
    return file.path;
  }

  Future<void> _togglePlay(Uint8List bytes) async {
    if (_isPlaying) {
      await _player.pause();
      if (mounted) setState(() => _isPlaying = false);
      return;
    }
    final path = await _materializedFile(bytes);
    await _player.playFile(path);
    await _player.setPlaybackRate(_playbackSpeeds[_speedIndex]);
    if (mounted) setState(() => _isPlaying = true);
  }

  void _cycleSpeed() {
    setState(() => _speedIndex = (_speedIndex + 1) % _playbackSpeeds.length);
    _player.setPlaybackRate(_playbackSpeeds[_speedIndex]);
  }

  @override
  Widget build(BuildContext context) {
    final isMine = widget.message.isMine;
    final bytes = context.watch<AudioStore>().bytesFor(widget.message.id);

    if (!isMine && bytes == null) {
      final peers = context.watch<DiscoveryService>().peers;
      for (final peer in peers) {
        if (peer.id == widget.message.fromId) {
          context.read<AudioStore>().ensureFetched(widget.message.id, peer);
          break;
        }
      }
    }

    final knownTotal = widget.message.voiceDurationMs != null
        ? Duration(milliseconds: widget.message.voiceDurationMs!)
        : null;
    final total = knownTotal ?? _position;
    final progress = total.inMilliseconds == 0
        ? 0.0
        : (_position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    final fgColor = isMine ? AppColors.onAccent : AppColors.text;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * widget.maxWidthFraction,
        ),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: isMine ? AppColors.accent : AppColors.panel2,
          borderRadius: BorderRadius.circular(widget.radius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: bytes == null ? null : () => _togglePlay(bytes),
              child: Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: fgColor.withValues(alpha: 0.16),
                ),
                child: Icon(
                  bytes == null
                      ? Icons.hourglass_empty
                      : (_isPlaying ? Icons.pause : Icons.play_arrow),
                  size: 16,
                  color: fgColor,
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 80,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 3,
                  backgroundColor: fgColor.withValues(alpha: 0.2),
                  valueColor: AlwaysStoppedAnimation(fgColor),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formatClockDuration(
                _isPlaying || _position > Duration.zero ? _position : total,
              ),
              style: AppTypography.bubbleText.copyWith(
                color: fgColor,
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: _cycleSpeed,
              child: Text(
                _formatSpeed(_playbackSpeeds[_speedIndex]),
                style: AppTypography.bubbleText.copyWith(
                  color: fgColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _openFile(String path) async {
  if (Platform.isAndroid || Platform.isIOS) {
    await OpenFilex.open(path);
  } else if (Platform.isMacOS) {
    await Process.run('open', [path]);
  } else if (Platform.isWindows) {
    await Process.run('cmd', ['/c', 'start', '', path]);
  } else if (Platform.isLinux) {
    await Process.run('xdg-open', [path]);
  }
}

class FileMessageBubble extends StatelessWidget {
  final ChatMessage message;
  final double maxWidthFraction;
  final double radius;

  const FileMessageBubble({
    super.key,
    required this.message,
    required this.maxWidthFraction,
    required this.radius,
  });

  Peer? _livePeer(BuildContext context) {
    for (final peer in context.read<DiscoveryService>().peers) {
      if (peer.id == message.fromId) return peer;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isMine = message.isMine;
    final fileStore = context.watch<FileStore>();
    final record = fileStore.recordFor(message.id);
    final fileName = record?.fileName ?? message.fileName ?? '';
    final sizeBytes = record?.sizeBytes ?? message.fileSizeBytes ?? 0;
    final status = record?.status ?? FileTransferStatus.pending;
    final progress = fileStore.progressFor(message.id);
    final fgColor = isMine ? AppColors.onAccent : AppColors.text;
    final localPath = record?.localPath;
    final isImage = isImageFile(fileName);
    final isVideo = isVideoFile(fileName);
    final showsMediaPreview =
        status == FileTransferStatus.accepted &&
        localPath != null &&
        (isImage || isVideo);

    final previewSize = (MediaQuery.of(context).size.width * 0.5).clamp(
      120.0,
      240.0,
    );

    Widget fileRow = showsMediaPreview
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => isImage
                        ? ImageViewerScreen(path: localPath)
                        : VideoPlayerScreen(path: localPath),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: previewSize,
                    height: previewSize,
                    child: isImage
                        ? Image.file(File(localPath), fit: BoxFit.cover)
                        : Stack(
                            fit: StackFit.expand,
                            children: [
                              Container(color: fgColor.withValues(alpha: 0.12)),
                              Center(
                                child: Container(
                                  width: 48,
                                  height: 48,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.black.withValues(alpha: 0.5),
                                  ),
                                  child: const Icon(
                                    Icons.play_arrow,
                                    color: Colors.white,
                                    size: 28,
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: SizedBox(
                  width: previewSize,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bubbleText.copyWith(
                          color: fgColor,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        formatByteSize(l10n, sizeBytes),
                        style: AppTypography.bubbleText.copyWith(
                          color: fgColor.withValues(alpha: 0.7),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(fileIconFor(fileName), color: fgColor),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bubbleText.copyWith(color: fgColor),
                    ),
                    Text(
                      formatByteSize(l10n, sizeBytes),
                      style: AppTypography.bubbleText.copyWith(
                        color: fgColor,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

    final Widget? actionRow = switch (status) {
      FileTransferStatus.pending when progress != null => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 3,
            backgroundColor: fgColor.withValues(alpha: 0.2),
            valueColor: AlwaysStoppedAnimation(fgColor),
          ),
        ),
      ),
      FileTransferStatus.pending => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () => fileStore.decline(message.id),
              child: Text(l10n.requestDecline),
            ),
            FilledButton(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final peer = _livePeer(context);
                final ok =
                    peer != null && await fileStore.accept(message.id, peer);
                if (!ok) {
                  messenger.showSnackBar(
                    SnackBar(content: Text(l10n.fileTransferFailed)),
                  );
                }
              },
              child: Text(l10n.requestAccept),
            ),
          ],
        ),
      ),
      FileTransferStatus.accepted when localPath != null => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () async {
                final bytes = await File(localPath).readAsBytes();
                if (!context.mounted) return;
                await FilePicker.saveFile(
                  dialogTitle: l10n.fileChooseDestination,
                  fileName: fileName,
                  bytes: bytes,
                  initialDirectory: await fileStore
                      .suggestedSaveDirectoryPath(),
                );
              },
              child: Text(l10n.fileDownload),
            ),
            TextButton(
              onPressed: () => _openFile(localPath),
              child: Text(l10n.fileOpen),
            ),
          ],
        ),
      ),
      FileTransferStatus.accepted => null,
      FileTransferStatus.declined => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          l10n.fileDeclined,
          style: AppTypography.bubbleText.copyWith(
            color: fgColor.withValues(alpha: 0.6),
            fontSize: 12,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    };

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * maxWidthFraction,
        ),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: isMine ? AppColors.accent : AppColors.panel2,
          borderRadius: BorderRadius.circular(radius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [fileRow, ?actionRow],
        ),
      ),
    );
  }
}
