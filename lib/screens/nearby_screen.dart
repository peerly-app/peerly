import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../design/colors.dart';
import '../design/typography.dart';
import '../l10n/app_localizations.dart';
import '../models/peer.dart';
import '../services/chat_repository.dart';
import '../services/chat_store.dart';
import '../services/device_identity_service.dart';
import '../services/discovery_service.dart';
import '../services/message_client.dart';
import '../services/network_info_service.dart';
import '../widgets/peer_tile.dart';
import '../widgets/radar_pulse.dart';
import 'chat_screen.dart';

class NearbyScreen extends StatefulWidget {
  const NearbyScreen({super.key});

  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen> {
  final _networkInfo = NetworkInfoService();
  final _messageClient = MessageClient();
  String? _networkName;

  @override
  void initState() {
    super.initState();
    _networkInfo.currentNetworkName().then((name) {
      if (mounted) setState(() => _networkName = name);
    });
  }

  Future<void> _openChat(
    BuildContext context,
    Peer peer,
    ChatStore chatStore,
  ) async {
    if (chatStore.statusFor(peer.id) == null) {
      final identity = context.read<DeviceIdentityService>();
      await chatStore.setStatus(
        peer.id,
        peer.alias,
        ConversationStatus.pendingOutgoing,
      );
      final ok = await _messageClient.sendRequest(
        peer,
        id: identity.id,
        alias: identity.alias,
        platform: identity.platform,
      );
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.requestSendFailed),
          ),
        );
      }
    }
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(peerId: peer.id, peerAlias: peer.alias),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final chatStore = context.watch<ChatStore>();
    final peers = context
        .watch<DiscoveryService>()
        .peers
        .where((p) => chatStore.statusFor(p.id) != ConversationStatus.blocked)
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          Text(l10n.navNearby, style: AppTypography.screenTitle),
          const SizedBox(height: 4),
          Text(
            _networkName != null
                ? l10n.nearbySearchingNetwork(_networkName!)
                : l10n.nearbySearchingGeneric,
            style: AppTypography.body,
          ),
          const SizedBox(height: 24),
          const Center(child: RadarPulse()),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              l10n.nearbyDevicesFound(peers.length).toUpperCase(),
              style: AppTypography.eyebrow,
            ),
          ),
          if (peers.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(l10n.nearbyEmpty, style: AppTypography.body),
              ),
            ),
          for (final peer in peers) ...[
            PeerTile(
              peer: peer,
              subtitleOverride: switch (chatStore.statusFor(peer.id)) {
                ConversationStatus.pendingOutgoing =>
                  l10n.conversationsRequestSentSubtitle,
                ConversationStatus.pendingIncoming =>
                  l10n.conversationsRequestReceivedSubtitle,
                _ => null,
              },
              onTap: () => _openChat(context, peer, chatStore),
            ),
            const Divider(color: AppColors.borderSubtle, height: 1),
          ],
        ],
      ),
    );
  }
}
