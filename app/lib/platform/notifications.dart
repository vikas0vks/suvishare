import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:logging/logging.dart';
import 'package:window_manager/window_manager.dart';

/// Local notifications for the two moments that matter:
/// an incoming request (so a hidden window / backgrounded phone is never a
/// black hole) and a finished receive. Best-effort on every platform — a
/// notification failure must never affect the transfer itself.
class SuviNotifications {
  SuviNotifications._();

  static final _log = Logger('suvi.notifications');
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static const _channelId = 'suvi_events';

  static Future<void> init() async {
    if (_ready) return;
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const linux = LinuxInitializationSettings(defaultActionName: 'Open');
      const windows = WindowsInitializationSettings(
        appName: 'Suvi Share',
        appUserModelId: 'com.suvishare.suvi_share',
        guid: '7b4e2c10-5f1d-4a6b-9e3c-1d8a2f6b4c90',
      );
      const darwin = DarwinInitializationSettings();
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: android,
          linux: linux,
          windows: windows,
          macOS: darwin,
          iOS: darwin,
        ),
        onDidReceiveNotificationResponse: (_) => _bringToFront(),
      );
      _ready = true;
    } catch (e) {
      _log.warning('notifications unavailable: $e');
    }
  }

  static Future<void> _bringToFront() async {
    if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) return;
    try {
      await windowManager.show();
      await windowManager.focus();
    } catch (_) {}
  }

  static NotificationDetails get _details => const NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      'Transfers',
      channelDescription: 'Incoming requests and finished transfers',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.message,
    ),
    linux: LinuxNotificationDetails(urgency: LinuxNotificationUrgency.normal),
    windows: WindowsNotificationDetails(),
  );

  /// "X wants to send you N files" — fixed id so repeated requests replace
  /// rather than stack.
  static Future<void> incomingRequest(String title, String body) =>
      _show(1, title, body);

  /// "Received N files from X".
  static Future<void> receiveFinished(String title, String body) =>
      _show(2, title, body);

  static Future<void> _show(int id, String title, String body) async {
    await init();
    if (!_ready) return;
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: _details,
      );
    } catch (e) {
      _log.fine('notification failed: $e');
    }
  }

  /// Clears the incoming-request notification once it has been decided.
  static Future<void> clearIncoming() async {
    if (!_ready) return;
    try {
      await _plugin.cancel(id: 1);
    } catch (_) {}
  }
}
