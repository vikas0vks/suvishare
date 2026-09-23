import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../client/peer_client.dart';
import '../constants.dart';
import '../discovery/peer.dart';
import '../models/device_info.dart';
import '../models/file_dto.dart';
import '../models/session.dart';

/// Something the user wants to send: a file on disk, an in-memory blob, or an
/// opaque source (e.g. an Android `content://` URI) exposed as a byte stream.
@immutable
class SendItem {
  SendItem.file(this.path, {String? name, this.size, String? mime})
    : id = const Uuid().v4(),
      name = name ?? p.basename(path!),
      mime = mime ?? lookupMimeType(path!) ?? 'application/octet-stream',
      bytes = null,
      _opener = null,
      _sizer = null;

  SendItem.bytes(this.bytes, {required this.name, String? mime})
    : id = const Uuid().v4(),
      path = null,
      size = bytes!.length,
      mime = mime ?? lookupMimeType(name) ?? 'application/octet-stream',
      _opener = null,
      _sizer = null;

  /// A source that can only be read as a stream (no local path).
  /// [opener] must be able to produce the full byte stream on demand;
  /// resume (non-zero offset) is handled by skipping bytes.
  SendItem.stream({
    required this.name,
    required Stream<List<int>> Function() opener,
    int? size,
    Future<int> Function()? sizer,
    String? mime,
  }) : id = const Uuid().v4(),
       path = null,
       bytes = null,
       size = size,
       mime = mime ?? lookupMimeType(name) ?? 'application/octet-stream',
       _opener = opener,
       _sizer = sizer;

  final String id;
  final String name;
  final String? path;
  final List<int>? bytes;
  final int? size;
  final String mime;
  final Stream<List<int>> Function()? _opener;
  final Future<int> Function()? _sizer;

  Future<int> resolveSize() async {
    if (size != null) return size!;
    if (path != null) return File(path!).length();
    if (_sizer != null) return _sizer();
    return 0;
  }

  Stream<List<int>> open(int offset) {
    if (bytes != null) {
      return Stream.value(offset == 0 ? bytes! : bytes!.sublist(offset));
    }
    // Read on-disk files in large blocks. File.openRead() uses 64 KB chunks,
    // which throttles real-network transfers badly; 1 MB blocks fix it.
    if (path != null) return _fileBlocks(File(path!), offset);
    final stream = _opener!();
    if (offset == 0) return stream;
    return _skip(stream, offset);
  }

  static Stream<List<int>> _fileBlocks(File file, int offset) async* {
    final raf = await file.open(mode: FileMode.read);
    try {
      if (offset > 0) await raf.setPosition(offset);
      while (true) {
        final block = await raf.read(SuviConstants.chunkSize);
        if (block.isEmpty) break;
        yield block;
      }
    } finally {
      await raf.close();
    }
  }

  static Stream<List<int>> _skip(Stream<List<int>> source, int offset) async* {
    var remaining = offset;
    await for (final chunk in source) {
      if (remaining <= 0) {
        yield chunk;
      } else if (chunk.length <= remaining) {
        remaining -= chunk.length;
      } else {
        yield chunk.sublist(remaining);
        remaining = 0;
      }
    }
  }
}

@immutable
class SendingFile {
  const SendingFile({
    required this.item,
    required this.dto,
    this.token,
    this.status = FileStatus.queued,
    this.sent = 0,
    this.error,
  });

  final SendItem item;
  final FileDto dto;
  final String? token;
  final FileStatus status;
  final int sent;
  final String? error;

  SendingFile copyWith({
    String? token,
    FileStatus? status,
    int? sent,
    String? error,
  }) => SendingFile(
    item: item,
    dto: dto,
    token: token ?? this.token,
    status: status ?? this.status,
    sent: sent ?? this.sent,
    error: error ?? this.error,
  );
}

/// Why a send session failed, in terms the UI can act on.
enum SendFailure {
  none,

  /// TCP connect to the peer failed even after a fresh register probe —
  /// the app on the other device is closed, asleep, or its IP changed.
  /// The UI should drop the stale peer entry and re-discover.
  unreachable,
  declined,
  busy,
  pinRequired,
  other,
}

@immutable
class SendSession {
  const SendSession({
    required this.localId,
    required this.target,
    required this.files,
    required this.status,
    required this.startedAt,
    this.remoteSessionId,
    this.text,
    this.errorMessage,
    this.failure = SendFailure.none,
    this.endedAt,
  });

  final String localId;
  final Peer target;
  final Map<String, SendingFile> files;
  final SessionStatus status;
  final DateTime startedAt;
  final String? remoteSessionId;
  final String? text;
  final String? errorMessage;
  final SendFailure failure;
  final DateTime? endedAt;

  int get totalBytes => files.values.fold(0, (a, f) => a + f.dto.size);
  int get sentBytes => files.values.fold(0, (a, f) => a + f.sent);
  double get progress => totalBytes == 0 ? 1 : sentBytes / totalBytes;
  int get finishedCount =>
      files.values.where((f) => f.status == FileStatus.finished).length;
  int get failedCount =>
      files.values.where((f) => f.status == FileStatus.failed).length;

  SendSession copyWith({
    Map<String, SendingFile>? files,
    SessionStatus? status,
    String? remoteSessionId,
    String? errorMessage,
    SendFailure? failure,
    DateTime? endedAt,
  }) => SendSession(
    localId: localId,
    target: target,
    files: files ?? this.files,
    status: status ?? this.status,
    startedAt: startedAt,
    remoteSessionId: remoteSessionId ?? this.remoteSessionId,
    text: text,
    errorMessage: errorMessage ?? this.errorMessage,
    failure: failure ?? this.failure,
    endedAt: endedAt ?? this.endedAt,
  );
}

/// Result of one upload attempt, deciding whether a resume is worth trying.
sealed class _UploadOutcome {
  const _UploadOutcome();
}

class _UploadOk extends _UploadOutcome {
  const _UploadOk();
}

/// The receiver rejected us or the user cancelled — do not retry.
class _UploadFatal extends _UploadOutcome {
  const _UploadFatal();
}

/// The transport failed mid-stream — ask the receiver where to resume.
class _UploadRetryable extends _UploadOutcome {
  const _UploadRetryable(this.error);
  final String error;
}

/// Drives one outgoing transfer: prepare → parallel uploads → done.
class SendService {
  SendService({
    required PeerClient client,
    required DeviceInfo Function() selfInfo,
    this.maxResumeAttempts = 3,
    this.resumeBackoff = const Duration(milliseconds: 400),
  }) : _client = client,
       _selfInfo = selfInfo;

  /// How many times a single file may be resumed after a transport failure.
  final int maxResumeAttempts;

  /// Base delay between resume attempts; multiplied by the attempt number.
  final Duration resumeBackoff;

  static final _log = Logger('suvi.send');

  final PeerClient _client;
  final DeviceInfo Function() _selfInfo;

  final Map<String, CancelToken> _cancelTokens = {};
  final Map<String, SendSession> _sessions = {};
  final StreamController<SendSession> _updates =
      StreamController<SendSession>.broadcast();

  Stream<SendSession> get updates => _updates.stream;
  SendSession? session(String localId) => _sessions[localId];

  /// Starts a transfer. Returns the local session id immediately; progress is
  /// reported on [updates]. Resolves when the session reaches a terminal state.
  Future<SendSession> send({
    required Peer target,
    required List<SendItem> items,
    String? text,
    String? pin,
    int parallel = SuviConstants.parallelUploads,
    String? localId,
  }) async {
    final lid = localId ?? const Uuid().v4();
    final cancelToken = CancelToken();
    _cancelTokens[lid] = cancelToken;
    var identityRetained = false;

    try {
      if (target.info.protocol == PeerProtocol.https) {
        _client.retainExpectedFingerprint(target.ip, target.fingerprint);
        identityRetained = true;
      }

      final files = <String, SendingFile>{};
      for (final item in items) {
        final size = await item.resolveSize();
        DateTime? modified;
        if (item.path != null) {
          try {
            modified = await File(item.path!).lastModified();
          } catch (_) {}
        }
        files[item.id] = SendingFile(
          item: item,
          dto: FileDto(
            id: item.id,
            fileName: item.name,
            size: size,
            fileType: item.mime,
            modified: modified,
          ),
        );
      }

      var s = SendSession(
        localId: lid,
        target: target,
        files: files,
        status: SessionStatus.waiting,
        startedAt: DateTime.now(),
        text: text,
      );
      _publish(s);

      if (target.info.protocol == PeerProtocol.https) {
        final verified = await _client.verifyPeerIdentity(
          target.ip,
          target.port,
          target.fingerprint,
          protocol: target.info.protocol,
        );
        if (!verified) {
          final observed = _client.observedFingerprint(target.ip);
          final mismatch = observed != null && observed != target.fingerprint;
          s = s.copyWith(
            status: SessionStatus.failed,
            errorMessage: mismatch
                ? 'Certificate mismatch — device identity changed'
                : 'Could not connect — is the device still on the same Wi-Fi?',
            failure: mismatch ? SendFailure.other : SendFailure.unreachable,
            endedAt: DateTime.now(),
          );
          _publish(s);
          return s;
        }
      }

      // 1. prepare — with one recovery pass for transport failures. A dead
      // keep-alive socket or a peer that just restarted both show up here as an
      // instant connection error even though the device is fine; a fresh
      // `register` round-trip both revalidates the peer and warms a new
      // connection before the single retry.
      PrepareUploadRequest buildRequest() => PrepareUploadRequest(
        info: _selfInfo(),
        files: {for (final f in files.values) f.dto.id: f.dto},
        text: text,
      );

      PrepareUploadResponse? prep;
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          prep = await _client.prepareUpload(
            target.ip,
            target.port,
            buildRequest(),
            protocol: target.info.protocol,
            pin: pin,
            cancelToken: cancelToken,
          );
          break;
        } on PeerApiException catch (e) {
          final status = switch (e.statusCode) {
            403 => SessionStatus.declined,
            _ => SessionStatus.failed,
          };
          final failure = switch (e.statusCode) {
            401 => SendFailure.pinRequired,
            403 => SendFailure.declined,
            409 => SendFailure.busy,
            _ => SendFailure.other,
          };
          s = s.copyWith(
            status: status,
            errorMessage: _friendly(e),
            failure: failure,
            endedAt: DateTime.now(),
          );
          _publish(s);
          return s;
        } on DioException catch (e) {
          if (CancelToken.isCancel(e)) {
            s = s.copyWith(
              status: SessionStatus.cancelledBySender,
              endedAt: DateTime.now(),
            );
            _publish(s);
            return s;
          }
          final transport =
              e.type == DioExceptionType.connectionError ||
              e.type == DioExceptionType.connectionTimeout ||
              e.type == DioExceptionType.receiveTimeout;
          if (transport && attempt == 0) {
            final alive = await _client.register(
              target.ip,
              target.port,
              protocol: target.info.protocol,
              timeout: const Duration(seconds: 3),
            );
            if (alive != null) continue; // peer is up — retry prepare once
            s = s.copyWith(
              status: SessionStatus.failed,
              errorMessage: _friendlyDio(e),
              failure: SendFailure.unreachable,
              endedAt: DateTime.now(),
            );
            _publish(s);
            return s;
          }
          s = s.copyWith(
            status: SessionStatus.failed,
            errorMessage: _friendlyDio(e),
            failure: transport ? SendFailure.unreachable : SendFailure.other,
            endedAt: DateTime.now(),
          );
          _publish(s);
          return s;
        } catch (e) {
          s = s.copyWith(
            status: SessionStatus.failed,
            errorMessage: '$e',
            failure: SendFailure.other,
            endedAt: DateTime.now(),
          );
          _publish(s);
          return s;
        }
      }
      if (prep == null) {
        s = s.copyWith(
          status: SessionStatus.failed,
          failure: SendFailure.unreachable,
          endedAt: DateTime.now(),
        );
        _publish(s);
        return s;
      }

      // Nothing accepted (204) → done without uploads.
      if (prep.sessionId.isEmpty) {
        s = s.copyWith(
          files: {
            for (final f in files.values)
              f.dto.id: f.copyWith(status: FileStatus.skipped),
          },
          status: SessionStatus.finished,
          endedAt: DateTime.now(),
        );
        _publish(s);
        _cancelTokens.remove(lid);
        return s;
      }

      // 2. mark accepted/skipped
      final updated = <String, SendingFile>{};
      for (final f in files.values) {
        final token = prep.files[f.dto.id];
        updated[f.dto.id] = token == null
            ? f.copyWith(status: FileStatus.skipped)
            : f.copyWith(token: token);
      }
      s = s.copyWith(
        files: updated,
        remoteSessionId: prep.sessionId,
        status: SessionStatus.transferring,
      );
      _publish(s);

      // 3. upload with bounded parallelism
      final queue = Queue<SendingFile>.of(
        updated.values.where((f) => f.token != null),
      );
      Future<void> worker() async {
        while (queue.isNotEmpty && !cancelToken.isCancelled) {
          final f = queue.removeFirst();
          await _uploadOne(lid, f, cancelToken);
        }
      }

      await Future.wait(List.generate(parallel.clamp(1, 8), (_) => worker()));

      // 4. finish
      final fin = _sessions[lid]!;
      SessionStatus status;
      if (cancelToken.isCancelled) {
        status = SessionStatus.cancelledBySender;
      } else if (fin.failedCount > 0) {
        status = SessionStatus.finishedWithErrors;
      } else {
        status = SessionStatus.finished;
      }
      final done = fin.copyWith(status: status, endedAt: DateTime.now());
      _publish(done);
      _cancelTokens.remove(lid);
      return done;
    } finally {
      _cancelTokens.remove(lid);
      if (identityRetained) {
        _client.releaseExpectedFingerprint(target.ip, target.fingerprint);
      }
    }
  }

  /// Uploads one file, retrying from the receiver's byte count if the
  /// connection drops mid-stream. Protocol rejections (403/409/…) are final —
  /// only transport failures are worth retrying.
  Future<void> _uploadOne(
    String localId,
    SendingFile f,
    CancelToken cancelToken,
  ) async {
    var offset = 0;
    for (var attempt = 0; attempt <= maxResumeAttempts; attempt++) {
      if (cancelToken.isCancelled) break;
      final outcome = await _attemptUpload(localId, f, cancelToken, offset);
      switch (outcome) {
        case _UploadOk():
          return;
        case _UploadFatal():
          return;
        case _UploadRetryable(:final error):
          if (attempt == maxResumeAttempts) {
            _fail(localId, f, error);
            return;
          }
          // Ask the receiver how much it actually kept, then continue there.
          final s = _sessions[localId]!;
          var resumeAt = 0;
          try {
            resumeAt = await _client.uploadStatus(
              s.target.ip,
              s.target.port,
              sessionId: s.remoteSessionId!,
              fileId: f.dto.id,
              token: f.token!,
              protocol: s.target.info.protocol,
            );
          } catch (_) {
            _fail(localId, f, error);
            return;
          }
          if (resumeAt >= f.dto.size) {
            _publish(
              _setFile(
                _sessions[localId]!,
                _sessions[localId]!.files[f.dto.id]!.copyWith(
                  status: FileStatus.finished,
                  sent: f.dto.size,
                ),
              ),
            );
            return;
          }
          offset = resumeAt;
          _log.info(
            'resuming ${f.dto.fileName} at $offset/${f.dto.size} '
            '(attempt ${attempt + 1})',
          );
          await Future<void>.delayed(resumeBackoff * (attempt + 1));
      }
    }
  }

  Future<_UploadOutcome> _attemptUpload(
    String localId,
    SendingFile f,
    CancelToken cancelToken,
    int offset,
  ) async {
    final s = _sessions[localId]!;
    _publish(
      _setFile(
        s,
        s.files[f.dto.id]!.copyWith(status: FileStatus.sending, sent: offset),
      ),
    );
    var lastPublish = DateTime.now();
    try {
      await _client.upload(
        s.target.ip,
        s.target.port,
        sessionId: s.remoteSessionId!,
        fileId: f.dto.id,
        token: f.token!,
        body: f.item.open(offset),
        size: f.dto.size,
        offset: offset,
        protocol: s.target.info.protocol,
        cancelToken: cancelToken,
        onProgress: (sent, _) {
          final total = offset + sent;
          final now = DateTime.now();
          if (now.difference(lastPublish).inMilliseconds < 120 &&
              total < f.dto.size) {
            return;
          }
          lastPublish = now;
          final cur = _sessions[localId]!;
          _publish(_setFile(cur, cur.files[f.dto.id]!.copyWith(sent: total)));
        },
      );
      final cur = _sessions[localId]!;
      _publish(
        _setFile(
          cur,
          cur.files[f.dto.id]!.copyWith(
            status: FileStatus.finished,
            sent: f.dto.size,
          ),
        ),
      );
      return const _UploadOk();
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        _fail(localId, f, 'Cancelled');
        return const _UploadFatal();
      }
      // A dropped connection or a timeout is worth resuming.
      return _UploadRetryable(_friendlyDio(e));
    } on PeerApiException catch (e) {
      _fail(localId, f, _friendly(e));
      if (e.statusCode == 409 || e.statusCode == 404) {
        // Session gone on the other side: stop the whole transfer.
        cancelToken.cancel('remote session ended');
      }
      return const _UploadFatal();
    } catch (e, st) {
      _log.warning('upload failed: $e', e, st);
      return _UploadRetryable('$e');
    }
  }

  void _fail(String localId, SendingFile f, String error) {
    final cur = _sessions[localId];
    if (cur == null) return;
    final file = cur.files[f.dto.id];
    if (file == null) return;
    _publish(
      _setFile(cur, file.copyWith(status: FileStatus.failed, error: error)),
    );
  }

  /// Cancels a running session and informs the receiver.
  Future<void> cancel(String localId) async {
    final token = _cancelTokens[localId];
    final s = _sessions[localId];
    token?.cancel('user');
    if (s?.remoteSessionId != null) {
      await _client.cancel(
        s!.target.ip,
        s.target.port,
        sessionId: s.remoteSessionId!,
        protocol: s.target.info.protocol,
      );
    }
    if (s != null && !s.status.isTerminal) {
      _publish(
        s.copyWith(
          status: SessionStatus.cancelledBySender,
          endedAt: DateTime.now(),
        ),
      );
    }
  }

  SendSession _setFile(SendSession s, SendingFile f) {
    final files = Map<String, SendingFile>.from(s.files)..[f.dto.id] = f;
    return s.copyWith(files: files);
  }

  void _publish(SendSession s) {
    _sessions[s.localId] = s;
    if (!_updates.isClosed) _updates.add(s);
  }

  static String _friendly(PeerApiException e) => switch (e.statusCode) {
    401 => 'PIN required or incorrect',
    403 => 'Declined by the receiver',
    409 => 'Receiver is busy with another transfer',
    413 => 'Too large for the receiver',
    429 => 'Too many requests — try again shortly',
    _ => e.message,
  };

  static String _friendlyDio(DioException e) => switch (e.type) {
    DioExceptionType.connectionTimeout || DioExceptionType.connectionError =>
      'Could not connect — is the device still on the same Wi-Fi?',
    DioExceptionType.receiveTimeout => 'The receiver stopped responding',
    DioExceptionType.badCertificate =>
      'Certificate mismatch — device identity changed',
    _ => e.message ?? 'Network error',
  };

  Future<void> dispose() async {
    for (final t in _cancelTokens.values) {
      t.cancel('dispose');
    }
    await _updates.close();
  }
}
