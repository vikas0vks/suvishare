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
  static const _notificationUpdateInterval = Duration(seconds: 1);
  static bool _initialised = false;
  static int _refCount = 0;
  static final Stopwatch _notificationClock = Stopwatch()..start();
  static int _lastNotificationUpdateMs =
      -_notificationUpdateInterval.inMilliseconds;
  static String? _lastNotificationTitle;
  static String? _lastNotificationBody;
  static bool _notificationUpdateInFlight = false;

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
    // Record the initial state before the first platform-channel await. Session
    // progress can arrive while the service is still starting; without this,
    // every early update races a second notification write.
    _lastNotificationTitle = title;
    _lastNotificationBody = body;
    _lastNotificationUpdateMs = _notificationClock.elapsedMilliseconds;
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
    final nowMs = _notificationClock.elapsedMilliseconds;
    final unchanged =
        title == _lastNotificationTitle && body == _lastNotificationBody;
    final tooSoon =
        nowMs - _lastNotificationUpdateMs <
        _notificationUpdateInterval.inMilliseconds;
    if (unchanged || tooSoon || _notificationUpdateInFlight) return;

    // Android rate-limits notification enqueues. Transfer progress is emitted
    // several times per second for a smooth in-app UI, but a once-per-second
    // system notification is enough and avoids repeated SharedPreferences
    // fsyncs in flutter_foreground_task while the hot byte path is active.
    _lastNotificationTitle = title;
    _lastNotificationBody = body;
    _lastNotificationUpdateMs = nowMs;
    _notificationUpdateInFlight = true;
    try {
      await FlutterForegroundTask.updateService(
        notificationTitle: title,
        notificationText: body,
      );
    } catch (_) {
      // A later progress event may retry after the throttle interval.
    } finally {
      _notificationUpdateInFlight = false;
    }
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
    } finally {
      _lastNotificationTitle = null;
      _lastNotificationBody = null;
      _lastNotificationUpdateMs =
          -_notificationUpdateInterval.inMilliseconds;
      _notificationUpdateInFlight = false;
    }
  }
}
