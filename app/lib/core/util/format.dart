import 'package:flutter/material.dart';
import 'package:suvi_core/suvi_core.dart';

import '../../l10n/app_localizations.dart';

String formatBytes(int bytes, {int decimals = 1}) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var v = bytes / 1024;
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  final d = v >= 100 ? 0 : decimals;
  return '${v.toStringAsFixed(d)} ${units[i]}';
}

String formatSpeed(double bytesPerSecond) =>
    '${formatBytes(bytesPerSecond.round())}/s';

String formatEta(Duration d) {
  if (d.inSeconds < 60) return '${d.inSeconds}s';
  if (d.inMinutes < 60) return '${d.inMinutes}m ${d.inSeconds % 60}s';
  return '${d.inHours}h ${d.inMinutes % 60}m';
}

IconData iconForMime(String mime, {String? fileName}) {
  if (mime.startsWith('image/')) return Icons.image_rounded;
  if (mime.startsWith('video/')) return Icons.movie_rounded;
  if (mime.startsWith('audio/')) return Icons.audiotrack_rounded;
  if (mime == 'application/vnd.android.package-archive') {
    return Icons.android_rounded;
  }
  if (mime == 'application/pdf') return Icons.picture_as_pdf_rounded;
  if (mime.contains('zip') ||
      mime.contains('compressed') ||
      mime.contains('tar')) {
    return Icons.folder_zip_rounded;
  }
  if (mime.startsWith('text/') ||
      mime.contains('document') ||
      mime.contains('word')) {
    return Icons.description_rounded;
  }
  if (mime.contains('sheet') ||
      mime.contains('excel') ||
      mime.contains('csv')) {
    return Icons.table_chart_rounded;
  }
  if (mime.contains('presentation')) return Icons.slideshow_rounded;
  return Icons.insert_drive_file_rounded;
}

IconData iconForDevice(DeviceType t) => switch (t) {
  DeviceType.mobile => Icons.smartphone_rounded,
  DeviceType.desktop => Icons.computer_rounded,
  DeviceType.web => Icons.language_rounded,
  DeviceType.headless => Icons.terminal_rounded,
  DeviceType.server => Icons.dns_rounded,
};

String statusLabel(AppLocalizations l, SessionStatus s) => switch (s) {
  SessionStatus.finished => l.done,
  SessionStatus.finishedWithErrors => l.failed,
  SessionStatus.failed => l.failed,
  SessionStatus.declined => l.declined,
  SessionStatus.cancelledBySender ||
  SessionStatus.cancelledByReceiver => l.cancelled,
  SessionStatus.waiting => '…',
  SessionStatus.pendingDecision => '…',
  SessionStatus.transferring => '…',
};

/// Simple moving-average throughput meter.
class SpeedMeter {
  final List<(DateTime, int)> _samples = [];
  double _last = 0;

  double update(int bytes) {
    final now = DateTime.now();
    _samples.add((now, bytes));
    _samples.removeWhere(
      (s) => now.difference(s.$1) > const Duration(seconds: 3),
    );
    if (_samples.length < 2) return _last;
    final first = _samples.first;
    final dt = now.difference(first.$1).inMilliseconds / 1000.0;
    if (dt <= 0) return _last;
    _last = (bytes - first.$2) / dt;
    return _last < 0 ? 0 : _last;
  }

  double get value => _last;
}
