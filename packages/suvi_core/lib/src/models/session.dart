import 'package:meta/meta.dart';

import '../constants.dart';
import 'device_info.dart';
import 'file_dto.dart';

/// Request body of `POST /prepare-upload`.
@immutable
class PrepareUploadRequest {
  const PrepareUploadRequest({
    required this.info,
    required this.files,
    this.text,
  });

  final DeviceInfo info;

  /// Keyed by file id.
  final Map<String, FileDto> files;

  /// Suvi extension: a short text payload (clipboard / message).
  final String? text;

  int get totalSize => files.values.fold(0, (a, f) => a + f.size);

  Map<String, dynamic> toJson() => {
    'info': info.toJson(),
    'files': {for (final f in files.values) f.id: f.toJson()},
    if (text != null) 'text': text,
  };

  static PrepareUploadRequest? tryParse(Object? json) {
    if (json is! Map) return null;
    final info = DeviceInfo.tryParse(json['info']);
    if (info == null) return null;
    final rawFiles = json['files'];
    final files = <String, FileDto>{};
    if (rawFiles is Map) {
      if (rawFiles.length > SuviConstants.maxFilesPerSession) return null;
      for (final entry in rawFiles.entries) {
        if (entry.key is! String) return null;
        final f = FileDto.tryParse(entry.value);
        if (f == null || entry.key != f.id || files.containsKey(f.id)) {
          return null;
        }
        files[f.id] = f;
      }
    } else if (rawFiles != null) {
      return null;
    }
    final text = json['text'];
    if (files.isEmpty && text is! String) return null;
    return PrepareUploadRequest(
      info: info,
      files: files,
      text: text is String ? text : null,
    );
  }
}

/// Response body of `POST /prepare-upload`.
@immutable
class PrepareUploadResponse {
  const PrepareUploadResponse({required this.sessionId, required this.files});

  final String sessionId;

  /// fileId → fileToken for each accepted file.
  final Map<String, String> files;

  Map<String, dynamic> toJson() => {'sessionId': sessionId, 'files': files};

  static PrepareUploadResponse? tryParse(Object? json) {
    if (json is! Map) return null;
    final sessionId = json['sessionId'];
    final files = json['files'];
    if (sessionId is! String || files is! Map) return null;
    return PrepareUploadResponse(
      sessionId: sessionId,
      files: {
        for (final e in files.entries)
          if (e.key is String && e.value is String)
            e.key as String: e.value as String,
      },
    );
  }
}

/// State of a single file inside a session.
enum FileStatus { queued, sending, finished, failed, skipped }

/// State of a whole session (send or receive).
enum SessionStatus {
  /// Sender: waiting for the receiver to accept.
  waiting,

  /// Receiver: waiting for local user decision.
  pendingDecision,
  declined,
  transferring,
  finished,
  finishedWithErrors,
  cancelledBySender,
  cancelledByReceiver,
  failed,
}

extension SessionStatusX on SessionStatus {
  bool get isTerminal => switch (this) {
    SessionStatus.waiting ||
    SessionStatus.pendingDecision ||
    SessionStatus.transferring => false,
    _ => true,
  };
}
