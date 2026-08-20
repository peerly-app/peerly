import 'package:flutter_test/flutter_test.dart';
import 'package:peero/models/peer.dart';
import 'package:peero/services/device_identity_service.dart';
import 'package:peero/services/discovery_service.dart';

import '../helpers/test_harness.dart';

Peer _peer(String id, DateTime lastSeen) => Peer(
  id: id,
  alias: 'peer-$id',
  platform: 'linux',
  ip: '192.168.1.$id',
  port: 12345,
  lastSeen: lastSeen,
);

Map<String, dynamic> announcement({
  String id = 'peer-1',
  String alias = 'Bob',
  String platform = 'linux',
  int port = 5000,
  String? avatarVersion,
}) {
  return {
    'type': 'announce',
    'id': id,
    'alias': alias,
    'platform': platform,
    'port': port,
    'avatarVersion': ?avatarVersion,
  };
}

void main() {
  group('pruneStalePeers', () {
    test('keeps recently-seen peers and drops stale ones', () {
      final now = DateTime(2026, 7, 23, 12, 0, 0);
      final peers = {
        'fresh': _peer('1', now.subtract(const Duration(seconds: 5))),
        'stale': _peer('2', now.subtract(const Duration(seconds: 15))),
        'boundary': _peer('3', now.subtract(const Duration(seconds: 10))),
      };

      final result = DiscoveryService.pruneStalePeers(peers, now);

      expect(result.containsKey('fresh'), isTrue);
      expect(result.containsKey('stale'), isFalse);
      expect(result.containsKey('boundary'), isTrue);
    });

    test('does not mutate the input map', () {
      final now = DateTime(2026, 7, 23, 12, 0, 0);
      final peers = {
        'stale': _peer('9', now.subtract(const Duration(seconds: 30))),
      };

      DiscoveryService.pruneStalePeers(peers, now);

      expect(peers.containsKey('stale'), isTrue);
    });

    test('an empty map stays empty', () {
      expect(DiscoveryService.pruneStalePeers({}, DateTime(2026)), isEmpty);
    });
  });

  group('handleAnnouncement', () {
    late DiscoveryService discovery;
    late List<List<Peer>> announcedBatches;
    late int notifications;

    setUp(() {
      notifications = 0;
      announcedBatches = [];
      discovery = DiscoveryService(
        identity: loadedIdentity(id: 'me'),
        servicePort: () => 4242,
        avatarVersion: () => 'own-v1',
        onPeerAnnounced: announcedBatches.add,
      );
      discovery.addListener(() => notifications++);
    });

    tearDown(() => discovery.dispose());

    test('records a newly discovered peer and notifies', () {
      discovery.handleAnnouncement(
        announcement(avatarVersion: 'v1'),
        sourceIp: '192.168.1.20',
      );

      final peer = discovery.peers.single;
      expect(peer.id, 'peer-1');
      expect(peer.alias, 'Bob');
      expect(peer.platform, 'linux');
      expect(peer.port, 5000);
      expect(peer.avatarVersion, 'v1');

      expect(peer.ip, '192.168.1.20');
      expect(notifications, 1);
    });

    test(
      'an unchanged heartbeat refreshes lastSeen without notifying',
      () async {
        discovery.handleAnnouncement(announcement(), sourceIp: '192.168.1.20');
        final firstSeen = discovery.peers.single.lastSeen;
        announcedBatches.clear();
        await Future<void>.delayed(const Duration(milliseconds: 5));

        discovery.handleAnnouncement(announcement(), sourceIp: '192.168.1.20');

        expect(discovery.peers.single.lastSeen.isAfter(firstSeen), isTrue);

        expect(notifications, 1);

        expect(announcedBatches, hasLength(1));
      },
    );

    test('notifies on any change a user could notice', () {
      discovery.handleAnnouncement(
        announcement(avatarVersion: 'v1'),
        sourceIp: '192.168.1.20',
      );

      discovery.handleAnnouncement(
        announcement(alias: 'Bobby', avatarVersion: 'v1'),
        sourceIp: '192.168.1.20',
      );
      expect(notifications, 2);

      discovery.handleAnnouncement(
        announcement(alias: 'Bobby', avatarVersion: 'v2'),
        sourceIp: '192.168.1.20',
      );
      expect(notifications, 3);

      discovery.handleAnnouncement(
        announcement(alias: 'Bobby', avatarVersion: 'v2', port: 6000),
        sourceIp: '192.168.1.20',
      );
      expect(notifications, 4);

      discovery.handleAnnouncement(
        announcement(alias: 'Bobby', avatarVersion: 'v2', port: 6000),
        sourceIp: '192.168.1.99',
      );
      expect(notifications, 5);
      expect(discovery.peers.single.ip, '192.168.1.99');
    });

    test('tracks several peers independently', () {
      discovery.handleAnnouncement(
        announcement(id: 'peer-1'),
        sourceIp: '192.168.1.20',
      );
      discovery.handleAnnouncement(
        announcement(id: 'peer-2', alias: 'Carol'),
        sourceIp: '192.168.1.21',
      );

      expect(discovery.peers.map((p) => p.id), ['peer-1', 'peer-2']);
      expect(notifications, 2);
    });

    test('ignores our own echoed announce', () {
      discovery.handleAnnouncement(
        announcement(id: 'me'),
        sourceIp: '127.0.0.1',
      );

      expect(discovery.peers, isEmpty);
      expect(notifications, 0);
      expect(announcedBatches, isEmpty);
    });

    test('ignores packets that are not announcements', () {
      discovery.handleAnnouncement({
        'type': 'something-else',
        'id': 'peer-9',
      }, sourceIp: '192.168.1.20');

      expect(discovery.peers, isEmpty);
      expect(notifications, 0);
    });

    test('a payload missing fields throws for the socket layer to swallow', () {
      expect(
        () => discovery.handleAnnouncement({
          'type': 'announce',
          'id': 'peer-9',
        }, sourceIp: '192.168.1.20'),
        throwsA(anything),
      );
      expect(discovery.peers, isEmpty);
    });

    test('the peers list is unmodifiable', () {
      discovery.handleAnnouncement(announcement(), sourceIp: '192.168.1.20');

      expect(() => discovery.peers.add(testPeer()), throwsUnsupportedError);
    });

    test('the cached peers list is refreshed after each change', () {
      discovery.handleAnnouncement(announcement(), sourceIp: '192.168.1.20');
      final first = discovery.peers;

      discovery.handleAnnouncement(
        announcement(id: 'peer-2'),
        sourceIp: '192.168.1.21',
      );

      expect(first, hasLength(1));
      expect(discovery.peers, hasLength(2));
    });
  });

  group('buildAnnouncement', () {
    test(
      'carries the identity, the live service port and the photo version',
      () {
        var port = 4242;
        final discovery = DiscoveryService(
          identity: loadedIdentity(id: 'me', alias: 'Mon poste'),
          servicePort: () => port,
          avatarVersion: () => 'v7',
        );
        addTearDown(discovery.dispose);

        expect(discovery.buildAnnouncement(), {
          'type': 'announce',
          'id': 'me',
          'alias': 'Mon poste',
          'platform': isNotEmpty,
          'port': 4242,
          'avatarVersion': 'v7',
        });

        port = 9999;
        expect(discovery.buildAnnouncement()['port'], 9999);
      },
    );

    test('omits the photo version when this device has no photo', () {
      final discovery = DiscoveryService(
        identity: loadedIdentity(),
        servicePort: () => 1,
        avatarVersion: () => null,
      );
      addTearDown(discovery.dispose);

      expect(
        discovery.buildAnnouncement().containsKey('avatarVersion'),
        isFalse,
      );
    });
  });

  group('socket lifecycle', () {
    test('start binds the discovery port and dispose releases it', () async {
      final discovery = DiscoveryService(
        identity: loadedIdentity(),
        servicePort: () => 1,
        avatarVersion: () => null,
      );

      await discovery.start();
      discovery.dispose();

      final second = DiscoveryService(
        identity: loadedIdentity(),
        servicePort: () => 1,
        avatarVersion: () => null,
      );
      await second.start();
      second.dispose();
    });

    test('announces on the group once the identity is ready', () async {
      useInMemoryPreferences();
      final identity = DeviceIdentityService();
      await identity.load();

      final discovery = DiscoveryService(
        identity: identity,
        servicePort: () => 4242,
        avatarVersion: () => 'v1',
      );

      await discovery.start();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      discovery.dispose();
    });

    test('stays quiet until the identity has loaded', () async {
      final discovery = DiscoveryService(
        identity: loadedIdentity(),
        servicePort: () => 4242,
        avatarVersion: () => null,
      );

      await discovery.start();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      discovery.dispose();

      expect(discovery.peers, isEmpty);
    });
  });
}
