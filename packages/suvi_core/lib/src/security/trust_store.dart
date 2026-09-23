import 'dart:async';

import 'package:meta/meta.dart';

/// How much we trust a peer.
enum TrustLevel {
  /// Never paired; every transfer needs explicit accept.
  unknown,

  /// Paired & certificate pinned; may auto-accept if the user enabled it.
  trusted,

  /// Was trusted, but its certificate changed — re-pair required.
  mismatch,

  /// User explicitly blocked this device.
  blocked,
}

@immutable
class TrustedDevice {
  const TrustedDevice({
    required this.fingerprint,
    required this.alias,
    required this.pairedAt,
    this.autoAccept = false,
    this.favorite = false,
    this.lastIp,
    this.blocked = false,
  });

  final String fingerprint;
  final String alias;
  final DateTime pairedAt;
  final bool autoAccept;
  final bool favorite;
  final String? lastIp;
  final bool blocked;

  TrustedDevice copyWith({
    String? alias,
    bool? autoAccept,
    bool? favorite,
    String? lastIp,
    bool? blocked,
  }) => TrustedDevice(
    fingerprint: fingerprint,
    alias: alias ?? this.alias,
    pairedAt: pairedAt,
    autoAccept: autoAccept ?? this.autoAccept,
    favorite: favorite ?? this.favorite,
    lastIp: lastIp ?? this.lastIp,
    blocked: blocked ?? this.blocked,
  );

  Map<String, dynamic> toJson() => {
    'fingerprint': fingerprint,
    'alias': alias,
    'pairedAt': pairedAt.toUtc().toIso8601String(),
    'autoAccept': autoAccept,
    'favorite': favorite,
    'lastIp': lastIp,
    'blocked': blocked,
  };

  static TrustedDevice? tryParse(Object? json) {
    if (json is! Map) return null;
    final fp = json['fingerprint'];
    final alias = json['alias'];
    if (fp is! String || alias is! String) return null;
    return TrustedDevice(
      fingerprint: fp,
      alias: alias,
      pairedAt:
          DateTime.tryParse(json['pairedAt'] as String? ?? '') ??
          DateTime.now(),
      autoAccept: json['autoAccept'] == true,
      favorite: json['favorite'] == true,
      lastIp: json['lastIp'] as String?,
      blocked: json['blocked'] == true,
    );
  }
}

/// In-memory trust list with a persistence hook. The app supplies
/// [persist] (e.g. write JSON to disk) and seeds via [load].
class TrustStore {
  TrustStore({Future<void> Function(List<TrustedDevice>)? persist})
    : _persist = persist;

  final Future<void> Function(List<TrustedDevice>)? _persist;
  final Map<String, TrustedDevice> _devices = {};
  final StreamController<List<TrustedDevice>> _updates =
      StreamController.broadcast();

  Stream<List<TrustedDevice>> get updates => _updates.stream;
  List<TrustedDevice> get all => _devices.values.toList()
    ..sort((a, b) => a.alias.toLowerCase().compareTo(b.alias.toLowerCase()));

  void load(Iterable<TrustedDevice> devices) {
    _devices
      ..clear()
      ..addEntries(devices.map((d) => MapEntry(d.fingerprint, d)));
    _emit();
  }

  TrustedDevice? get(String fingerprint) => _devices[fingerprint];
  bool isTrusted(String fp) => _devices[fp] != null && !_devices[fp]!.blocked;
  bool isBlocked(String fp) => _devices[fp]?.blocked == true;
  bool autoAccepts(String fp) =>
      _devices[fp]?.autoAccept == true && !_devices[fp]!.blocked;

  TrustLevel levelFor(String advertisedFp, {String? observedFp}) {
    final d = _devices[advertisedFp];
    if (d == null) return TrustLevel.unknown;
    if (d.blocked) return TrustLevel.blocked;
    if (observedFp != null && observedFp != advertisedFp) {
      return TrustLevel.mismatch;
    }
    return TrustLevel.trusted;
  }

  Future<void> trust(String fingerprint, String alias, {String? ip}) async {
    final existing = _devices[fingerprint];
    _devices[fingerprint] =
        (existing ??
                TrustedDevice(
                  fingerprint: fingerprint,
                  alias: alias,
                  pairedAt: DateTime.now(),
                ))
            .copyWith(alias: alias, lastIp: ip, blocked: false);
    await _save();
  }

  Future<void> update(
    String fingerprint,
    TrustedDevice Function(TrustedDevice) fn,
  ) async {
    final d = _devices[fingerprint];
    if (d == null) return;
    _devices[fingerprint] = fn(d);
    await _save();
  }

  Future<void> remove(String fingerprint) async {
    if (_devices.remove(fingerprint) != null) await _save();
  }

  Future<void> block(String fingerprint, String alias) async {
    final existing =
        _devices[fingerprint] ??
        TrustedDevice(
          fingerprint: fingerprint,
          alias: alias,
          pairedAt: DateTime.now(),
        );
    _devices[fingerprint] = existing.copyWith(blocked: true, autoAccept: false);
    await _save();
  }

  Future<void> _save() async {
    _emit();
    await _persist?.call(all);
  }

  void _emit() {
    if (!_updates.isClosed) _updates.add(all);
  }

  Future<void> dispose() => _updates.close();
}
