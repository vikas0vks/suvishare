import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../constants.dart';
import '../models/device_info.dart';
import '../models/session.dart';
import '../security/identity.dart';
import '../util/network_utils.dart';
import 'session_manager.dart';

/// The device's HTTPS API server (receiver side of the protocol).
class SuviServer {
  SuviServer({
    required DeviceInfo Function() selfInfo,
    required SessionManager sessions,
    required SuviIdentity identity,
    void Function(DeviceInfo info, String ip)? onRegister,
    Handler? webHandler,
    String? Function()? requiredUploadPin,
  }) : _selfInfo = selfInfo,
       _sessions = sessions,
       _identity = identity,
       _onRegister = onRegister,
       _webHandler = webHandler,
       _requiredUploadPin = requiredUploadPin;

  static final _log = Logger('suvi.server');

  final DeviceInfo Function() _selfInfo;
  final SessionManager _sessions;
  final SuviIdentity _identity;
  final void Function(DeviceInfo info, String ip)? _onRegister;

  /// Optional handler for non-API paths (web-share page).
  final Handler? _webHandler;
  final String? Function()? _requiredUploadPin;
  final Map<String, List<DateTime>> _pinFailures = {};

  HttpServer? _server;
  int? _boundPort;
  bool _https = true;

  bool get isRunning => _server != null;
  int? get port => _boundPort;
  bool get isHttps => _https;

  /// Binds on all IPv4 interfaces. If [https] is false a plain HTTP server
  /// is started (used for the browser web-share listener).
  Future<void> start({
    int port = SuviConstants.defaultPort,
    bool https = true,
    InternetAddress? address,
  }) async {
    if (_server != null) return;
    _https = https;
    final handler = const Pipeline()
        .addMiddleware(_logging())
        .addMiddleware(_security())
        .addHandler(_router().call);
    final addr = address ?? InternetAddress.anyIPv4;
    _server = await shelf_io.serve(
      handler,
      addr,
      port,
      securityContext: https ? _identity.toSecurityContext() : null,
      shared: false,
    );
    _server!.autoCompress = false;
    _server!.idleTimeout = const Duration(minutes: 2);
    _boundPort = _server!.port;
    _log.info(
      'Suvi server listening on ${https ? 'https' : 'http'}://'
      '${addr.address}:$_boundPort',
    );
  }

  Future<void> stop() async {
    final s = _server;
    _server = null;
    _boundPort = null;
    await s?.close(force: true);
  }

  // -------------------------------------------------------------- routing

  Router _router() {
    final r = Router(notFoundHandler: _notFound);
    final api = SuviConstants.apiPrefix;

    r.get('$api/info', _info);
    r.post('$api/register', _register);
    r.post('$api/prepare-upload', _prepareUpload);
    r.post('$api/upload', _upload);
    r.get('$api/upload-status', _uploadStatus);
    r.post('$api/cancel', _cancel);

    // LocalSend-compat aliases (same semantics).
    const ls = '/api/localsend/v2';
    r.get('$ls/info', _info);
    r.post('$ls/register', _register);
    r.post('$ls/prepare-upload', _prepareUpload);
    r.post('$ls/upload', _upload);
    r.post('$ls/cancel', _cancel);

    if (_webHandler != null) {
      r.all('/<ignored|.*>', _webHandler);
    }
    return r;
  }

  Response _notFound(Request req) => _json(404, {'message': 'Not found'});

  Future<Response> _info(Request req) async {
    return _json(200, _selfInfo().copyWith(clearAnnounce: true).toJson());
  }

  Future<Response> _register(Request req) async {
    final body = await _readJson(req);
    if (body.tooLarge) return _json(413, {'message': 'Request body too large'});
    final info = DeviceInfo.tryParse(body.data);
    if (info == null) return _json(400, {'message': 'Invalid device info'});
    final ip = _remoteIp(req);
    if (info.fingerprint != _selfInfo().fingerprint) {
      _onRegister?.call(info, ip);
    }
    return _json(200, _selfInfo().copyWith(clearAnnounce: true).toJson());
  }

  Future<Response> _prepareUpload(Request req) async {
    final body = await _readJson(req);
    if (body.tooLarge) return _json(413, {'message': 'Request body too large'});
    final parsed = PrepareUploadRequest.tryParse(body.data);
    if (parsed == null) return _json(400, {'message': 'Invalid request body'});
    final pin = req.url.queryParameters['pin'];
    final requiredPin = _requiredUploadPin?.call();
    if (requiredPin != null && requiredPin.isNotEmpty && pin != requiredPin) {
      if (!_allowPinFailure(_remoteIp(req))) {
        return _json(429, {'message': 'Too many PIN attempts'});
      }
      return _json(401, {'message': 'PIN required'});
    }
    if (requiredPin != null && pin == requiredPin) {
      _pinFailures.remove(_remoteIp(req));
    }
    final outcome = await _sessions.prepareUpload(
      parsed,
      _remoteIp(req),
      pin: pin,
    );
    return switch (outcome) {
      PrepareAccepted(:final sessionId, :final fileTokens) => _json(
        200,
        PrepareUploadResponse(sessionId: sessionId, files: fileTokens).toJson(),
      ),
      PrepareNothingToDo() => Response(204),
      PrepareError(:final status, :final message) => _json(status, {
        'message': message,
      }),
    };
  }

  Future<Response> _upload(Request req) async {
    final q = req.url.queryParameters;
    final sessionId = q['sessionId'];
    final fileId = q['fileId'];
    final token = q['token'];
    if (sessionId == null || fileId == null || token == null) {
      return _json(400, {'message': 'Missing sessionId/fileId/token'});
    }
    final offset = int.tryParse(req.headers['x-suvi-offset'] ?? '') ?? 0;
    final outcome = await _sessions.upload(
      sessionId: sessionId,
      fileId: fileId,
      token: token,
      senderIp: _remoteIp(req),
      body: req.read(),
      offset: offset,
      contentLength: req.contentLength,
    );
    if (outcome.ok) return Response.ok('');
    return _json(outcome.status, {'message': outcome.message});
  }

  Future<Response> _uploadStatus(Request req) async {
    final q = req.url.queryParameters;
    final sessionId = q['sessionId'];
    final fileId = q['fileId'];
    final token = q['token'];
    if (sessionId == null || fileId == null || token == null) {
      return _json(400, {'message': 'Missing sessionId/fileId/token'});
    }
    final outcome = await _sessions.uploadStatus(
      sessionId,
      fileId,
      token,
      _remoteIp(req),
    );
    if (!outcome.ok) return _json(outcome.status, {'message': outcome.message});
    return _json(200, {'received': int.tryParse(outcome.message) ?? 0});
  }

  Future<Response> _cancel(Request req) async {
    final sessionId = req.url.queryParameters['sessionId'];
    if (sessionId == null) return _json(400, {'message': 'Missing sessionId'});
    await _sessions.cancel(sessionId, senderIp: _remoteIp(req));
    return Response.ok('');
  }

  // ----------------------------------------------------------- middleware

  Middleware _logging() =>
      (inner) => (req) async {
        final sw = Stopwatch()..start();
        final res = await inner(req);
        _log.fine(
          '${req.method} /${req.url.path} → ${res.statusCode} '
          '(${sw.elapsedMilliseconds} ms) from ${_remoteIp(req)}',
        );
        return res;
      };

  Middleware _security() =>
      (inner) => (req) async {
        try {
          final remoteIp = _remoteIp(req);
          if (remoteIp.isNotEmpty && !NetworkUtils.isAllowedPeerIp(remoteIp)) {
            return _json(403, {'message': 'LAN access only'});
          }
          final res = await inner(req);
          return res.change(
            headers: {
              'x-content-type-options': 'nosniff',
              'x-frame-options': 'DENY',
              'referrer-policy': 'no-referrer',
              'permissions-policy': 'camera=(), microphone=(), geolocation=()',
              'content-security-policy':
                  "default-src 'self'; img-src 'self' data:; "
                  "style-src 'self'; script-src 'self'; connect-src 'self'; "
                  "object-src 'none'; base-uri 'none'; frame-ancestors 'none'",
              'cache-control': 'no-store',
              'server': 'SuviShare/${SuviConstants.protocolVersion}',
            },
          );
        } catch (e, st) {
          _log.severe('Unhandled error for ${req.url}: $e', e, st);
          return _json(500, {'message': 'Internal error'});
        }
      };

  // -------------------------------------------------------------- helpers

  static String _remoteIp(Request req) {
    final conn = req.context['shelf.io.connection_info'] as HttpConnectionInfo?;
    final ip = conn?.remoteAddress.address ?? '';
    // Normalise IPv4-mapped IPv6 (::ffff:1.2.3.4).
    return ip.startsWith('::ffff:') ? ip.substring(7) : ip;
  }

  static Future<({Object? data, bool tooLarge})> _readJson(Request req) async {
    final declared = req.contentLength;
    if (declared != null && declared > SuviConstants.maxJsonBodyBytes) {
      return (data: null, tooLarge: true);
    }
    try {
      final bytes = BytesBuilder(copy: false);
      var total = 0;
      await for (final chunk in req.read()) {
        total += chunk.length;
        if (total > SuviConstants.maxJsonBodyBytes) {
          return (data: null, tooLarge: true);
        }
        bytes.add(chunk);
      }
      if (total == 0) return (data: null, tooLarge: false);
      return (
        data: jsonDecode(utf8.decode(bytes.takeBytes())),
        tooLarge: false,
      );
    } catch (_) {
      return (data: null, tooLarge: false);
    }
  }

  bool _allowPinFailure(String ip) {
    final now = DateTime.now();
    final hits = _pinFailures.putIfAbsent(ip, () => []);
    hits.removeWhere((t) => now.difference(t) > const Duration(minutes: 1));
    if (hits.length >= SuviConstants.prepareRateLimitPerMinute) return false;
    hits.add(now);
    return true;
  }

  static Response _json(int status, Object body) => Response(
    status,
    body: jsonEncode(body),
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}
