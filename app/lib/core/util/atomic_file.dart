import 'dart:io';

var _writeSequence = 0;

/// Writes a complete replacement beside [target] and renames it into place.
/// The previous file remains readable until the replacement is fully flushed.
Future<void> writeAtomic(
  File target,
  String contents, {
  bool private = false,
}) async {
  await target.parent.create(recursive: true);
  final temporary = File('${target.path}.$pid.${_writeSequence++}.tmp');
  try {
    await temporary.writeAsString(contents, flush: true);
    try {
      await temporary.rename(target.path);
    } on FileSystemException {
      // Windows does not consistently replace an existing destination.
      if (await target.exists()) await target.delete();
      await temporary.rename(target.path);
    }
    if (private && (Platform.isLinux || Platform.isMacOS)) {
      await Process.run('chmod', ['600', target.path]);
    }
  } finally {
    if (await temporary.exists()) await temporary.delete();
  }
}
