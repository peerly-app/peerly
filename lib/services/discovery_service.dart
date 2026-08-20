import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/peer.dart';
import 'device_identity_service.dart';

class DiscoveryService extends ChangeNotifier {
  static const String multicastGroup = '239.100.100.100';
  static const int discoveryPort = 53320;
  static const Duration announceInterval = Duration(seconds: 3);
  static const Duration staleAfter = Duration(seconds: 10);
  static const Duration cleanupInterval = Duration(seconds: 2);

  final DeviceIdentityService identity;

  final int Function() servicePort;

  final String? Function() avatarVersion;

  void Function(List<Peer> peers)? onPeerAnnounced;

  DiscoveryService({
    required this.identity,
    required this.servicePort,
    required this.avatarVersion,
    this.onPeerAnnounced,
  });

  RawDatagramSocket? _socket;
  Timer? _announceTimer;
  Timer? _cleanupTimer;

  final Map<String, Peer> _peers = {};
  List<Peer>? _peersView;

  List<Peer> get peers => _peersView ??= List.unmodifiable(_peers.values);

  Future<void> start() async {
    if (_socket != null) return;

    RawDatagramSocket socket;
    try {
      socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        discoveryPort,
        reuseAddress: true,
        reusePort: true,
      );
    } on SocketException {
      socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        discoveryPort,
        reuseAddress: true,
      );
    }
    socket.joinMulticast(InternetAddress(multicastGroup));
    socket.listen(_onEvent);
    _socket = socket;

    _announceTimer = Timer.periodic(announceInterval, (_) => _announce());
    _cleanupTimer = Timer.periodic(cleanupInterval, (_) => _pruneStale());
    _announce();
  }

  void _onEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final datagram = _socket?.receive();
    if (datagram == null) return;

    try {
      handleAnnouncement(
        jsonDecode(utf8.decode(datagram.data)) as Map<String, dynamic>,
        sourceIp: datagram.address.address,
      );
    } catch (_) {}
  }

  @visibleForTesting
  void handleAnnouncement(
    Map<String, dynamic> json, {
    required String sourceIp,
  }) {
    if (json['type'] != 'announce') return;

    final peerId = json['id'] as String;

    if (peerId == identity.id) return;

    final previous = _peers[peerId];
    final peer = Peer(
      id: peerId,
      alias: json['alias'] as String,
      platform: json['platform'] as String,
      ip: sourceIp,
      port: json['port'] as int,
      lastSeen: DateTime.now(),
      avatarVersion: json['avatarVersion'] as String?,
    );
    _peers[peerId] = peer;
    _peersView = null;

    if (previous == null || !previous.hasSameAdvertisement(peer)) {
      notifyListeners();
    }
    onPeerAnnounced?.call(peers);
  }

  @visibleForTesting
  Map<String, dynamic> buildAnnouncement() => {
    'type': 'announce',
    'id': identity.id,
    'alias': identity.alias,
    'platform': identity.platform,
    'port': servicePort(),
    'avatarVersion': ?avatarVersion(),
  };

  void _announce() {
    final socket = _socket;
    if (socket == null || !identity.ready) return;

    try {
      socket.send(
        utf8.encode(jsonEncode(buildAnnouncement())),
        InternetAddress(multicastGroup),
        discoveryPort,
      );
    } on SocketException catch (_) {}
  }

  void _pruneStale() {
    final before = _peers.length;
    final pruned = pruneStalePeers(_peers, DateTime.now());
    if (pruned.length != before) {
      _peers
        ..clear()
        ..addAll(pruned);
      _peersView = null;
      notifyListeners();
    }
  }

  @visibleForTesting
  static Map<String, Peer> pruneStalePeers(
    Map<String, Peer> peers,
    DateTime now,
  ) {
    final result = Map<String, Peer>.from(peers);
    result.removeWhere((_, peer) => now.difference(peer.lastSeen) > staleAfter);
    return result;
  }

  @override
  void dispose() {
    _announceTimer?.cancel();
    _cleanupTimer?.cancel();
    _socket?.close();
    super.dispose();
  }
}
