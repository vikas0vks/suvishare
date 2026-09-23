import 'dart:convert';

import 'package:meta/meta.dart';

import '../constants.dart';

/// Metadata about one file in a transfer session.
@immutable
class FileDto {
  const FileDto({
    required this.id,
    required this.fileName,
    required this.size,
    required this.fileType,
    this.sha256,
    this.preview,
    this.modified,
    this.accessed,
  });

  final String id;
  final String fileName;
  final int size;

  /// MIME type, e.g. `image/jpeg`; `application/octet-stream` if unknown.
  final String fileType;
  final String? sha256;

  /// Base64 thumbnail (≤ 32 KB), optional.
  final String? preview;
  final DateTime? modified;
  final DateTime? accessed;

  bool get isImage => fileType.startsWith('image/');
  bool get isVideo => fileType.startsWith('video/');
  bool get isAudio => fileType.startsWith('audio/');
  bool get isText => fileType.startsWith('text/');
  bool get isApk => fileType == 'application/vnd.android.package-archive';

  Map<String, dynamic> toJson() => {
    'id': id,
    'fileName': fileName,
    'size': size,
    'fileType': fileType,
    if (sha256 != null) 'sha256': sha256,
    if (preview != null) 'preview': preview,
    'metadata': {
      'modified': modified?.toUtc().toIso8601String(),
      'accessed': accessed?.toUtc().toIso8601String(),
    },
  };

  static FileDto? tryParse(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final fileName = json['fileName'];
    final size = json['size'];
    if (id is! String || fileName is! String || size is! int) return null;
    if (id.isEmpty ||
        utf8.encode(id).length > SuviConstants.maxFileIdBytes ||
        !RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(id) ||
        fileName.isEmpty ||
        utf8.encode(fileName).length > SuviConstants.maxFileNameBytes ||
        size < 0 ||
        size > SuviConstants.maxDeclaredFileBytes) {
      return null;
    }
    final fileType = json['fileType'];
    if (fileType != null &&
        (fileType is! String ||
            fileType.isEmpty ||
            utf8.encode(fileType).length > SuviConstants.maxMimeBytes)) {
      return null;
    }
    final sha256 = json['sha256'];
    if (sha256 != null &&
        (sha256 is! String || !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(sha256))) {
      return null;
    }
    final preview = json['preview'];
    if (preview != null) {
      if (preview is! String || preview.length > 44000) return null;
      try {
        if (base64Decode(preview).length > SuviConstants.maxPreviewBytes) {
          return null;
        }
      } on FormatException {
        return null;
      }
    }
    final meta = json['metadata'];
    DateTime? parseDate(Object? v) => v is String ? DateTime.tryParse(v) : null;
    return FileDto(
      id: id,
      fileName: fileName,
      size: size,
      fileType: (fileType as String?) ?? 'application/octet-stream',
      sha256: (sha256 as String?)?.toLowerCase(),
      preview: preview as String?,
      modified: meta is Map ? parseDate(meta['modified']) : null,
      accessed: meta is Map ? parseDate(meta['accessed']) : null,
    );
  }

  factory FileDto.fromJson(Map<String, dynamic> json) {
    final parsed = tryParse(json);
    if (parsed == null) throw const FormatException('Invalid FileDto');
    return parsed;
  }

  FileDto copyWith({String? fileName}) => FileDto(
    id: id,
    fileName: fileName ?? this.fileName,
    size: size,
    fileType: fileType,
    sha256: sha256,
    preview: preview,
    modified: modified,
    accessed: accessed,
  );

  @override
  bool operator ==(Object other) =>
      other is FileDto &&
      other.id == id &&
      other.fileName == fileName &&
      other.size == size &&
      other.fileType == fileType &&
      other.sha256 == sha256;

  @override
  int get hashCode => Object.hash(id, fileName, size, fileType, sha256);

  @override
  String toString() => 'FileDto($fileName, $size B, $fileType)';
}
