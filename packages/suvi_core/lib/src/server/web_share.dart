import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:logging/logging.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';

import '../models/file_dto.dart';
import '../security/filename_sanitizer.dart';
import '../transfer/send_service.dart';

/// One file being offered to browsers.
class WebShareFile {
  WebShareFile({required this.dto, required this.item});
  final FileDto dto;
  final SendItem item;
}

/// A time-boxed set of files this device offers to browsers on the LAN,
/// plus the PIN gate. Sessions expire so a stale tab cannot keep downloading
/// (the bug LocalSend hit in issue #3094).
class WebShareOffer {
  WebShareOffer({
    required this.sessionId,
    required this.files,
    required this.expiresAt,
    this.pin,
  });

  final String sessionId;
  final Map<String, WebShareFile> files;
  final DateTime expiresAt;
  final String? pin;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  int get totalSize => files.values.fold(0, (a, f) => a + f.dto.size);

  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'files': {for (final f in files.values) f.dto.id: f.dto.toJson()},
  };
}

/// Serves the browser-facing page and the download API over **plain HTTP**.
///
/// HTTP, not HTTPS, is deliberate: browsers reject self-signed certificates and
/// a LAN IP can never get a publicly-trusted one. The compromise is that the
/// page is PIN-gated, the session is short-lived, and the listener only runs
/// while the user has Web Share switched on. See docs/05-protocol-spec.md §4.
class WebShareHandler {
  WebShareHandler({
    required Future<List<int>?> Function(String assetPath) loadAsset,
    required String Function() deviceAlias,
    String? sessionPin,
    Random? random,
  }) : _loadAsset = loadAsset,
       _deviceAlias = deviceAlias,
       _sessionPin = sessionPin,
       _random = random ?? Random.secure();

  static final _log = Logger('suvi.webshare');
  static const _apiPrefix = '/api/suvi/v1';

  final Future<List<int>?> Function(String assetPath) _loadAsset;
  final String Function() _deviceAlias;
  final String? _sessionPin;
  final Random _random;

  WebShareOffer? _offer;
  final Set<String> _authorised = {}; // client IPs that passed the PIN gate
  final Map<String, List<DateTime>> _pinFailures = {};

  WebShareOffer? get offer => _offer;
  bool get hasOffer => _offer != null && !_offer!.isExpired;
  String? get sessionPin => _sessionPin;

  /// Publishes [items] for download by browsers. Returns the offer.
  Future<WebShareOffer> publish(
    List<SendItem> items, {
    String? pin,
    Duration ttl = const Duration(minutes: 30),
  }) async {
    final files = <String, WebShareFile>{};
    for (final item in items) {
      final size = await item.resolveSize();
      files[item.id] = WebShareFile(
        dto: FileDto(
          id: item.id,
          fileName: FilenameSanitizer.sanitize(item.name),
          size: size,
          fileType: item.mime,
        ),
        item: item,
      );
    }
    _authorised.clear();
    _offer = WebShareOffer(
      sessionId: _token(),
      files: files,
      expiresAt: DateTime.now().add(ttl),
      pin: (pin != null && pin.isNotEmpty)
          ? pin
          : (_sessionPin != null && _sessionPin.isNotEmpty
                ? _sessionPin
                : null),
    );
    _log.info('web share published: ${files.length} file(s)');
    return _offer!;
  }

  /// Stops offering files. Existing downloads are cut off.
  void revoke() {
    _offer = null;
    _authorised.clear();
    _pinFailures.clear();
  }

  /// shelf handler for every non-`/api/suvi/v1` path plus the download API.
  Future<Response> call(Request request) async {
    final path = '/${request.url.path}';
    if (path.startsWith('$_apiPrefix/prepare-download')) {
      return _prepareDownload(request);
    }
    if (path.startsWith('$_apiPrefix/download')) return _download(request);
    if (path.startsWith('$_apiPrefix/web-info')) return _webInfo(request);
    return _static(request, path);
  }

  // ------------------------------------------------------------------ pages

  Future<Response> _static(Request request, String path) async {
    var asset = path;
    if (asset == '/' || asset.isEmpty) asset = '/index.html';
    // No traversal out of the asset folder, no absolute paths.
    final normalised = p.posix.normalize(asset);
    if (normalised.contains('..')) {
      return Response.forbidden('Forbidden');
    }
    final bytes = await _loadAsset('assets/web$normalised');
    if (bytes == null) {
      // Single-page app: unknown paths fall back to the shell.
      final index = await _loadAsset('assets/web/index.html');
      if (index == null) return Response.notFound('Not found');
      return Response.ok(
        index,
        headers: {'content-type': 'text/html; charset=utf-8'},
      );
    }
    final type = lookupMimeType(normalised) ?? 'application/octet-stream';
    return Response.ok(
      bytes,
      headers: {
        'content-type':
            type.startsWith('text/') ||
                type.contains('javascript') ||
                type.contains('json')
            ? '$type; charset=utf-8'
            : type,
      },
    );
  }

  Response _webInfo(Request request) => _json(200, {
    'alias': _deviceAlias(),
    'hasOffer': hasOffer,
    'pinRequired': _sessionPin?.isNotEmpty == true || _offer?.pin != null,
    'fileCount': hasOffer ? _offer!.files.length : 0,
    'totalSize': hasOffer ? _offer!.totalSize : 0,
  });

  // --------------------------------------------------------------- download

  Future<Response> _prepareDownload(Request request) async {
    final offer = _offer;
    if (offer == null || offer.isExpired) {
      _offer = null;
      return _json(404, {'message': 'Nothing is being shared right now'});
    }
    final ip = remoteIpOf(request);
    if (offer.pin != null) {
      final pin = request.url.queryParameters['pin'];
      if (pin != offer.pin && !_authorised.contains(ip)) {
        if (!_allowPinFailure(ip)) {
          return _json(429, {'message': 'Too many PIN attempts'});
        }
        return _json(401, {'message': 'PIN required'});
      }
      _authorised.add(ip);
      _pinFailures.remove(ip);
    }
    return _json(200, {
      'info': {'alias': _deviceAlias(), 'deviceType': 'desktop'},
      ...offer.toJson(),
    });
  }

  Future<Response> _download(Request request) async {
    final offer = _offer;
    final q = request.url.queryParameters;
    if (offer == null || offer.isExpired || q['sessionId'] != offer.sessionId) {
      return _json(404, {'message': 'Share expired'});
    }
    if (offer.pin != null && !_authorised.contains(remoteIpOf(request))) {
      return _json(401, {'message': 'PIN required'});
    }
    final file = offer.files[q['fileId']];
    if (file == null) return _json(404, {'message': 'Unknown file'});

    final size = file.dto.size;
    var start = 0;
    var end = size == 0 ? -1 : size - 1;
    var status = 200;
    final range = request.headers['range'];
    if (range != null && size > 0) {
      final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(range.trim());
      if (match == null) return _rangeNotSatisfiable(size);
      final rawStart = match.group(1)!;
      final rawEnd = match.group(2)!;
      if (rawStart.isEmpty) {
        final suffix = int.tryParse(rawEnd);
        if (suffix == null || suffix <= 0) return _rangeNotSatisfiable(size);
        start = (size - suffix).clamp(0, size);
      } else {
        start = int.tryParse(rawStart) ?? -1;
      }
      if (rawEnd.isNotEmpty && rawStart.isNotEmpty) {
        end = int.tryParse(rawEnd) ?? -1;
      }
      if (start < 0 || start >= size || end < start) {
        return _rangeNotSatisfiable(size);
      }
      end = end.clamp(start, size - 1);
      status = 206;
    }
    final length = end < start ? 0 : end - start + 1;
    final body = length == 0
        ? const Stream<List<int>>.empty()
        : _takeBytes(file.item.open(start), length);
    return Response(
      status,
      body: body,
      headers: {
        'content-type': file.dto.fileType,
        'content-length': '$length',
        'accept-ranges': 'bytes',
        if (status == 206) 'content-range': 'bytes $start-$end/$size',
        'content-disposition':
            'attachment; filename="${_headerSafe(file.dto.fileName)}"; '
            "filename*=UTF-8''${Uri.encodeComponent(file.dto.fileName)}",
        'cache-control': 'no-store',
      },
    );
  }

  // ---------------------------------------------------------------- helpers

  /// Remote IP of a shelf request, with IPv4-mapped IPv6 normalised.
  static String remoteIpOf(Request req) {
    final conn = req.context['shelf.io.connection_info'] as HttpConnectionInfo?;
    final ip = conn?.remoteAddress.address ?? '';
    return ip.startsWith('::ffff:') ? ip.substring(7) : ip;
  }

  /// ASCII-only fallback for the legacy `filename=` header parameter.
  static String _headerSafe(String name) =>
      name.replaceAll(RegExp(r'[^\x20-\x7E]'), '_').replaceAll('"', '_');

  String _token() {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return List.generate(
      24,
      (_) => chars[_random.nextInt(chars.length)],
    ).join();
  }

  bool _allowPinFailure(String ip) {
    final now = DateTime.now();
    final hits = _pinFailures.putIfAbsent(ip, () => []);
    hits.removeWhere((t) => now.difference(t) > const Duration(minutes: 1));
    if (hits.length >= 10) return false;
    hits.add(now);
    return true;
  }

  static Stream<List<int>> _takeBytes(
    Stream<List<int>> source,
    int wanted,
  ) async* {
    var remaining = wanted;
    await for (final chunk in source) {
      if (remaining <= 0) break;
      if (chunk.length <= remaining) {
        yield chunk;
        remaining -= chunk.length;
      } else {
        yield chunk.sublist(0, remaining);
        remaining = 0;
      }
    }
  }

  static Response _rangeNotSatisfiable(int size) => Response(
    416,
    body: jsonEncode({'message': 'Range not satisfiable'}),
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'content-range': 'bytes */$size',
    },
  );

  static Response _json(int status, Object body) => Response(
    status,
    body: jsonEncode(body),
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}
