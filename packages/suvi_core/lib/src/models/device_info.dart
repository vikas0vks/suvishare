import 'package:meta/meta.dart';

/// Kind of device, as advertised on the network.
enum DeviceType {
  mobile,
  desktop,
  web,
  headless,
  server;

  static DeviceType parse(String? raw) {
    for (final t in DeviceType.values) {
      if (t.name == raw) return t;
    }
    return DeviceType.desktop;
  }
}

/// Transport protocol a peer serves its API over.
enum PeerProtocol {
  https,
  http;

  static PeerProtocol parse(String? raw) =>
      raw == 'http' ? PeerProtocol.http : PeerProtocol.https;
}

/// Device info object exchanged during discovery and in every request.
@immutable
class DeviceInfo {
  const DeviceInfo({
    required this.alias,
    required this.fingerprint,
    required this.port,
    this.version = '1.0',
    this.deviceModel,
    this.deviceType = DeviceType.desktop,
    this.protocol = PeerProtocol.https,
    this.download = false,
    this.announce,
    this.avatarColor = 0,
  });

  final String alias;
  final String version;
  final String? deviceModel;
  final DeviceType deviceType;
  final String fingerprint;
  final int port;
  final PeerProtocol protocol;
  final bool download;

  /// Only meaningful on UDP: `true` = announcement, `false` = reply.
  final bool? announce;

  /// Suvi extension: 0..7 hue index for the avatar.
  final int avatarColor;

  /// Whether this device hosts an API we can connect back to.
  ///
  /// Browser clients advertise `port: 0` — they can send to us but we can
  /// never initiate a connection to them, so they must not appear in the
  /// nearby list as a send target.
  bool get isReachable => port > 0 && deviceType != DeviceType.web;

  DeviceInfo copyWith({
    String? alias,
    String? version,
    String? deviceModel,
    DeviceType? deviceType,
    String? fingerprint,
    int? port,
    PeerProtocol? protocol,
    bool? download,
    bool? announce,
    bool clearAnnounce = false,
    int? avatarColor,
  }) {
    return DeviceInfo(
      alias: alias ?? this.alias,
      version: version ?? this.version,
      deviceModel: deviceModel ?? this.deviceModel,
      deviceType: deviceType ?? this.deviceType,
      fingerprint: fingerprint ?? this.fingerprint,
      port: port ?? this.port,
      protocol: protocol ?? this.protocol,
      download: download ?? this.download,
      announce: clearAnnounce ? null : (announce ?? this.announce),
      avatarColor: avatarColor ?? this.avatarColor,
    );
  }

  Map<String, dynamic> toJson() => {
    'alias': alias,
    'version': version,
    if (deviceModel != null) 'deviceModel': deviceModel,
    'deviceType': deviceType.name,
    'fingerprint': fingerprint,
    'port': port,
    'protocol': protocol.name,
    'download': download,
    if (announce != null) 'announce': announce,
    'avatarColor': avatarColor,
  };

  static DeviceInfo? tryParse(Object? json) {
    if (json is! Map) return null;
    final alias = json['alias'];
    final fingerprint = json['fingerprint'];
    final port = json['port'];
    final version = json['version'];
    final deviceModel = json['deviceModel'];
    final deviceType = json['deviceType'];
    final protocol = json['protocol'];
    final avatarColor = json['avatarColor'];
    if (alias is! String || fingerprint is! String || port is! int) {
      return null;
    }
    // Port 0 is allowed and means "I do not host an API" — browser clients
    // send it. Anything above 65535 is malformed.
    if (alias.trim().isEmpty ||
        alias.length > 128 ||
        fingerprint.isEmpty ||
        fingerprint.length > 256 ||
        port < 0 ||
        port > 65535 ||
        (version != null && (version is! String || version.length > 32)) ||
        (deviceModel != null &&
            (deviceModel is! String || deviceModel.length > 128)) ||
        (deviceType != null && deviceType is! String) ||
        (protocol != null && protocol is! String) ||
        (avatarColor != null && avatarColor is! int) ||
        (json['download'] != null && json['download'] is! bool) ||
        (json['announce'] != null && json['announce'] is! bool)) {
      return null;
    }
    return DeviceInfo(
      alias: alias,
      version: (version as String?) ?? '1.0',
      deviceModel: deviceModel as String?,
      deviceType: DeviceType.parse(deviceType as String?),
      fingerprint: fingerprint,
      port: port,
      protocol: PeerProtocol.parse(protocol as String?),
      download: json['download'] == true,
      announce: json['announce'] is bool ? json['announce'] as bool : null,
      avatarColor: avatarColor is int ? avatarColor.clamp(0, 7) : 0,
    );
  }

  factory DeviceInfo.fromJson(Map<String, dynamic> json) {
    final parsed = tryParse(json);
    if (parsed == null) {
      throw const FormatException('Invalid DeviceInfo');
    }
    return parsed;
  }

  @override
  bool operator ==(Object other) =>
      other is DeviceInfo &&
      other.alias == alias &&
      other.fingerprint == fingerprint &&
      other.port == port &&
      other.protocol == protocol &&
      other.deviceType == deviceType &&
      other.deviceModel == deviceModel &&
      other.download == download &&
      other.avatarColor == avatarColor;

  @override
  int get hashCode => Object.hash(
    alias,
    fingerprint,
    port,
    protocol,
    deviceType,
    deviceModel,
    download,
    avatarColor,
  );

  @override
  String toString() => 'DeviceInfo($alias, $deviceType, $fingerprint, :$port)';
}
