import 'dart:io';

import 'package:logging/logging.dart';
import 'package:window_manager/window_manager.dart';

/// Loopback-port single-instance lock for desktop.
///
/// On Windows the C++ runner already enforces this with a named mutex before
/// Flutter even starts; this Dart lock is the equivalent for Linux/macOS and a
/// second line of defence everywhere. The first instance binds a localhost
/// port and answers `GET /focus`; a second launch fails to bind, pokes that
/// endpoint so the existing window comes to the front, and exits.
class SingleInstance {
  SingleInstance._();

  static final _log = Logger('suvi.instance');
  static const int _port = 53339;
  static HttpServer? _server;

  /// Returns `true` if this process owns the instance lock and should keep
  /// starting. `false` means another instance is running and has been focused
  /// — the caller must exit.
  static Future<bool> acquire() async {
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, _port);
    } on SocketException {
      // Port taken: probably us. Verify before giving up, so an unrelated app
      // squatting the port can't block Suvi Share from ever launching.
      final isUs = await _pokeExisting();
      if (isUs) return false;
      _log.warning(
        'port $_port is held by a foreign process; '
        'continuing without the instance lock',
      );
      return true;
    } catch (e) {
      _log.warning('instance lock unavailable: $e');
      return true;
    }

    _server!.listen((req) async {
      if (req.uri.path == '/focus') {
        req.response.headers.set('server', 'SuviShare');
        req.response.write('ok');
        await req.response.close();
        try {
          await windowManager.show();
          await windowManager.focus();
        } catch (e) {
          _log.fine('focus on ping failed: $e');
        }
      } else {
        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
      }
    }, onError: (Object e) => _log.fine('instance lock error: $e'));
    return true;
  }

  static Future<bool> _pokeExisting() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final req = await client.get('127.0.0.1', _port, '/focus');
      final res = await req.close().timeout(const Duration(seconds: 2));
      final server = res.headers.value('server') ?? '';
      await res.drain<void>();
      return res.statusCode == 200 && server == 'SuviShare';
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  static Future<void> release() async {
    await _server?.close(force: true);
    _server = null;
  }
}
