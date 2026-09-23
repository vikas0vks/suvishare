import 'dart:io';

import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

/// Android `WifiManager.MulticastLock` — without it most Wi-Fi drivers drop
/// multicast packets and discovery never sees other devices. No-op elsewhere.
class MulticastLock {
  static const _channel = MethodChannel('com.suvishare/multicast_lock');
  static final _log = Logger('suvi.multicastlock');
  bool _held = false;

  bool get isHeld => _held;

  Future<void> acquire() async {
    if (!Platform.isAndroid || _held) return;
    try {
      await _channel.invokeMethod<void>('acquire');
      _held = true;
    } on MissingPluginException {
      _log.fine('multicast lock channel not registered');
    } catch (e) {
      _log.warning('acquire failed: $e');
    }
  }

  Future<void> release() async {
    if (!Platform.isAndroid || !_held) return;
    try {
      await _channel.invokeMethod<void>('release');
    } catch (_) {}
    _held = false;
  }
}

/// Android high-performance Wi-Fi lock. Held only while a transfer is running,
/// so the Wi-Fi radio stays out of power-save and throughput doesn't collapse.
/// Reference-counted here so overlapping send + receive both work.
class WifiPerfLock {
  static const _channel = MethodChannel('com.suvishare/multicast_lock');
  static final _log = Logger('suvi.wifilock');
  static int _refs = 0;

  static Future<void> acquire() async {
    if (!Platform.isAndroid) return;
    _refs++;
    if (_refs != 1) return;
    try {
      await _channel.invokeMethod<void>('acquireWifi');
    } on MissingPluginException {
      // ignore
    } catch (e) {
      _log.fine('wifi lock acquire failed: $e');
    }
  }

  static Future<void> release() async {
    if (!Platform.isAndroid) return;
    if (_refs > 0) _refs--;
    if (_refs != 0) return;
    try {
      await _channel.invokeMethod<void>('releaseWifi');
    } catch (_) {}
  }
}
