import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../design/colors.dart';
import '../design/typography.dart';
import '../l10n/app_localizations.dart';
import '../models/chat_message.dart';
import '../models/peer.dart';
import '../services/audio_recorder_service.dart';
import '../services/audio_store.dart';
import '../services/chat_repository.dart';
import '../services/chat_store.dart';
import '../services/device_identity_service.dart';
import '../services/discovery_service.dart';
import '../services/file_store.dart';
import '../services/message_client.dart';
import '../utils/file_types.dart';
import '../utils/formatting.dart';
import '../widgets/avatar.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/message_bubble.dart';

const _maxRecordingDuration = Duration(minutes: 5);
const _minRecordingDuration = Duration(milliseconds: 500);

class ChatScreen extends StatefulWidget {
  final String peerId;
  final String peerAlias;

  const ChatScreen({super.key, required this.peerId, required this.peerAlias});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _messageClient = MessageClient();
  final _recorder = createAudioRecorder();
  bool _sending = false;
  int _lastMessageCount = 0;
  bool _hasComposerText = false;

  bool _isRecording = false;
  bool _recordPulse = false;
  Duration _recordDuration = Duration.zero;
  Timer? _recordTimer;
  Peer? _recordingPeer;

  Future<void>? _startFuture;
  bool _stopRequestedWhileStarting = false;
  bool _cancelRequestedWhileStarting = false;

  late final ChatStore _chatStore;

  @override
  void initState() {
    super.initState();
    _chatStore = context.read<ChatStore>();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _chatStore.setViewing(widget.peerId);
    });
    _chatStore.ensureLoaded(widget.peerId);

    _controller.addListener(() {
      final hasText = _controller.text.trim().isNotEmpty;
      if (hasText != _hasComposerText) {
        setState(() => _hasComposerText = hasText);
      }
    });

    _recorder.hasPermission();
  }

  @override
  void dispose() {
    _chatStore.setViewing(null);
    _controller.dispose();
    _scrollController.dispose();
    _recordTimer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send(Peer? peer) async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    final identity = context.read<DeviceIdentityService>();
    final message = ChatMessage(
      fromId: identity.id,
      fromAlias: identity.alias,
      text: text,
      timestamp: DateTime.now(),
      isMine: true,
    );

    setState(() => _sending = true);
    _controller.clear();
    await _chatStore.add(widget.peerId, widget.peerAlias, message);

    final ok = peer != null && await _messageClient.send(peer, message);
    if (mounted) {
      setState(() => _sending = false);
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.chatSendFailed)),
        );
      }
    }
  }

  Future<void> _startRecording(Peer? peer) async {
    if (_isRecording || _startFuture != null) return;
    _stopRequestedWhileStarting = false;
    _cancelRequestedWhileStarting = false;
    final future = _doStartRecording(peer);
    _startFuture = future;
    await future;
    _startFuture = null;
  }

  Future<void> _doStartRecording(Peer? peer) async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.voiceMicPermissionDenied,
            ),
          ),
        );
      }
      return;
    }
    await _recorder.start();
    if (!mounted) return;
    if (_cancelRequestedWhileStarting) {
      await _recorder.cancel();
      return;
    }
    _recordingPeer = peer;
    setState(() {
      _isRecording = true;
      _recordDuration = Duration.zero;
      _recordPulse = false;
    });
    _recordTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      setState(() {
        _recordDuration += const Duration(milliseconds: 500);
        _recordPulse = !_recordPulse;
      });
      if (_recordDuration >= _maxRecordingDuration) _stopAndSendRecording();
    });
    if (_stopRequestedWhileStarting) {
      await _performStopAndSend();
    }
  }

  Future<void> _stopAndSendRecording() async {
    if (_startFuture != null) {
      _stopRequestedWhileStarting = true;
      return;
    }
    await _performStopAndSend();
  }

  Future<void> _performStopAndSend() async {
    if (!_isRecording) return;
    _recordTimer?.cancel();
    final duration = _recordDuration;
    final peer = _recordingPeer;
    final bytes = await _recorder.stop();
    if (mounted) setState(() => _isRecording = false);
    if (bytes == null || duration < _minRecordingDuration) return;
    await _sendVoice(peer, bytes, duration);
  }

  Future<void> _cancelRecording() async {
    if (_startFuture != null) {
      _cancelRequestedWhileStarting = true;
      return;
    }
    await _performCancel();
  }

  Future<void> _performCancel() async {
    if (!_isRecording) return;
    _recordTimer?.cancel();
    await _recorder.cancel();
    if (mounted) setState(() => _isRecording = false);
  }

  Future<void> _sendVoice(
    Peer? peer,
    Uint8List bytes,
    Duration duration,
  ) async {
    final identity = context.read<DeviceIdentityService>();
    final audioStore = context.read<AudioStore>();
    final message = ChatMessage(
      fromId: identity.id,
      fromAlias: identity.alias,
      text: '',
      timestamp: DateTime.now(),
      isMine: true,
      kind: MessageKind.voice,
      voiceDurationMs: duration.inMilliseconds,
    );
    await audioStore.saveOwnRecording(message.id, bytes);
    await _chatStore.add(widget.peerId, widget.peerAlias, message);

    final ok = peer != null && await _messageClient.send(peer, message);
    if (mounted && !ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.chatSendFailed)),
      );
    }
  }

  Future<void> _pickAndSendFile(Peer? peer) async {
    final l10n = AppLocalizations.of(context)!;
    final identity = context.read<DeviceIdentityService>();
    final fileStore = context.read<FileStore>();
    PlatformFile? picked;
    try {
      picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: allowedFileExtensions,
      );
    } catch (_) {
      picked = null;
    }
    if (picked == null || picked.path == null) return;

    if (!isSendableFile(picked.name, picked.size)) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.fileNotAllowed)));
      }
      return;
    }

    final message = ChatMessage(
      fromId: identity.id,
      fromAlias: identity.alias,
      text: '',
      timestamp: DateTime.now(),
      isMine: true,
      kind: MessageKind.file,
      fileName: picked.name,
      fileSizeBytes: picked.size,
    );
    await fileStore.registerOwnFile(
      message.id,
      sourcePath: picked.path!,
      fileName: picked.name,
      sizeBytes: picked.size,
    );
    await _chatStore.add(widget.peerId, widget.peerAlias, message);

    final ok = peer != null && await _messageClient.send(peer, message);
    if (mounted && !ok) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.chatSendFailed)));
    }
  }

  Future<void> _respondToRequest(Peer? peer, {required bool accepted}) async {
    final identity = context.read<DeviceIdentityService>();
    if (accepted) {
      await _chatStore.setStatus(
        widget.peerId,
        widget.peerAlias,
        ConversationStatus.accepted,
      );
    } else {
      await _chatStore.resetRelationship(widget.peerId);
    }
    if (peer != null) {
      await _messageClient.sendRequestResponse(
        peer,
        id: identity.id,
        alias: identity.alias,
        accepted: accepted,
      );
    }

    if (!accepted && mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  Future<void> _block() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await confirmBlock(
      context,
      title: l10n.blockConfirmTitle(widget.peerAlias),
      body: l10n.blockConfirmBody,
    );
    if (!confirmed) return;
    await _chatStore.setStatus(
      widget.peerId,
      widget.peerAlias,
      ConversationStatus.blocked,
    );
  }

  Future<void> _unblock() => _chatStore.resetRelationship(widget.peerId);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final discovery = context.watch<DiscoveryService>();

    Peer? livePeer;
    for (final p in discovery.peers) {
      if (p.id == widget.peerId) {
        livePeer = p;
        break;
      }
    }
    final isOnline = livePeer != null;

    final chatStore = context.watch<ChatStore>();
    final messages = chatStore.messagesFor(widget.peerId);
    if (messages.length != _lastMessageCount) {
      _lastMessageCount = messages.length;
      _scrollToBottom();
    }
    final status = chatStore.statusFor(widget.peerId);

    final entries = buildChatEntries(
      messages,
      dayLabel: (day) => _dayLabel(context, l10n, day),
    );

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        actions: status == ConversationStatus.accepted || status == null
            ? [
                PopupMenuButton<void>(
                  itemBuilder: (context) => [
                    PopupMenuItem(onTap: _block, child: Text(l10n.block)),
                  ],
                ),
              ]
            : null,
        title: Row(
          children: [
            Avatar(id: widget.peerId, name: widget.peerAlias, diameter: 36),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(widget.peerAlias, style: AppTypography.chatNameHeader),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isOnline
                            ? AppColors.avatarHues[2]
                            : AppColors.textDim,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      isOnline ? l10n.chatActiveNow : l10n.chatOffline,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        color: AppColors.textDim,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? Center(child: Text(l10n.chatEmpty, style: AppTypography.body))
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: entries.length,

                    itemBuilder: (context, index) => switch (entries[index]) {
                      ChatDayEntry(:final label) => _DaySeparator(label: label),
                      ChatMessageEntry(:final message) => _TimestampedMessage(
                        message: message,
                      ),
                    },
                  ),
          ),
          SafeArea(child: _bottomArea(l10n, status, livePeer)),
        ],
      ),
    );
  }

  Widget _bottomArea(
    AppLocalizations l10n,
    ConversationStatus? status,
    Peer? livePeer,
  ) {
    switch (status) {
      case ConversationStatus.pendingOutgoing:
        return StatusBanner(
          text: l10n.chatPendingOutgoingBanner(widget.peerAlias),
        );
      case ConversationStatus.pendingIncoming:
        return StatusBanner(
          text: l10n.chatPendingIncomingBanner(widget.peerAlias),
          actions: [
            TextButton(
              onPressed: () => _respondToRequest(livePeer, accepted: false),
              child: Text(l10n.requestDecline),
            ),
            FilledButton(
              onPressed: () => _respondToRequest(livePeer, accepted: true),
              child: Text(l10n.requestAccept),
            ),
          ],
        );
      case ConversationStatus.blocked:
        return StatusBanner(
          text: l10n.chatBlockedBanner(widget.peerAlias),
          actions: [TextButton(onPressed: _unblock, child: Text(l10n.unblock))],
        );
      case ConversationStatus.accepted:
      case null:
        final hasText = _hasComposerText;
        return Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              GestureDetector(
                onTap: _isRecording ? null : () => _pickAndSendFile(livePeer),
                child: const AttachButton(),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _isRecording
                    ? _recordingInfo()
                    : Container(
                        height: 38,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: AppColors.panel2,
                          borderRadius: BorderRadius.circular(19),
                        ),
                        child: TextField(
                          controller: _controller,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            color: AppColors.text,
                            fontSize: 14,
                          ),
                          decoration: InputDecoration(
                            hintText: l10n.chatComposerHint(widget.peerAlias),
                            hintStyle: const TextStyle(
                              color: AppColors.textDim,
                              fontFamily: 'Inter',
                              fontSize: 14,
                            ),
                            border: InputBorder.none,
                            isCollapsed: true,
                          ),
                          onSubmitted: (_) => _send(livePeer),
                          textInputAction: TextInputAction.send,
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              if (hasText && !_isRecording)
                GestureDetector(
                  onTap: _sending ? null : () => _send(livePeer),
                  child: const SendButton(),
                )
              else
                GestureDetector(
                  onTapDown: (_) => _startRecording(livePeer),
                  onTapUp: (_) => _stopAndSendRecording(),
                  onTapCancel: _cancelRecording,
                  child: const MicButton(),
                ),
            ],
          ),
        );
    }
  }

  Widget _recordingInfo() {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.panel2,
        borderRadius: BorderRadius.circular(19),
      ),
      child: Row(
        children: [
          AnimatedOpacity(
            opacity: _recordPulse ? 1 : 0.3,
            duration: const Duration(milliseconds: 400),
            child: Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: Colors.redAccent,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(formatClockDuration(_recordDuration), style: AppTypography.body),
          const Spacer(),
          GestureDetector(
            onTap: _cancelRecording,
            child: const Icon(
              Icons.delete_outline,
              size: 20,
              color: AppColors.textDim,
            ),
          ),
        ],
      ),
    );
  }
}

class StatusBanner extends StatelessWidget {
  final String text;
  final List<Widget> actions;

  const StatusBanner({super.key, required this.text, this.actions = const []});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: AppColors.panel,
      child: Row(
        children: [
          Expanded(child: Text(text, style: AppTypography.body)),
          ...actions,
        ],
      ),
    );
  }
}

class AttachButton extends StatelessWidget {
  const AttachButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: const BoxDecoration(
        color: AppColors.panel2,
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.add, color: AppColors.text, size: 20),
    );
  }
}

class SendButton extends StatelessWidget {
  const SendButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: const BoxDecoration(
        color: AppColors.accent,
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.arrow_upward,
        color: AppColors.onAccent,
        size: 18,
      ),
    );
  }
}

class MicButton extends StatelessWidget {
  const MicButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: const BoxDecoration(
        color: AppColors.accent,
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.mic, color: AppColors.onAccent, size: 18),
    );
  }
}

sealed class ChatEntry {
  const ChatEntry();
}

class ChatDayEntry extends ChatEntry {
  final String label;

  const ChatDayEntry(this.label);
}

class ChatMessageEntry extends ChatEntry {
  final ChatMessage message;

  const ChatMessageEntry(this.message);
}

List<ChatEntry> buildChatEntries(
  List<ChatMessage> messages, {
  required String Function(DateTime day) dayLabel,
}) {
  final entries = <ChatEntry>[];
  DateTime? lastDay;
  for (final message in messages) {
    final timestamp = message.timestamp;
    final day = DateTime(timestamp.year, timestamp.month, timestamp.day);
    if (lastDay == null || !isSameDay(day, lastDay)) {
      entries.add(ChatDayEntry(dayLabel(day)));
      lastDay = day;
    }
    entries.add(ChatMessageEntry(message));
  }
  return entries;
}

String _dayLabel(BuildContext context, AppLocalizations l10n, DateTime day) {
  final now = DateTime.now();
  if (isSameDay(day, now)) return l10n.chatToday;
  if (isSameDay(day, now.subtract(const Duration(days: 1)))) {
    return l10n.chatYesterday;
  }
  return DateFormat.yMMMMd(
    Localizations.localeOf(context).toString(),
  ).format(day);
}

class _DaySeparator extends StatelessWidget {
  final String label;

  const _DaySeparator({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.panel2,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: AppTypography.body.copyWith(
              fontSize: 12,
              color: AppColors.textDim,
            ),
          ),
        ),
      ),
    );
  }
}

class _TimestampedMessage extends StatelessWidget {
  final ChatMessage message;

  const _TimestampedMessage({required this.message});

  @override
  Widget build(BuildContext context) {
    final isMine = message.isMine;
    final timeStr = TimeOfDay.fromDateTime(message.timestamp).format(context);
    return Column(
      crossAxisAlignment: isMine
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        MessageBubble(message: message),
        Padding(
          padding: const EdgeInsets.only(
            left: 14,
            right: 14,
            top: 2,
            bottom: 6,
          ),
          child: Text(
            timeStr,
            style: AppTypography.body.copyWith(
              fontSize: 11,
              color: AppColors.textDim,
            ),
          ),
        ),
      ],
    );
  }
}
