import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// Everything needed before this device may *receive* files:
/// runtime permissions (Android) and a save directory that is actually
/// writable. Asked lazily, right before the first accept — never up front.
class ReceivePrerequisites {
  ReceivePrerequisites._();

  static final _log = Logger('suvi.permissions');
  static int? _sdkInt;
  static bool _notificationsAsked = false;

  static Future<int> _androidSdk() async {
    if (!Platform.isAndroid) return 0;
    return _sdkInt ??= (await DeviceInfoPlugin().androidInfo).version.sdkInt;
  }

  /// Requests the runtime permissions receiving depends on. Safe to call
  /// repeatedly; each dialog is shown at most once per run. Never throws.
  static Future<void> requestReceivePermissions() async {
    if (!Platform.isAndroid) return;
    try {
      final sdk = await _androidSdk();

      // Android 13+: without this the accept/progress notifications are
      // silently dropped and a background receive looks like nothing happened.
      if (sdk >= 33 && !_notificationsAsked) {
        _notificationsAsked = true;
        final status = await Permission.notification.status;
        if (status.isDenied) {
          await Permission.notification.request();
        }
      }

      // Android 10 and below: writing to the public Download folder needs the
      // legacy storage permission. 11+ lets apps create their own files there
      // without any permission, so never ask on modern devices.
      if (sdk <= 29) {
        final status = await Permission.storage.status;
        if (status.isDenied) {
          await Permission.storage.request();
        }
      }
    } catch (e) {
      _log.warning('permission request failed: $e');
    }
  }

  /// Returns a directory that is proven writable, preferring [preferred].
  ///
  /// Proven = a probe file was actually created and deleted there, because on
  /// Android "the path exists" says nothing about scoped-storage access. Falls
  /// back to an app-owned directory that needs no permission at all, so
  /// receiving can never fail with a write error after the user already
  /// accepted.
  static Future<({String dir, bool fellBack})> resolveWritableDir(
    String preferred,
  ) async {
    if (await _probe(preferred)) return (dir: preferred, fellBack: false);

    for (final fallback in await _fallbacks()) {
      if (fallback == preferred) continue;
      if (await _probe(fallback)) {
        _log.info('save dir "$preferred" not writable; using "$fallback"');
        return (dir: fallback, fellBack: true);
      }
    }
    // Nothing probed writable (bizarre) — return the preference and let the
    // transfer surface the real error.
    return (dir: preferred, fellBack: false);
  }

  static Future<List<String>> _fallbacks() async {
    final out = <String>[];
    try {
      if (Platform.isAndroid) {
        // App-specific external dir: visible in file managers under
        // Android/data, writable without any permission on every API level.
        final ext = await getExternalStorageDirectory();
        if (ext != null) out.add(p.join(ext.path, 'Suvi Share'));
      } else {
        final downloads = await getDownloadsDirectory();
        if (downloads != null) out.add(p.join(downloads.path, 'Suvi Share'));
      }
      final docs = await getApplicationDocumentsDirectory();
      out.add(p.join(docs.path, 'Suvi Share'));
    } catch (e) {
      _log.warning('fallback dir lookup failed: $e');
    }
    return out;
  }

  static Future<bool> _probe(String dir) async {
    try {
      final d = Directory(dir);
      if (!await d.exists()) await d.create(recursive: true);
      final probe = File(p.join(dir, '.suvi-write-probe'));
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// One call for the receive path: permissions + writable directory.
  static Future<({String dir, bool fellBack})> prepare(String preferred) async {
    await requestReceivePermissions();
    return resolveWritableDir(preferred);
  }
}
