import 'dart:io';

import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:mime/mime.dart';
import 'package:suvi_core/suvi_core.dart';
import 'package:uri_content/uri_content.dart';

/// Zero-copy file picking for Android.
///
/// The file_picker plugin copies every selection into the app cache before
/// returning to Dart; a multi-GB movie makes that copy slow or fail, and a
/// failure silently drops the file from the result — the "I picked a big file
/// and nothing appeared" bug. This channel returns SAF `content://` URIs
/// immediately, and the files are streamed straight from their source at send
/// time via uri_content. Nothing is ever duplicated on disk.
class NativeFilePicker {
  NativeFilePicker._();

  static final _log = Logger('suvi.nativepicker');
  static const _channel = MethodChannel('com.suvishare/native_picker');
  static final _uriContent = UriContent();

  static bool get isSupported => Platform.isAndroid;

  /// Opens the system document picker. [mimeTypes] filters what is shown
  /// (e.g. `['image/*', 'video/*']`); defaults to everything.
  /// Returns [SendItem]s that stream directly from the picked URIs.
  static Future<List<SendItem>> pickFiles({List<String>? mimeTypes}) async {
    if (!isSupported) return const [];
    List<Object?> raw;
    try {
      raw =
          await _channel.invokeMethod<List<Object?>>('pickFiles', {
            'mimeTypes': mimeTypes ?? const ['*/*'],
          }) ??
          const [];
    } catch (e) {
      _log.warning('native pick failed: $e');
      rethrow;
    }

    final items = <SendItem>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final uriStr = entry['uri'] as String?;
      final name = (entry['name'] as String?) ?? 'file';
      final size = (entry['size'] as num?)?.toInt() ?? -1;
      if (uriStr == null) continue;
      final uri = Uri.parse(uriStr);
      items.add(
        SendItem.stream(
          name: name,
          opener: () => _uriContent.getContentStream(uri),
          // SIZE can be unknown (-1) for some providers; fall back to asking the
          // resolver, and only then to 0 (the receiver validates by stream end).
          size: size >= 0 ? size : null,
          sizer: () async => await _uriContent.getContentLength(uri) ?? 0,
          mime: lookupMimeType(name) ?? 'application/octet-stream',
        ),
      );
    }
    return items;
  }
}
