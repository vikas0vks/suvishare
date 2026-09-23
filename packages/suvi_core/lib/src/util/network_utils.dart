import 'dart:io';

/// One usable LAN address on this machine.
class LocalAddress {
  const LocalAddress({
    required this.interfaceName,
    required this.address,
    this.prefixLength = 24,
  });

  final String interfaceName;
  final InternetAddress address;

  /// Dart does not expose the netmask; we assume /24 (documented limitation,
  /// same as LocalSend). Subnet scanning is only attempted for /24.
  final int prefixLength;

  String get ip => address.address;

  /// All other host addresses in the /24 of this address.
  Iterable<String> subnetHosts() sync* {
    final parts = address.address.split('.');
    if (parts.length != 4) return;
    final base = '${parts[0]}.${parts[1]}.${parts[2]}.';
    final self = int.tryParse(parts[3]);
    for (var i = 1; i < 255; i++) {
      if (i == self) continue;
      yield '$base$i';
    }
  }

  @override
  String toString() => '$interfaceName $ip/$prefixLength';
}

class NetworkUtils {
  NetworkUtils._();

  /// Heuristic ordering: prefer Wi-Fi/Ethernet style names, deprioritise
  /// virtual adapters (VPN, Docker, VirtualBox, Hyper-V…).
  static const List<String> _virtualHints = [
    'docker',
    'vmware',
    'virtualbox',
    'vbox',
    'hyper-v',
    'vethernet',
    'tap',
    'tun',
    'wireguard',
    'wg',
    'zerotier',
    'tailscale',
    'hamachi',
    'loopback',
    'bluetooth',
    'vpn',
    'br-',
    'veth',
    'virbr',
  ];

  static bool isPrivateIPv4(InternetAddress a) {
    if (a.type != InternetAddressType.IPv4) return false;
    final b = a.rawAddress;
    if (b[0] == 10) return true;
    if (b[0] == 172 && b[1] >= 16 && b[1] <= 31) return true;
    if (b[0] == 192 && b[1] == 168) return true;
    if (b[0] == 169 && b[1] == 254) return true; // link-local
    if (b[0] == 100 && b[1] >= 64 && b[1] <= 127) {
      return true; // CGNAT (hotspots)
    }
    return false;
  }

  /// Whether an inbound peer address belongs to a network Suvi Share is
  /// designed to serve. Loopback is included for local tests and tooling.
  static bool isAllowedPeerIp(String value) {
    final address = InternetAddress.tryParse(value);
    if (address == null) return false;
    if (address.isLoopback) return true;
    if (address.type == InternetAddressType.IPv4) {
      return isPrivateIPv4(address);
    }
    final bytes = address.rawAddress;
    // IPv6 link-local fe80::/10 and unique-local fc00::/7.
    return (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80) ||
        (bytes[0] & 0xfe) == 0xfc;
  }

  static bool looksVirtual(String name) {
    final n = name.toLowerCase();
    return _virtualHints.any(n.contains);
  }

  /// Lists private IPv4 addresses, physical-looking interfaces first.
  static Future<List<LocalAddress>> localAddresses({
    bool includeVirtual = false,
  }) async {
    final result = <LocalAddress>[];
    List<NetworkInterface> ifaces;
    try {
      ifaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: true,
        type: InternetAddressType.IPv4,
      );
    } catch (_) {
      return result;
    }
    for (final iface in ifaces) {
      final virtual = looksVirtual(iface.name);
      if (virtual && !includeVirtual) continue;
      for (final addr in iface.addresses) {
        if (!isPrivateIPv4(addr)) continue;
        result.add(LocalAddress(interfaceName: iface.name, address: addr));
      }
    }
    result.sort((a, b) {
      final av = looksVirtual(a.interfaceName) ? 1 : 0;
      final bv = looksVirtual(b.interfaceName) ? 1 : 0;
      if (av != bv) return av - bv;
      // Prefer 192.168.x and 10.x (typical home) over link-local.
      int score(LocalAddress l) {
        final b = l.address.rawAddress;
        if (b[0] == 169) return 3;
        if (b[0] == 100) return 2;
        return 0;
      }

      return score(a) - score(b);
    });
    return result;
  }

  /// Best-guess primary LAN IP (or null if offline).
  static Future<String?> primaryIp() async {
    final list = await localAddresses();
    return list.isEmpty ? null : list.first.ip;
  }
}
