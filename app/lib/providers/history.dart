import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:suvi_core/suvi_core.dart';
import 'package:uuid/uuid.dart';

import '../core/util/atomic_file.dart';

enum HistoryDirection { sent, received }

@immutable
class HistoryFile {
  const HistoryFile({
    required this.name,
    required this.size,
    required this.mime,
    this.path,
  });
  final String name;
  final int size;
  final String mime;
  final String? path;

  Map<String, dynamic> toJson() => {
    'name': name,
    'size': size,
    'mime': mime,
    'path': path,
  };
  static HistoryFile fromJson(Map<String, dynamic> j) => HistoryFile(
    name: j['name'] as String,
    size: (j['size'] as num).toInt(),
    mime: (j['mime'] as String?) ?? 'application/octet-stream',
    path: j['path'] as String?,
  );
}

@immutable
class HistoryEntry {
  const HistoryEntry({
    required this.id,
    required this.direction,
    required this.peerAlias,
    required this.peerFingerprint,
    required this.status,
    required this.files,
    required this.timestamp,
    this.text,
  });

  final String id;
  final HistoryDirection direction;
  final String peerAlias;
  final String peerFingerprint;
  final SessionStatus status;
  final List<HistoryFile> files;
  final DateTime timestamp;
  final String? text;

  int get totalSize => files.fold(0, (a, f) => a + f.size);

  Map<String, dynamic> toJson() => {
    'id': id,
    'direction': direction.name,
    'peerAlias': peerAlias,
    'peerFingerprint': peerFingerprint,
    'status': status.name,
    'files': files.map((f) => f.toJson()).toList(),
    'timestamp': timestamp.toIso8601String(),
    'text': text,
  };

  static HistoryEntry fromJson(Map<String, dynamic> j) => HistoryEntry(
    id: j['id'] as String,
    direction: HistoryDirection.values.firstWhere(
      (d) => d.name == j['direction'],
      orElse: () => HistoryDirection.received,
    ),
    peerAlias: j['peerAlias'] as String,
    peerFingerprint: (j['peerFingerprint'] as String?) ?? '',
    status: SessionStatus.values.firstWhere(
      (s) => s.name == j['status'],
      orElse: () => SessionStatus.finished,
    ),
    files: ((j['files'] as List?) ?? const [])
        .map((e) => HistoryFile.fromJson(e as Map<String, dynamic>))
        .toList(),
    timestamp:
        DateTime.tryParse(j['timestamp'] as String? ?? '') ?? DateTime.now(),
    text: j['text'] as String?,
  );
}

class HistoryNotifier extends AsyncNotifier<List<HistoryEntry>> {
  File? _file;
  Future<void> _saveTail = Future<void>.value();

  @override
  Future<List<HistoryEntry>> build() async {
    final dir = await getApplicationSupportDirectory();
    _file = File(p.join(dir.path, 'history.json'));
    if (!await _file!.exists()) return const [];
    try {
      final raw = jsonDecode(await _file!.readAsString()) as List;
      return raw
          .map((e) => HistoryEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> add(HistoryEntry e) async {
    final cur = state.value ?? const [];
    final next = [e, ...cur.where((x) => x.id != e.id)];
    state = AsyncData(next.length > 500 ? next.sublist(0, 500) : next);
    await _save();
  }

  Future<void> remove(String id) async {
    state = AsyncData(
      (state.value ?? const []).where((e) => e.id != id).toList(),
    );
    await _save();
  }

  Future<void> clear() async {
    state = const AsyncData([]);
    await _save();
  }

  Future<void> _save() async {
    final file = _file;
    if (file == null) return;
    final encoded = jsonEncode(
      (state.value ?? const []).map((e) => e.toJson()).toList(),
    );
    final write = _saveTail.then(
      (_) => writeAtomic(file, encoded, private: true),
    );
    _saveTail = write.catchError((_) {});
    try {
      await write;
    } catch (_) {}
  }

  static String newId() => const Uuid().v4();
}

final historyProvider =
    AsyncNotifierProvider<HistoryNotifier, List<HistoryEntry>>(
      HistoryNotifier.new,
    );
