import 'dart:async';

import 'package:logging/logging.dart';

import '../client/peer_client.dart';
import '../constants.dart';
import '../models/device_info.dart';
import 'multicast_discovery.dart';
import 'peer.dart';
import 'peer_registry.dart';
import 'subnet_scanner.dart';

/// Orchestrates every discovery layer and feeds a [PeerRegistry]:
///
/// 1. UDP multicast announce/listen; on sighting → TCP `register` reply.
/// 2. Incoming `register` calls from the server (via [onRegisterReceived]).
/// 3. On-demand subnet scan.
/// 4. Manual address entry.
///
/// mDNS is plugged in by the app layer (platform plugin) through [addSighting].
class DiscoveryService {
  DiscoveryService({
    required DeviceInfo Function() selfInfo,
    required PeerClient client,
    PeerRegistry? registry,
    int? multicastPort,
  }) : _selfInfo = selfInfo,
       _client = client,
       registry = registry ?? PeerRegistry(),
       _multicast = MulticastDiscovery(
         selfInfo: selfInfo,
         port: multicastPort ?? SuviConstants.defaultPort,
       ) {
    _scanner = SubnetScanner(_client);
  }

  static final _log = Logger('suvi.discovery');

  final DeviceInfo Function() _selfInfo;
  final PeerClient _client;
  final PeerRegistry registry;
  final MulticastDiscovery _multicast;
  late final SubnetScanner _scanner;

  StreamSubscription<MulticastSighting>? _sub;
  Timer? _activeTimer;
  bool _scanning = false;
  final _scanProgress = StreamController<(int, int)>.broadcast();

  bool get isScanning => _scanning;
  Stream<(int, int)> get scanProgress => _scanProgress.stream;

  Future<void> start() async {
    registry.start();
    _sub ??= _multicast.sightings.listen(_onSighting);
    await _multicast.start();
    // Announce quickly for 30 s, then relax.
    _activeTimer?.cancel();
    _activeTimer = Timer(const Duration(seconds: 30), () {
      _multicast.setAnnounceInterval(SuviConstants.announceIntervalIdle);
    });
  }

  /// Re-announce aggressively (user pulled to refresh / network changed).
  Future<void> refresh() async {
    if (!_multicast.isRunning) {
      await start();
      return;
    }
    _multicast.setAnnounceInterval(SuviConstants.announceIntervalActive);
    await _multicast.announce();
    _activeTimer?.cancel();
    _activeTimer = Timer(const Duration(seconds: 30), () {
      _multicast.setAnnounceInterval(SuviConstants.announceIntervalIdle);
    });
  }

  /// Restart sockets (after the local IP / interfaces changed).
  Future<void> restart() async {
    await _multicast.stop();
    await start();
  }

  Future<void> _onSighting(MulticastSighting s) async {
    // Record immediately so the UI is snappy, then confirm over TCP.
    registry.upsert(s.info, s.ip, DiscoverySource.multicast);
    if (s.info.announce == true) {
      final theirs = await _client.register(
        s.ip,
        s.info.port,
        protocol: s.info.protocol,
      );
      if (theirs != null) {
        registry.upsert(
          theirs,
          s.ip,
          DiscoverySource.register,
          verifiedFingerprint: _client.observedFingerprint(s.ip),
        );
      } else {
        // TCP path failed (firewall?) — fall back to a UDP reply.
        await _multicast.replyTo(s.ip);
      }
    }
  }

  /// Called by the HTTPS server when a peer registers with us.
  void onRegisterReceived(DeviceInfo info, String ip) {
    if (info.fingerprint == _selfInfo().fingerprint) return;
    registry.upsert(info, ip, DiscoverySource.register);
  }

  /// mDNS or other external source.
  void addSighting(DeviceInfo info, String ip, DiscoverySource source) {
    if (info.fingerprint == _selfInfo().fingerprint) return;
    registry.upsert(info, ip, source);
  }

  /// Manual `ip[:port]` entry. Returns the peer if reachable.
  Future<Peer?> addManual(String address, {int? defaultPort}) async {
    var ip = address.trim();
    var port = defaultPort ?? SuviConstants.defaultPort;
    final idx = ip.lastIndexOf(':');
    if (idx > 0 && !ip.contains(']')) {
      port = int.tryParse(ip.substring(idx + 1)) ?? port;
      ip = ip.substring(0, idx);
    }
    for (final proto in [PeerProtocol.https, PeerProtocol.http]) {
      final info = await _client.register(ip, port, protocol: proto);
      if (info != null) {
        registry.upsert(
          info,
          ip,
          DiscoverySource.manual,
          verifiedFingerprint: _client.observedFingerprint(ip),
        );
        return registry.byFingerprint(info.fingerprint);
      }
    }
    return null;
  }

  /// Sweeps local /24 subnets. Safe to call repeatedly; ignored if running.
  Future<void> scanSubnet({int? port}) async {
    if (_scanning) return;
    _scanning = true;
    try {
      final p = port ?? _selfInfo().port;
      await for (final hit in _scanner.scan(
        port: p,
        onProgress: (d, t) => _scanProgress.add((d, t)),
      )) {
        if (hit.info.fingerprint == _selfInfo().fingerprint) continue;
        registry.upsert(
          hit.info,
          hit.ip,
          DiscoverySource.scan,
          verifiedFingerprint: _client.observedFingerprint(hit.ip),
        );
      }
    } catch (e) {
      _log.warning('scan failed: $e');
    } finally {
      _scanning = false;
    }
  }

  Future<void> stop() async {
    _activeTimer?.cancel();
    await _multicast.stop();
  }

  Future<void> dispose() async {
    await stop();
    await _sub?.cancel();
    await _multicast.dispose();
    await _scanProgress.close();
    await registry.dispose();
  }
}
