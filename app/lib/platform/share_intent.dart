import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:suvi_core/suvi_core.dart';

/// Content handed to us by the system share sheet.
class SharedPayload {
  const SharedPayload({this.items = const [], this.text});
  final List<SendItem> items;
  final String? text;

  bool get isEmpty => items.isEmpty && (text == null || text!.isEmpty);
}

/// Bridges Android's `ACTION_SEND` / `ACTION_SEND_MULTIPLE` into the send flow,
/// so Suvi Share appears in the system share sheet of every other app.
///
/// Handles both entry points: a cold start (the app was launched *by* the share)
/// and a warm share while the app is already running.
class ShareIntentListener {
  static final _log = Logger('suvi.shareintent');

  final _controller = StreamController<SharedPayload>.broadcast();
  StreamSubscription<List<SharedMediaFile>>? _sub;
  bool _started = false;

  Stream<SharedPayload> get payloads => _controller.stream;

  static bool get _supported => Platform.isAndroid || Platform.isIOS;

  Future<void> start() async {
    if (!_supported || _started) return;
    _started = true;
    try {
      _sub = ReceiveSharingIntent.instance.getMediaStream().listen(
        (files) => _emit(files),
        onError: (Object e) => _log.warning('share stream error: $e'),
      );
      // The share that launched the app, if any.
      final initial = await ReceiveSharingIntent.instance.getInitialMedia();
      if (initial.isNotEmpty) {
        _emit(initial);
        // Tell the plugin we consumed it, or it replays on the next resume.
        ReceiveSharingIntent.instance.reset();
      }
    } catch (e) {
      _log.warning('share intent unavailable: $e');
    }
  }

  void _emit(List<SharedMediaFile> files) {
    if (files.isEmpty) return;
    final items = <SendItem>[];
    final texts = <String>[];
    for (final f in files) {
      switch (f.type) {
        case SharedMediaType.text:
        case SharedMediaType.url:
          texts.add(f.path);
        case SharedMediaType.image:
        case SharedMediaType.video:
        case SharedMediaType.file:
          if (f.path.isNotEmpty && File(f.path).existsSync()) {
            items.add(SendItem.file(f.path, mime: f.mimeType));
          }
      }
    }
    final payload = SharedPayload(
      items: items,
      text: texts.isEmpty ? null : texts.join('\n'),
    );
    if (payload.isEmpty) return;
    _log.fine('shared: ${items.length} file(s), text=${texts.isNotEmpty}');
    if (!_controller.isClosed) _controller.add(payload);
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    await _controller.close();
  }
}
