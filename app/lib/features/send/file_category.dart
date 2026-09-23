/// User-facing file groups. These affect only the native picker filter; once a
/// file is selected it follows the same streaming, checksum, and TLS path as
/// every other [SendItem].
enum ShareFileCategory {
  general,
  documents,
  images,
  videos,
  music,
  compressed,
  other,
}

extension ShareFileCategoryFilters on ShareFileCategory {
  /// Android Storage Access Framework MIME filters. `null` means all files.
  List<String>? get mimeTypes => switch (this) {
    ShareFileCategory.general => null,
    ShareFileCategory.documents => const [
      'application/pdf',
      'text/*',
      'application/rtf',
      'application/msword',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'application/vnd.ms-excel',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'application/vnd.ms-powerpoint',
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'application/vnd.oasis.opendocument.text',
      'application/vnd.oasis.opendocument.spreadsheet',
      'application/epub+zip',
    ],
    ShareFileCategory.images => const ['image/*'],
    ShareFileCategory.videos => const ['video/*'],
    ShareFileCategory.music => const ['audio/*'],
    ShareFileCategory.compressed => const [
      'application/zip',
      'application/x-7z-compressed',
      'application/vnd.rar',
      'application/gzip',
      'application/x-tar',
      'application/x-bzip2',
    ],
    ShareFileCategory.other => const [
      'application/octet-stream',
      'application/vnd.android.package-archive',
      'application/x-msdownload',
      'application/x-iso9660-image',
      'application/json',
      'application/xml',
    ],
  };

  /// Desktop extension filters for categories that have no portable picker
  /// type. Unknown formats remain available through General.
  List<String>? get extensions => switch (this) {
    ShareFileCategory.documents => const [
      'pdf',
      'txt',
      'md',
      'rtf',
      'doc',
      'docx',
      'xls',
      'xlsx',
      'ppt',
      'pptx',
      'odt',
      'ods',
      'odp',
      'csv',
      'epub',
    ],
    ShareFileCategory.compressed => const [
      'zip',
      '7z',
      'rar',
      'tar',
      'gz',
      'tgz',
      'bz2',
      'xz',
      'zst',
    ],
    ShareFileCategory.other => const [
      'apk',
      'aab',
      'exe',
      'msi',
      'appx',
      'msix',
      'dmg',
      'pkg',
      'deb',
      'rpm',
      'iso',
      'img',
      'bin',
      'dat',
      'db',
      'sqlite',
      'json',
      'xml',
      'yaml',
      'yml',
    ],
    _ => null,
  };
}
