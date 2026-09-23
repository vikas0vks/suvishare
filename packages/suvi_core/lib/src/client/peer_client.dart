import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:logging/logging.dart';

import '../constants.dart';
import '../models/device_info.dart';
import '../models/session.dart';
import '../security/identity.dart';

/// Decides whether to accept a peer's TLS certificate.
///
/// Receives the host we connected to and the SHA-256 fingerprint of the
/// certificate presented. Return `true` to proceed. Typical policy: if the
/// peer is pinned, require equality; otherwise trust-on-first-use.
typedef CertificatePolicy = bool Function(String host, String fingerprint);

/// Thrown for non-2xx protocol responses.
class PeerApiException implements Exception {
  PeerApiException(this.statusCode, this.message, {this.uri});
  final int statusCode;
  final String message;
  final Uri? uri;

  bool get isPinRequired => statusCode == 401;
  bool get isRejected => statusCode == 403;
  bool get isBusy => statusCode == 409;
  bool get isTooLarge => statusCode == 413;
  bool get isRateLimited => statusCode == 429;

  @override
  String toString() => 'PeerApiException($statusCode, $message)';
}

/// HTTP(S) client for talking to other Suvi Share devices.
class PeerClient {
  PeerClient({
    required DeviceInfo Function() selfInfo,
    CertificatePolicy? certificatePolicy,
    Duration connectTimeout = const Duration(seconds: 5),
  }) : _selfInfo = selfInfo,
       _policy = certificatePolicy ?? ((_, __) => true) {
    _dio = Dio(
      BaseOptions(
        connectTimeout: connectTimeout,
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(days: 1),
        responseType: ResponseType.json,
        validateStatus: (_) => true,
      ),
    );
    _dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final c = HttpClient()
          ..connectionTimeout = connectTimeout
          ..idleTimeout = const Duration(seconds: 15)
          ..badCertificateCallback = (cert, host, port) {
            final fp = SuviIdentity.fingerprintOfDer(cert.der);
            _lastSeenFingerprint[host] = fp;
            final expected = _expectedFingerprint[host];
            return (expected == null || expected == fp) && _policy(host, fp);
          };
        return c;
      },
    );
  }

  static final _log = Logger('suvi.client');

  final DeviceInfo Function() _selfInfo;
  final CertificatePolicy _policy;
  final Map<String, String> _lastSeenFingerprint = {};
  final Map<String, String> _expectedFingerprint = {};
  final Map<String, int> _expectedFingerprintRefs = {};
  late final Dio _dio;

  /// Fingerprint observed on the last TLS connection to [host], if any.
  String? observedFingerprint(String host) => _lastSeenFingerprint[host];

  /// Pins subsequent TLS connections to [host] until balanced by
  /// [releaseExpectedFingerprint]. Nested users of the same pin are safe.
  void retainExpectedFingerprint(String host, String fingerprint) {
    final current = _expectedFingerprint[host];
    if (current != null && current != fingerprint) {
      throw StateError('Conflicting certificate identity for $host');
    }
    _expectedFingerprint[host] = fingerprint;
    _expectedFingerprintRefs[host] = (_expectedFingerprintRefs[host] ?? 0) + 1;
  }

  void releaseExpectedFingerprint(String host, String fingerprint) {
    if (_expectedFingerprint[host] != fingerprint) return;
    final remaining = (_expectedFingerprintRefs[host] ?? 1) - 1;
    if (remaining <= 0) {
      _expectedFingerprint.remove(host);
      _expectedFingerprintRefs.remove(host);
    } else {
      _expectedFingerprintRefs[host] = remaining;
    }
  }

  /// Proves that the peer reachable at [ip]:[port] presents [fingerprint] and
  /// advertises the same identity. HTTP peers cannot be identity-verified.
  Future<bool> verifyPeerIdentity(
    String ip,
    int port,
    String fingerprint, {
    PeerProtocol protocol = PeerProtocol.https,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (protocol != PeerProtocol.https) return false;
    retainExpectedFingerprint(ip, fingerprint);
    try {
      final peer = await info(ip, port, protocol: protocol, timeout: timeout);
      return peer?.fingerprint == fingerprint &&
          observedFingerprint(ip) == fingerprint;
    } finally {
      releaseExpectedFingerprint(ip, fingerprint);
    }
  }

  String _url(PeerProtocol protocol, String ip, int port, String path) =>
      '${protocol.name}://$ip:$port${SuviConstants.apiPrefix}$path';

  /// `POST /register` — announce ourselves over TCP; returns the peer's info.
  Future<DeviceInfo?> register(
    String ip,
    int port, {
    PeerProtocol protocol = PeerProtocol.https,
    Duration? timeout,
  }) async {
    try {
      final res = await _dio
          .post<Object?>(
            _url(protocol, ip, port, '/register'),
            data: _selfInfo().toJson(),
            options: Options(
              receiveTimeout: timeout ?? const Duration(seconds: 5),
              sendTimeout: timeout ?? const Duration(seconds: 5),
            ),
          )
          .timeout(timeout ?? const Duration(seconds: 6));
      if (res.statusCode == 200) return DeviceInfo.tryParse(res.data);
      return null;
    } catch (e) {
      _log.finer('register $ip:$port failed: $e');
      return null;
    }
  }

  /// `GET /info`.
  Future<DeviceInfo?> info(
    String ip,
    int port, {
    PeerProtocol protocol = PeerProtocol.https,
    Duration? timeout,
  }) async {
    try {
      final res = await _dio
          .get<Object?>(
            _url(protocol, ip, port, '/info'),
            queryParameters: {'fingerprint': _selfInfo().fingerprint},
          )
          .timeout(timeout ?? const Duration(seconds: 5));
      if (res.statusCode == 200) return DeviceInfo.tryParse(res.data);
      return null;
    } catch (_) {
      return null;
    }
  }

  /// `POST /prepare-upload`. Throws [PeerApiException] on non-200.
  Future<PrepareUploadResponse> prepareUpload(
    String ip,
    int port,
    PrepareUploadRequest request, {
    PeerProtocol protocol = PeerProtocol.https,
    String? pin,
    CancelToken? cancelToken,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final res = await _dio.post<Object?>(
      _url(protocol, ip, port, '/prepare-upload'),
      queryParameters: {if (pin != null && pin.isNotEmpty) 'pin': pin},
      data: request.toJson(),
      cancelToken: cancelToken,
      options: Options(receiveTimeout: timeout),
    );
    if (res.statusCode == 204) {
      // Receiver accepted nothing but did not reject (e.g. all files skipped).
      return const PrepareUploadResponse(sessionId: '', files: {});
    }
    if (res.statusCode == 200) {
      final parsed = PrepareUploadResponse.tryParse(res.data);
      if (parsed == null) {
        throw PeerApiException(500, 'Malformed prepare-upload response');
      }
      return parsed;
    }
    throw PeerApiException(
      res.statusCode ?? 0,
      _messageOf(res),
      uri: res.realUri,
    );
  }

  /// `POST /upload` streaming [body] of exactly [size] bytes.
  Future<void> upload(
    String ip,
    int port, {
    required String sessionId,
    required String fileId,
    required String token,
    required Stream<List<int>> body,
    required int size,
    int offset = 0,
    PeerProtocol protocol = PeerProtocol.https,
    CancelToken? cancelToken,
    void Function(int sent, int total)? onProgress,
  }) async {
    final res = await _dio.post<Object?>(
      _url(protocol, ip, port, '/upload'),
      queryParameters: {
        'sessionId': sessionId,
        'fileId': fileId,
        'token': token,
      },
      data: body,
      cancelToken: cancelToken,
      onSendProgress: onProgress,
      options: Options(
        headers: {
          Headers.contentLengthHeader: size - offset,
          Headers.contentTypeHeader: 'application/octet-stream',
          if (offset > 0) 'X-Suvi-Offset': '$offset',
        },
        receiveTimeout: const Duration(minutes: 10),
      ),
    );
    if (res.statusCode == 200) return;
    throw PeerApiException(
      res.statusCode ?? 0,
      _messageOf(res),
      uri: res.realUri,
    );
  }

  /// `GET /upload-status` → bytes the receiver already has (for resume).
  Future<int> uploadStatus(
    String ip,
    int port, {
    required String sessionId,
    required String fileId,
    required String token,
    PeerProtocol protocol = PeerProtocol.https,
  }) async {
    final res = await _dio.get<Object?>(
      _url(protocol, ip, port, '/upload-status'),
      queryParameters: {
        'sessionId': sessionId,
        'fileId': fileId,
        'token': token,
      },
    );
    if (res.statusCode == 200 && res.data is Map) {
      final v = (res.data as Map)['received'];
      if (v is num) return v.toInt();
    }
    return 0;
  }

  /// `POST /cancel`.
  Future<void> cancel(
    String ip,
    int port, {
    required String sessionId,
    PeerProtocol protocol = PeerProtocol.https,
  }) async {
    try {
      await _dio.post<Object?>(
        _url(protocol, ip, port, '/cancel'),
        queryParameters: {'sessionId': sessionId},
        options: Options(receiveTimeout: const Duration(seconds: 5)),
      );
    } catch (e) {
      _log.fine('cancel failed: $e');
    }
  }

  String _messageOf(Response<Object?> res) {
    final d = res.data;
    if (d is Map && d['message'] is String) return d['message'] as String;
    if (d is String && d.isNotEmpty) {
      try {
        final j = jsonDecode(d);
        if (j is Map && j['message'] is String) return j['message'] as String;
      } catch (_) {}
      return d;
    }
    return res.statusMessage ?? 'HTTP ${res.statusCode}';
  }

  void close() => _dio.close(force: true);
}
