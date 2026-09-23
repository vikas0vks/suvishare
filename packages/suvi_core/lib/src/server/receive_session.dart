import 'package:meta/meta.dart';

import '../models/device_info.dart';
import '../models/file_dto.dart';
import '../models/session.dart';

/// Per-file progress on the receiving side.
@immutable
class ReceivingFile {
  const ReceivingFile({
    required this.file,
    required this.token,
    this.status = FileStatus.queued,
    this.received = 0,
    this.savedPath,
    this.error,
  });

  final FileDto file;
  final String token;
  final FileStatus status;
  final int received;
  final String? savedPath;
  final String? error;

  ReceivingFile copyWith({
    FileStatus? status,
    int? received,
    String? savedPath,
    String? error,
  }) => ReceivingFile(
    file: file,
    token: token,
    status: status ?? this.status,
    received: received ?? this.received,
    savedPath: savedPath ?? this.savedPath,
    error: error ?? this.error,
  );
}

/// Immutable snapshot of a receive session. The [SessionManager] owns the
/// mutable state and publishes snapshots on every change.
@immutable
class ReceiveSession {
  const ReceiveSession({
    required this.sessionId,
    required this.sender,
    required this.senderIp,
    required this.files,
    required this.status,
    required this.saveDirectory,
    required this.startedAt,
    this.text,
    this.endedAt,
  });

  final String sessionId;
  final DeviceInfo sender;
  final String senderIp;

  /// Only files the user accepted. Keyed by fileId.
  final Map<String, ReceivingFile> files;
  final SessionStatus status;
  final String saveDirectory;
  final String? text;
  final DateTime startedAt;
  final DateTime? endedAt;

  int get totalBytes => files.values.fold(0, (a, f) => a + f.file.size);
  int get receivedBytes => files.values.fold(0, (a, f) => a + f.received);
  double get progress => totalBytes == 0 ? 1 : receivedBytes / totalBytes;
  int get finishedCount =>
      files.values.where((f) => f.status == FileStatus.finished).length;
  int get failedCount =>
      files.values.where((f) => f.status == FileStatus.failed).length;

  ReceiveSession copyWith({
    Map<String, ReceivingFile>? files,
    SessionStatus? status,
    DateTime? endedAt,
  }) => ReceiveSession(
    sessionId: sessionId,
    sender: sender,
    senderIp: senderIp,
    files: files ?? this.files,
    status: status ?? this.status,
    saveDirectory: saveDirectory,
    text: text,
    startedAt: startedAt,
    endedAt: endedAt ?? this.endedAt,
  );
}

/// Incoming request presented to the app for a decision.
@immutable
class IncomingRequest {
  const IncomingRequest({
    required this.sender,
    required this.senderIp,
    required this.files,
    this.text,
    this.pinProvided,
  });

  final DeviceInfo sender;
  final String senderIp;
  final List<FileDto> files;
  final String? text;
  final String? pinProvided;

  int get totalSize => files.fold(0, (a, f) => a + f.size);
}

/// The app's answer to an [IncomingRequest].
@immutable
class ReceiveDecision {
  const ReceiveDecision.accept(
    this.acceptedFileIds, {
    required this.saveDirectory,
  }) : accepted = true;

  const ReceiveDecision.decline()
    : accepted = false,
      acceptedFileIds = const {},
      saveDirectory = '';

  final bool accepted;
  final Set<String> acceptedFileIds;
  final String saveDirectory;
}

/// Policy hooks implemented by the app layer (UI/settings).
abstract class ReceiveDelegate {
  /// PIN required for `prepare-upload`, or `null` for none.
  String? get requiredPin;

  /// Asked for every incoming request. May block on user interaction.
  /// Throwing or returning decline → 403.
  Future<ReceiveDecision> decide(IncomingRequest request);

  /// Called when the session snapshot changes.
  void onSessionUpdate(ReceiveSession session) {}
}
