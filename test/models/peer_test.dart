import 'package:flutter_test/flutter_test.dart';
import 'package:peero/models/peer.dart';

Peer buildPeer({
  String id = 'peer-1',
  String alias = 'Bob',
  String platform = 'linux',
  String ip = '192.168.1.20',
  int port = 5000,
  DateTime? lastSeen,
  String? avatarVersion,
}) {
  return Peer(
    id: id,
    alias: alias,
    platform: platform,
    ip: ip,
    port: port,
    lastSeen: lastSeen ?? DateTime(2026, 1, 1, 12),
    avatarVersion: avatarVersion,
  );
}

void main() {
  group('endpoint URIs', () {
    final peer = buildPeer(ip: '10.0.0.7', port: 8080);

    test('all point at the peer\'s host and port over http', () {
      for (final uri in [
        peer.messageUri(),
        peer.requestUri(),
        peer.requestResponseUri(),
        peer.avatarUri(),
        peer.audioUri('m1'),
        peer.fileUri('m1'),
      ]) {
        expect(uri.scheme, 'http');
        expect(uri.host, '10.0.0.7');
        expect(uri.port, 8080);
      }
    });

    test('each targets its own path', () {
      expect(peer.messageUri().path, '/message');
      expect(peer.requestUri().path, '/request');
      expect(peer.requestResponseUri().path, '/request-response');
      expect(peer.avatarUri().path, '/avatar');
      expect(peer.audioUri('msg-42').path, '/audio/msg-42');
      expect(peer.fileUri('msg-42').path, '/file/msg-42');
    });
  });

  group('copyWith', () {
    test('keeps the id and carries unspecified fields over', () {
      final original = buildPeer();
      final copy = original.copyWith(alias: 'Bobby');

      expect(copy.id, original.id);
      expect(copy.alias, 'Bobby');
      expect(copy.platform, original.platform);
      expect(copy.ip, original.ip);
      expect(copy.port, original.port);
      expect(copy.lastSeen, original.lastSeen);
    });

    test('replaces every field it is given', () {
      final updated = buildPeer().copyWith(
        alias: 'Carol',
        platform: 'android',
        ip: '10.1.1.1',
        port: 9999,
        lastSeen: DateTime(2027),
        avatarVersion: 'v2',
      );

      expect(updated.alias, 'Carol');
      expect(updated.platform, 'android');
      expect(updated.ip, '10.1.1.1');
      expect(updated.port, 9999);
      expect(updated.lastSeen, DateTime(2027));
      expect(updated.avatarVersion, 'v2');
    });
  });

  group('hasSameAdvertisement', () {
    test('ignores lastSeen, which every heartbeat moves', () {
      final first = buildPeer(lastSeen: DateTime(2026, 1, 1, 12));
      final later = buildPeer(lastSeen: DateTime(2026, 1, 1, 12, 0, 3));

      expect(first.hasSameAdvertisement(later), isTrue);
      expect(first == later, isFalse);
    });

    test('catches a change in any advertised field', () {
      final base = buildPeer(avatarVersion: 'v1');

      expect(base.hasSameAdvertisement(base.copyWith(alias: 'Bobby')), isFalse);
      expect(base.hasSameAdvertisement(base.copyWith(ip: '10.0.0.1')), isFalse);
      expect(base.hasSameAdvertisement(base.copyWith(port: 1)), isFalse);
      expect(
        base.hasSameAdvertisement(base.copyWith(platform: 'ios')),
        isFalse,
      );
      expect(
        base.hasSameAdvertisement(base.copyWith(avatarVersion: 'v2')),
        isFalse,
      );
      expect(
        base.hasSameAdvertisement(buildPeer(id: 'other', avatarVersion: 'v1')),
        isFalse,
      );
    });

    test('a peer that gains a photo no longer matches its previous self', () {
      final without = buildPeer();
      final with_ = buildPeer(avatarVersion: 'v1');
      expect(without.hasSameAdvertisement(with_), isFalse);
    });
  });

  group('equality', () {
    test('two peers with identical fields are equal and hash alike', () {
      final a = buildPeer(avatarVersion: 'v1');
      final b = buildPeer(avatarVersion: 'v1');

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('differing lastSeen breaks equality', () {
      expect(
        buildPeer(lastSeen: DateTime(2026)),
        isNot(equals(buildPeer(lastSeen: DateTime(2027)))),
      );
    });

    test('is not equal to a non-Peer', () {
      expect(buildPeer() == Object(), isFalse);
    });
  });
}
