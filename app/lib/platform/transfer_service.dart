import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:logging/logging.dart';

import 'multicast_lock.dart';

/// Keeps the process alive on Android while a transfer is in flight.
///
/// Android 14+ requires a declared `foregroundServiceType`; ours is `dataSync`
/// (see AndroidManifest.xml). Without this, the OS freezes cached apps and a
/// long transfer dies the moment the user switches away — the single most
/// common "it stopped at 40%" complaint about apps of this kind.
///
/// No-op on every other platform.
class TransferForegroundService {
  static final _log = Logger('suvi.fgservice');
  static bool _initialised = false;
  static int _refCount = 0;

  static bool get _supported => Platform.isAndroid;

  static void init() {
    if (!_supported || _initialised) return;
    _initialised = true;
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'suvi_transfers',
        channelName: 'File transfers',
        channelDescription: 'Shown while Suvi Share is sending or receiving.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  /// Starts (or reuses) the service. Balance every call with [release].
  static Future<void> acquire({
    required String title,
    required String body,
  }) async {
    if (!_supported) return;
    init();
    _refCount++;
    // Keep Wi-Fi at full performance for the duration of the transfer.
    await WifiPerfLock.acquire();
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
          notificationTitle: title,
          notificationText: body,
        );
      } else {
        await FlutterForegroundTask.startService(
          notificationTitle: title,
          notificationText: body,
        );
      }
    } catch (e) {
      _log.warning('foreground service start failed: $e');
    }
  }

  /// Updates the notification text of a running service (progress).
  static Future<void> update({
    required String title,
    required String body,
  }) async {
    if (!_supported || _refCount == 0) return;
    try {
      await FlutterForegroundTask.updateService(
        notificationTitle: title,
        notificationText: body,
      );
    } catch (_) {}
  }

  /// Stops the service once every acquirer has released it.
  static Future<void> release() async {
    if (!_supported) return;
    await WifiPerfLock.release();
    if (_refCount > 0) _refCount--;
    if (_refCount > 0) return;
    try {
      await FlutterForegroundTask.stopService();
    } catch (e) {
      _log.fine('foreground service stop failed: $e');
    }
  }
}
