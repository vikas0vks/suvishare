import 'package:path/path.dart' as p;

/// Makes attacker-controlled file names safe to write under a save directory.
class FilenameSanitizer {
  FilenameSanitizer._();

  static final RegExp _illegal = RegExp(r'[\\/:*?"<>|\x00-\x1F\x7F]');
  static final RegExp _trailingDotsSpaces = RegExp(r'[. ]+$');
  static const Set<String> _windowsReserved = {
    'CON',
    'PRN',
    'AUX',
    'NUL',
    'COM1',
    'COM2',
    'COM3',
    'COM4',
    'COM5',
    'COM6',
    'COM7',
    'COM8',
    'COM9',
    'LPT1',
    'LPT2',
    'LPT3',
    'LPT4',
    'LPT5',
    'LPT6',
    'LPT7',
    'LPT8',
    'LPT9',
  };

  /// Returns a safe basename. Never returns empty, `.` or `..`.
  static String sanitize(String raw, {String fallback = 'file'}) {
    // Take the basename on both separators (the peer might be Windows).
    var name = raw.replaceAll('\\', '/');
    name = name.split('/').last;
    name = name.replaceAll(_illegal, '_');
    name = name.replaceAll(_trailingDotsSpaces, '');
    name = name.trim();
    if (name.isEmpty || name == '.' || name == '..') name = fallback;
    final stem = p.basenameWithoutExtension(name).toUpperCase();
    if (_windowsReserved.contains(stem)) name = '_$name';
    if (name.length > 200) {
      final ext = p.extension(name);
      final keep = 200 - ext.length;
      name = name.substring(0, keep < 1 ? 1 : keep) + ext;
    }
    return name;
  }

  /// Splits `name.ext` → (`name`, `.ext`).
  static (String, String) split(String name) {
    final ext = p.extension(name);
    final stem = ext.isEmpty
        ? name
        : name.substring(0, name.length - ext.length);
    return (stem, ext);
  }

  /// Returns `true` if [candidate] resolves to a path inside [root].
  static bool isInside(String root, String candidate) {
    final r = p.normalize(p.absolute(root));
    final c = p.normalize(p.absolute(candidate));
    return p.isWithin(r, c) || p.equals(r, c);
  }
}
