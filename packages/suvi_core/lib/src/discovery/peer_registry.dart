import 'dart:async';

import '../constants.dart';
import '../models/device_info.dart';
import 'peer.dart';

/// In-memory table of known peers keyed by fingerprint, with TTL expiry.
class PeerRegistry {
  PeerRegistry({Duration? ttl}) : _ttl = ttl ?? SuviConstants.peerTtl;

  final Duration _ttl;
  final Map<String, Peer> _peers = {};
  final StreamController<List<Peer>> _controller =
      StreamController<List<Peer>>.broadcast();
  Timer? _sweeper;

  Stream<List<Peer>> get stream => _controller.stream;
  List<Peer> get peers => _sorted();
  Peer? byFingerprint(String fp) => _peers[fp];

  void start() {
    _sweeper ??= Timer.periodic(const Duration(seconds: 10), (_) => _sweep());
  }

  /// Adds or refreshes a peer. Returns `true` if it is new or changed.
  ///
  /// Devices we can never connect back to (browser clients advertising
  /// `port: 0`) are ignored — showing them as send targets would only produce
  /// a connection error.
  bool upsert(
    DeviceInfo info,
    String ip,
    DiscoverySource source, {
    String? verifiedFingerprint,
  }) {
    if (!info.isReachable) return false;
    final now = DateTime.now();
    final existing = _peers[info.fingerprint];
    final next = Peer(
      info: info.copyWith(clearAnnounce: true),
      ip: ip,
      lastSeen: now,
      // Keep the "strongest" source: manual/favorite > register > others.
      source: existing == null ? source : _strongest(existing.source, source),
      verifiedFingerprint: verifiedFingerprint ?? existing?.verifiedFingerprint,
    );
    final changed =
        existing == null ||
        existing.info != next.info ||
        existing.ip != next.ip ||
        existing.verifiedFingerprint != next.verifiedFingerprint;
    _peers[info.fingerprint] = next;
    if (changed) _emit();
    return changed;
  }

  void remove(String fingerprint) {
    if (_peers.remove(fingerprint) != null) _emit();
  }

  void clear() {
    if (_peers.isNotEmpty) {
      _peers.clear();
      _emit();
    }
  }

  void _sweep() {
    final now = DateTime.now();
    final expired = _peers.values
        .where(
          (p) =>
              p.source != DiscoverySource.manual &&
              p.source != DiscoverySource.favorite &&
              now.difference(p.lastSeen) > _ttl,
        )
        .map((p) => p.fingerprint)
        .toList();
    if (expired.isEmpty) return;
    expired.forEach(_peers.remove);
    _emit();
  }

  static DiscoverySource _strongest(DiscoverySource a, DiscoverySource b) {
    int rank(DiscoverySource s) => switch (s) {
      DiscoverySource.favorite => 5,
      DiscoverySource.manual => 4,
      DiscoverySource.register => 3,
      DiscoverySource.mdns => 2,
      DiscoverySource.multicast => 1,
      DiscoverySource.scan => 1,
    };
    return rank(a) >= rank(b) ? a : b;
  }

  List<Peer> _sorted() {
    final list = _peers.values.toList();
    list.sort((a, b) => a.alias.toLowerCase().compareTo(b.alias.toLowerCase()));
    return list;
  }

  void _emit() {
    if (!_controller.isClosed) _controller.add(_sorted());
  }

  Future<void> dispose() async {
    _sweeper?.cancel();
    _sweeper = null;
    await _controller.close();
  }
}
