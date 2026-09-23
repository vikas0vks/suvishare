import 'package:meta/meta.dart';

import '../models/device_info.dart';

/// How we learned about a peer.
enum DiscoverySource { multicast, register, mdns, scan, manual, favorite }

/// A peer on the LAN: device info + where to reach it.
@immutable
class Peer {
  const Peer({
    required this.info,
    required this.ip,
    required this.lastSeen,
    required this.source,
    this.verifiedFingerprint,
  });

  final DeviceInfo info;
  final String ip;
  final DateTime lastSeen;
  final DiscoverySource source;

  /// SHA-256 of the certificate we actually saw on a TLS connection, if any.
  final String? verifiedFingerprint;

  String get fingerprint => info.fingerprint;
  String get alias => info.alias;
  int get port => info.port;
  String get baseUrl => '${info.protocol.name}://$ip:$port';

  Peer copyWith({
    DeviceInfo? info,
    String? ip,
    DateTime? lastSeen,
    DiscoverySource? source,
    String? verifiedFingerprint,
  }) => Peer(
    info: info ?? this.info,
    ip: ip ?? this.ip,
    lastSeen: lastSeen ?? this.lastSeen,
    source: source ?? this.source,
    verifiedFingerprint: verifiedFingerprint ?? this.verifiedFingerprint,
  );

  @override
  bool operator ==(Object other) =>
      other is Peer && other.fingerprint == fingerprint && other.ip == ip;

  @override
  int get hashCode => Object.hash(fingerprint, ip);

  @override
  String toString() => 'Peer(${info.alias} @ $ip:${info.port}, $source)';
}
