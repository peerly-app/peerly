class Peer {
  final String id;
  final String alias;
  final String platform;
  final String ip;
  final int port;
  final DateTime lastSeen;

  final String? avatarVersion;

  Peer({
    required this.id,
    required this.alias,
    required this.platform,
    required this.ip,
    required this.port,
    required this.lastSeen,
    this.avatarVersion,
  });

  Peer copyWith({
    String? alias,
    String? platform,
    String? ip,
    int? port,
    DateTime? lastSeen,
    String? avatarVersion,
  }) {
    return Peer(
      id: id,
      alias: alias ?? this.alias,
      platform: platform ?? this.platform,
      ip: ip ?? this.ip,
      port: port ?? this.port,
      lastSeen: lastSeen ?? this.lastSeen,
      avatarVersion: avatarVersion ?? this.avatarVersion,
    );
  }

  Uri _uri(String path) =>
      Uri(scheme: 'http', host: ip, port: port, path: path);

  Uri messageUri() => _uri('/message');

  Uri requestUri() => _uri('/request');

  Uri requestResponseUri() => _uri('/request-response');

  Uri avatarUri() => _uri('/avatar');

  Uri audioUri(String messageId) => _uri('/audio/$messageId');

  Uri fileUri(String messageId) => _uri('/file/$messageId');

  bool hasSameAdvertisement(Peer other) =>
      id == other.id &&
      alias == other.alias &&
      platform == other.platform &&
      ip == other.ip &&
      port == other.port &&
      avatarVersion == other.avatarVersion;

  @override
  bool operator ==(Object other) =>
      other is Peer &&
      hasSameAdvertisement(other) &&
      lastSeen == other.lastSeen;

  @override
  int get hashCode =>
      Object.hash(id, alias, platform, ip, port, lastSeen, avatarVersion);
}
