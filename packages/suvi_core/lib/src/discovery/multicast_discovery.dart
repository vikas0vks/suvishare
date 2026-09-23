import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';

import '../constants.dart';
import '../models/device_info.dart';

/// A UDP datagram we heard from another device.
class MulticastSighting {
  const MulticastSighting({required this.info, required this.ip});
  final DeviceInfo info;
  final String ip;
}

/// Sends and receives Suvi/LocalSend-style UDP multicast announcements.
///
/// Binds one socket per local interface (so multi-homed desktops work) and
/// joins the multicast group. Emits [MulticastSighting]s for every packet
/// whose fingerprint is not our own.
class MulticastDiscovery {
  MulticastDiscovery({
    required DeviceInfo Function() selfInfo,
    String group = SuviConstants.multicastGroup,
    int port = SuviConstants.defaultPort,
  }) : _selfInfo = selfInfo,
       _group = InternetAddress(group),
       _port = port;

  static final _log = Logger('suvi.multicast');

  final DeviceInfo Function() _selfInfo;
  final InternetAddress _group;
  final int _port;

  final List<RawDatagramSocket> _sockets = [];
  final StreamController<MulticastSighting> _sightings =
      StreamController.broadcast();
  Timer? _announceTimer;
  bool _running = false;

  Stream<MulticastSighting> get sightings => _sightings.stream;
  bool get isRunning => _running;

  /// Starts listening and announcing.
  Future<void> start({
    Duration announceInterval = SuviConstants.announceIntervalActive,
  }) async {
    if (_running) return;
    _running = true;
    await _bindSockets();
    await announce();
    _announceTimer = Timer.periodic(announceInterval, (_) => announce());
  }

  /// Changes the announce cadence (e.g. idle vs active discovery).
  void setAnnounceInterval(Duration interval) {
    if (!_running) return;
    _announceTimer?.cancel();
    _announceTimer = Timer.periodic(interval, (_) => announce());
  }

  Future<void> _bindSockets() async {
    List<NetworkInterface> ifaces = const [];
    try {
      ifaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
    } catch (e) {
      _log.warning('NetworkInterface.list failed: $e');
    }

    // One "any" socket is the baseline; it receives on most platforms.
    await _bindOne(InternetAddress.anyIPv4, null);
    // Additionally join the group on each interface for multi-NIC hosts.
    for (final iface in ifaces) {
      try {
        final s = _sockets.first;
        s.joinMulticast(_group, iface);
      } catch (e) {
        _log.fine('joinMulticast on ${iface.name} failed: $e');
      }
    }
  }

  Future<void> _bindOne(
    InternetAddress address,
    NetworkInterface? iface,
  ) async {
    try {
      final socket = await RawDatagramSocket.bind(
        address,
        _port,
        reuseAddress: true,
        // Android's Dart socket implementation rejects SO_REUSEPORT even
        // though the kernel is Linux-based. A rejected option aborts the bind
        // and silently disables discovery, so only enable it on platforms
        // where the Dart VM exposes support.
        reusePort: Platform.isLinux || Platform.isMacOS || Platform.isIOS,
        ttl: 1,
      );
      socket.broadcastEnabled = true;
      socket.multicastLoopback = true;
      try {
        socket.joinMulticast(_group, iface);
      } catch (e) {
        _log.fine('joinMulticast failed: $e');
      }
      socket.listen(
        _onEvent(socket),
        onError: (Object e) {
          _log.warning('multicast socket error: $e');
        },
      );
      _sockets.add(socket);
      _log.fine('multicast bound on ${address.address}:$_port');
    } catch (e) {
      _log.warning('bind ${address.address}:$_port failed: $e');
    }
  }

  void Function(RawSocketEvent) _onEvent(RawDatagramSocket socket) {
    return (event) {
      if (event != RawSocketEvent.read) return;
      final dg = socket.receive();
      if (dg == null) return;
      _handleDatagram(dg);
    };
  }

  void _handleDatagram(Datagram dg) {
    Object? json;
    try {
      json = jsonDecode(utf8.decode(dg.data));
    } catch (_) {
      return;
    }
    final info = DeviceInfo.tryParse(json);
    if (info == null) return;
    if (info.fingerprint == _selfInfo().fingerprint) return;
    _sightings.add(MulticastSighting(info: info, ip: dg.address.address));
  }

  /// Sends one announcement (`announce: true`) to the group.
  Future<void> announce() => _send(_selfInfo().copyWith(announce: true));

  /// Replies over UDP (`announce: false`) — used only when the TCP register
  /// path fails.
  Future<void> replyTo(String ip) async {
    final bytes = utf8.encode(
      jsonEncode(_selfInfo().copyWith(announce: false).toJson()),
    );
    for (final s in _sockets) {
      try {
        s.send(bytes, InternetAddress(ip), _port);
      } catch (_) {}
    }
  }

  Future<void> _send(DeviceInfo info) async {
    if (!_running || _sockets.isEmpty) return;
    final bytes = utf8.encode(jsonEncode(info.toJson()));
    for (final s in _sockets) {
      try {
        s.send(bytes, _group, _port);
      } catch (e) {
        _log.fine('send failed: $e');
      }
    }
  }

  Future<void> stop() async {
    _running = false;
    _announceTimer?.cancel();
    _announceTimer = null;
    for (final s in _sockets) {
      try {
        s.close();
      } catch (_) {}
    }
    _sockets.clear();
  }

  Future<void> dispose() async {
    await stop();
    await _sightings.close();
  }
}
