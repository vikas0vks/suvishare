import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../constants.dart';
import '../models/session.dart';
import '../security/filename_sanitizer.dart';
import 'receive_session.dart';

/// Outcome of `prepare-upload` handling.
sealed class PrepareOutcome {
  const PrepareOutcome();
}

class PrepareAccepted extends PrepareOutcome {
  const PrepareAccepted(this.sessionId, this.fileTokens);
  final String sessionId;
  final Map<String, String> fileTokens;
}

class PrepareNothingToDo extends PrepareOutcome {
  const PrepareNothingToDo();
}

class PrepareError extends PrepareOutcome {
  const PrepareError(this.status, this.message);
  final int status;
  final String message;
}

/// Outcome of an `upload` body.
class UploadOutcome {
  const UploadOutcome(this.status, [this.message = '']);
  final int status;
  final String message;
  bool get ok => status == 200;
}

/// Owns receive-side session state; the HTTP server is a thin adapter.
class SessionManager {
  SessionManager({required ReceiveDelegate delegate, Random? random})
    : _delegate = delegate,
      _random = random ?? Random.secure();

  static final _log = Logger('suvi.session');
  static const _uuid = Uuid();

  final ReceiveDelegate _delegate;
  final Random _random;

  ReceiveSession? _active;
  final Map<String, List<DateTime>> _rateHits = {};
  final Map<String, RandomAccessFile> _openFiles = {};
  Future<void> _renameTail = Future<void>.value();

  final StreamController<ReceiveSession> _updates =
      StreamController<ReceiveSession>.broadcast();

  /// Stream of snapshots for the UI.
  Stream<ReceiveSession> get updates => _updates.stream;
  ReceiveSession? get active => _active;

  bool get isBusy => _active != null && !_active!.status.isTerminal;

  // ---------------------------------------------------------------- prepare

  Future<PrepareOutcome> prepareUpload(
    PrepareUploadRequest req,
    String senderIp, {
    String? pin,
  }) async {
    if (!_allow(senderIp)) {
      return const PrepareError(429, 'Too many requests');
    }
    final requiredPin = _delegate.requiredPin;
    if (requiredPin != null && requiredPin.isNotEmpty && pin != requiredPin) {
      return const PrepareError(401, 'PIN required');
    }
    if (isBusy) {
      return const PrepareError(409, 'Busy with another session');
    }
    if (req.files.length > SuviConstants.maxFilesPerSession) {
      return const PrepareError(413, 'Too many files');
    }
    if (req.text != null &&
        utf8.encode(req.text!).length > SuviConstants.maxTextBytes) {
      return const PrepareError(413, 'Text too large');
    }

    final incoming = IncomingRequest(
      sender: req.info,
      senderIp: senderIp,
      files: req.files.values.toList(),
      text: req.text,
      pinProvided: pin,
    );

    // Reserve the slot while the user decides, so a second sender gets 409.
    final placeholder = ReceiveSession(
      sessionId: _uuid.v4(),
      sender: req.info,
      senderIp: senderIp,
      files: const {},
      status: SessionStatus.pendingDecision,
      saveDirectory: '',
      text: req.text,
      startedAt: DateTime.now(),
    );
    _active = placeholder;
    _publish();

    ReceiveDecision decision;
    try {
      decision = await _delegate
          .decide(incoming)
          .timeout(const Duration(minutes: 2));
    } catch (e) {
      _log.warning('delegate.decide threw: $e');
      decision = const ReceiveDecision.decline();
    }

    // The session might have been cancelled while the user was deciding.
    if (_active?.sessionId != placeholder.sessionId) {
      return const PrepareError(409, 'Session cancelled');
    }

    if (!decision.accepted) {
      _finish(SessionStatus.declined);
      return const PrepareError(403, 'Rejected');
    }

    final accepted = <String, ReceivingFile>{};
    final tokens = <String, String>{};
    for (final f in req.files.values) {
      if (!decision.acceptedFileIds.contains(f.id)) continue;
      final token = _token();
      tokens[f.id] = token;
      accepted[f.id] = ReceivingFile(
        file: f.copyWith(fileName: FilenameSanitizer.sanitize(f.fileName)),
        token: token,
      );
    }

    if (accepted.isEmpty && req.text == null) {
      _finish(SessionStatus.finished);
      return const PrepareNothingToDo();
    }

    _active = ReceiveSession(
      sessionId: placeholder.sessionId,
      sender: req.info,
      senderIp: senderIp,
      files: accepted,
      status: accepted.isEmpty
          ? SessionStatus.finished
          : SessionStatus.transferring,
      saveDirectory: decision.saveDirectory,
      text: req.text,
      startedAt: placeholder.startedAt,
      endedAt: accepted.isEmpty ? DateTime.now() : null,
    );
    _publish();
    if (accepted.isEmpty) _active = null;
    return PrepareAccepted(placeholder.sessionId, tokens);
  }

  // ----------------------------------------------------------------- upload

  /// Validates params; returns the target session/file or an error status.
  UploadOutcome _validate(
    String sessionId,
    String fileId,
    String token,
    String senderIp,
  ) {
    final s = _active;
    if (s == null || s.sessionId != sessionId) {
      return const UploadOutcome(404, 'Unknown session');
    }
    if (s.status != SessionStatus.transferring) {
      return const UploadOutcome(409, 'Session not accepting uploads');
    }
    final f = s.files[fileId];
    if (f == null) return const UploadOutcome(404, 'Unknown file');
    if (f.token != token || s.senderIp != senderIp) {
      return const UploadOutcome(403, 'Invalid token');
    }
    if (f.status == FileStatus.finished) {
      return const UploadOutcome(409, 'File already received');
    }
    return const UploadOutcome(200);
  }

  /// Bytes already on disk for a file (resume support).
  Future<UploadOutcome> uploadStatus(
    String sessionId,
    String fileId,
    String token,
    String senderIp,
  ) async {
    final v = _validate(sessionId, fileId, token, senderIp);
    if (!v.ok) return v;
    final f = _active!.files[fileId]!;
    return UploadOutcome(200, '${f.received}');
  }

  /// Streams [body] to disk. Returns 200 on success.
  Future<UploadOutcome> upload({
    required String sessionId,
    required String fileId,
    required String token,
    required String senderIp,
    required Stream<List<int>> body,
    int offset = 0,
    int? contentLength,
  }) async {
    final v = _validate(sessionId, fileId, token, senderIp);
    if (!v.ok) return v;
    final session = _active!;
    final rf = session.files[fileId]!;
    if (rf.status == FileStatus.sending) {
      return const UploadOutcome(409, 'File upload already in progress');
    }
    if (offset < 0 || offset > rf.received) {
      return const UploadOutcome(416, 'Offset beyond received bytes');
    }
    if (contentLength == null) {
      return const UploadOutcome(411, 'Content-Length required');
    }
    if (contentLength < 0 || contentLength + offset != rf.file.size) {
      return const UploadOutcome(400, 'Content-Length mismatch');
    }

    final dir = Directory(session.saveDirectory);
    try {
      if (!await dir.exists()) await dir.create(recursive: true);
    } catch (e) {
      return UploadOutcome(500, 'Cannot create save directory: $e');
    }

    final partPath = p.join(dir.path, '.${rf.file.id}.suvipart');
    if (!FilenameSanitizer.isInside(dir.path, partPath)) {
      return const UploadOutcome(400, 'Bad path');
    }
    final partFile = File(partPath);
    if (offset > 0) {
      if (!await partFile.exists() || await partFile.length() < offset) {
        return const UploadOutcome(416, 'Resume data is no longer available');
      }
    }

    _updateFile(
      fileId,
      (f) => f.copyWith(status: FileStatus.sending, received: offset),
    );

    RandomAccessFile? output;
    var received = offset;
    final progressClock = Stopwatch()..start();
    var lastPublishMs = 0;
    // Reuse one bounded buffer for the whole file. BytesBuilder.takeBytes()
    // allocates a new multi-megabyte Uint8List on every flush when a request
    // arrives as many TLS records. Sustained Android transfers then spend a
    // meaningful amount of CPU copying and collecting short-lived buffers,
    // especially after the activity moves to the background.
    final writeBuffer = Uint8List(SuviConstants.receiveWriteBufferSize);
    var bufferedBytes = 0;
    final digestCollector = rf.file.sha256 != null
        ? _DigestSinkCollector()
        : null;
    final hasher = digestCollector == null
        ? null
        : crypto.sha256.startChunkedConversion(digestCollector);

    try {
      if (offset > 0) {
        final truncateHandle = await partFile.open(mode: FileMode.append);
        await truncateHandle.truncate(offset);
        await truncateHandle.close();
        if (hasher != null) {
          await for (final chunk in partFile.openRead(0, offset)) {
            hasher.add(chunk);
          }
        }
        output = await partFile.open(mode: FileMode.append);
      } else {
        output = await partFile.open(mode: FileMode.write);
      }
      _openFiles[fileId] = output;

      Future<void> flushWriteBuffer() async {
        if (bufferedBytes == 0) return;
        await output!.writeFrom(writeBuffer, 0, bufferedBytes);
        bufferedBytes = 0;
      }

      try {
        await for (final chunk in body) {
          if (_active?.sessionId != sessionId) {
            throw const _CancelledException();
          }
          received += chunk.length;
          if (received > rf.file.size) {
            throw const FormatException('Body larger than declared size');
          }
          hasher?.add(chunk);

          var sourceOffset = 0;
          while (sourceOffset < chunk.length) {
            final available = writeBuffer.length - bufferedBytes;
            final byteCount = min(available, chunk.length - sourceOffset);
            writeBuffer.setRange(
              bufferedBytes,
              bufferedBytes + byteCount,
              chunk,
              sourceOffset,
            );
            bufferedBytes += byteCount;
            sourceOffset += byteCount;
            if (bufferedBytes == writeBuffer.length) {
              await flushWriteBuffer();
            }
          }

          final nowMs = progressClock.elapsedMilliseconds;
          if (nowMs - lastPublishMs >=
              SuviConstants.progressUpdateIntervalMs) {
            lastPublishMs = nowMs;
            _updateFile(fileId, (f) => f.copyWith(received: received));
          }
        }
      } catch (_) {
        // Preserve sub-buffer data after a transport drop so upload-status can
        // resume from every byte already received. A local cancellation clears
        // the active session and deliberately deletes the partial file.
        if (_active?.sessionId == sessionId) {
          await flushWriteBuffer();
        }
        rethrow;
      }
      await flushWriteBuffer();
      await output.flush();
      await output.close();
      _openFiles.remove(fileId);
      output = null;

      if (received != rf.file.size) {
        hasher?.close();
        _updateFile(
          fileId,
          (f) => f.copyWith(received: received, status: FileStatus.queued),
        );
        return const UploadOutcome(400, 'Incomplete body');
      }

      if (hasher != null) {
        hasher.close();
        final got = digestCollector?.digest?.toString();
        if (got != null && got != rf.file.sha256!.toLowerCase()) {
          await _safeDelete(partFile);
          _updateFile(
            fileId,
            (f) => f.copyWith(
              status: FileStatus.failed,
              received: 0,
              error: 'Checksum mismatch',
            ),
          );
          _maybeFinish();
          return const UploadOutcome(422, 'Checksum mismatch');
        }
      }

      final finalPath = await _commitPartFile(
        partFile,
        dir.path,
        rf.file.fileName,
      );
      if (rf.file.modified != null) {
        try {
          await File(finalPath).setLastModified(rf.file.modified!);
        } catch (_) {}
      }
      _updateFile(
        fileId,
        (f) => f.copyWith(
          status: FileStatus.finished,
          received: rf.file.size,
          savedPath: finalPath,
        ),
      );
      _maybeFinish();
      return const UploadOutcome(200);
    } on _CancelledException {
      await _closeQuietly(output, fileId);
      await _safeDelete(partFile);
      return const UploadOutcome(409, 'Cancelled');
    } catch (e, st) {
      _log.warning('upload $fileId failed: $e', e, st);
      await _closeQuietly(output, fileId);
      // Keep the .suvipart for resume; mark as queued with bytes on disk.
      final onDisk = await partFile.exists() ? await partFile.length() : 0;
      _updateFile(
        fileId,
        (f) => f.copyWith(
          status: FileStatus.queued,
          received: onDisk,
          error: '$e',
        ),
      );
      return UploadOutcome(500, 'Write failed: $e');
    }
  }

  // ----------------------------------------------------------------- cancel

  /// Called by the sender (`POST /cancel`) or the local user.
  Future<bool> cancel(
    String sessionId, {
    bool byReceiver = false,
    String? senderIp,
  }) async {
    final s = _active;
    if (s == null || s.sessionId != sessionId) return false;
    if (!byReceiver && senderIp != null && senderIp != s.senderIp) return false;
    for (final file in _openFiles.values) {
      try {
        await file.close();
      } catch (_) {}
    }
    _openFiles.clear();
    for (final f in s.files.values) {
      if (f.status != FileStatus.finished && s.saveDirectory.isNotEmpty) {
        await _safeDelete(
          File(p.join(s.saveDirectory, '.${f.file.id}.suvipart')),
        );
      }
    }
    _finish(
      byReceiver
          ? SessionStatus.cancelledByReceiver
          : SessionStatus.cancelledBySender,
    );
    return true;
  }

  /// Local user cancels whatever is active.
  Future<void> cancelActive() async {
    final s = _active;
    if (s != null) await cancel(s.sessionId, byReceiver: true);
  }

  // ---------------------------------------------------------------- helpers

  void _maybeFinish() {
    final s = _active;
    if (s == null) return;
    final pending = s.files.values.any(
      (f) => f.status == FileStatus.queued || f.status == FileStatus.sending,
    );
    if (pending) return;
    _finish(
      s.failedCount > 0
          ? SessionStatus.finishedWithErrors
          : SessionStatus.finished,
    );
  }

  void _finish(SessionStatus status) {
    final s = _active;
    if (s == null) return;
    _active = s.copyWith(status: status, endedAt: DateTime.now());
    _publish();
    _active = null;
  }

  void _updateFile(String fileId, ReceivingFile Function(ReceivingFile) fn) {
    final s = _active;
    if (s == null) return;
    final f = s.files[fileId];
    if (f == null) return;
    final files = Map<String, ReceivingFile>.from(s.files)..[fileId] = fn(f);
    _active = s.copyWith(files: files);
    _publish();
  }

  void _publish() {
    final s = _active;
    if (s == null) return;
    if (!_updates.isClosed) _updates.add(s);
    try {
      _delegate.onSessionUpdate(s);
    } catch (_) {}
  }

  bool _allow(String ip) {
    final now = DateTime.now();
    final hits = _rateHits.putIfAbsent(ip, () => []);
    hits.removeWhere((t) => now.difference(t) > const Duration(minutes: 1));
    if (hits.length >= SuviConstants.prepareRateLimitPerMinute) return false;
    hits.add(now);
    return true;
  }

  String _token() {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return List.generate(
      32,
      (_) => chars[_random.nextInt(chars.length)],
    ).join();
  }

  Future<String> _commitPartFile(
    File partFile,
    String dir,
    String fileName,
  ) async {
    final previous = _renameTail;
    final done = Completer<void>();
    _renameTail = done.future;
    await previous;
    try {
      final finalPath = await _uniquePath(dir, fileName);
      if (!FilenameSanitizer.isInside(dir, finalPath)) {
        throw const FileSystemException('Resolved path escaped save directory');
      }
      await partFile.rename(finalPath);
      return finalPath;
    } finally {
      done.complete();
    }
  }

  static Future<String> _uniquePath(String dir, String fileName) async {
    var candidate = p.join(dir, fileName);
    if (!await File(candidate).exists() &&
        !await Directory(candidate).exists()) {
      return candidate;
    }
    final (stem, ext) = FilenameSanitizer.split(fileName);
    for (var i = 1; i < 10000; i++) {
      candidate = p.join(dir, '$stem ($i)$ext');
      if (!await File(candidate).exists() &&
          !await Directory(candidate).exists()) {
        return candidate;
      }
    }
    return p.join(dir, '$stem (${DateTime.now().millisecondsSinceEpoch})$ext');
  }

  Future<void> _closeQuietly(RandomAccessFile? file, String fileId) async {
    _openFiles.remove(fileId);
    if (file == null) return;
    try {
      await file.close();
    } catch (_) {}
  }

  static Future<void> _safeDelete(File f) async {
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  Future<void> dispose() async {
    await cancelActive();
    await _updates.close();
  }
}

class _CancelledException implements Exception {
  const _CancelledException();
}

class _DigestSinkCollector implements Sink<crypto.Digest> {
  crypto.Digest? digest;
  @override
  void add(crypto.Digest data) => digest = data;
  @override
  void close() {}
}
