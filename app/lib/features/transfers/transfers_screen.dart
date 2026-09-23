import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:suvi_core/suvi_core.dart';

import '../../core/theme/app_theme.dart';
import '../../core/util/format.dart';
import '../../l10n/app_localizations.dart';
import '../../platform/open_location.dart';
import '../../providers/app_services.dart';
import '../../providers/history.dart';

class TransfersScreen extends ConsumerStatefulWidget {
  const TransfersScreen({super.key});

  @override
  ConsumerState<TransfersScreen> createState() => _TransfersScreenState();
}

class _TransfersScreenState extends ConsumerState<TransfersScreen> {
  int _segment = 0;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final history = ref.watch(historyProvider).value ?? const <HistoryEntry>[];
    final sends = ref
        .watch(sendSessionsProvider)
        .values
        .where((s) => !s.status.isTerminal)
        .toList();
    final receive = ref.watch(receiveSessionProvider);
    final activeCount =
        sends.length +
        ((receive != null && !receive.status.isTerminal) ? 1 : 0);
    final wc = windowClassOf(MediaQuery.sizeOf(context).width);
    final pad = wc == WindowClass.compact ? SuviSpacing.lg : SuviSpacing.xl;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.navTransfers),
        actions: [
          if (history.isNotEmpty)
            IconButton(
              tooltip: l.clearHistory,
              icon: const Icon(Icons.delete_sweep_rounded),
              onPressed: () => ref.read(historyProvider.notifier).clear(),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: EdgeInsets.fromLTRB(pad, 0, pad, SuviSpacing.md),
            child: SegmentedButton<int>(
              segments: [
                ButtonSegment(
                  value: 0,
                  icon: const Icon(Icons.sync_rounded),
                  label: Text(
                    activeCount > 0 ? '${l.active} ($activeCount)' : l.active,
                  ),
                ),
                ButtonSegment(
                  value: 1,
                  icon: const Icon(Icons.history_rounded),
                  label: Text(l.history),
                ),
              ],
              selected: {_segment},
              onSelectionChanged: (s) => setState(() => _segment = s.first),
            ),
          ),
        ),
      ),
      body: _segment == 0
          ? _ActiveList(sends: sends, receive: receive, padding: pad)
          : _HistoryList(entries: history, padding: pad),
    );
  }
}

class _ActiveList extends ConsumerWidget {
  const _ActiveList({
    required this.sends,
    required this.receive,
    required this.padding,
  });
  final List<SendSession> sends;
  final ReceiveSession? receive;
  final double padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final showReceive = receive != null && !receive!.status.isTerminal;
    if (sends.isEmpty && !showReceive) {
      return _Empty(
        icon: Icons.sync_rounded,
        title: l.noTransfersYet,
        body: l.noTransfersBody,
      );
    }
    return ListView(
      padding: EdgeInsets.fromLTRB(padding, 0, padding, SuviSpacing.xxl),
      children: [
        if (showReceive)
          _ActiveCard(
            title: l.receivingFrom(receive!.sender.alias),
            subtitle:
                '${formatBytes(receive!.receivedBytes)} / ${formatBytes(receive!.totalBytes)}',
            progress: receive!.progress,
            icon: Icons.download_rounded,
            color: scheme.primary,
            onCancel: () =>
                ref.read(appServicesProvider).value?.sessions.cancelActive(),
          ),
        for (final s in sends)
          _ActiveCard(
            title: l.sendingTo(s.target.alias),
            subtitle: s.status == SessionStatus.waiting
                ? l.waitingForAccept(s.target.alias)
                : '${formatBytes(s.sentBytes)} / ${formatBytes(s.totalBytes)}',
            progress: s.status == SessionStatus.waiting ? null : s.progress,
            icon: Icons.upload_rounded,
            color: scheme.primary,
            onCancel: () =>
                ref.read(appServicesProvider).value?.sender.cancel(s.localId),
          ),
      ],
    );
  }
}

class _ActiveCard extends StatelessWidget {
  const _ActiveCard({
    required this.title,
    required this.subtitle,
    required this.progress,
    required this.icon,
    required this.color,
    required this.onCancel,
  });

  final String title;
  final String subtitle;
  final double? progress;
  final IconData icon;
  final Color color;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: SuviSpacing.md),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(SuviSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(icon, color: color),
                  const SizedBox(width: SuviSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: l.cancel,
                    icon: const Icon(Icons.close_rounded),
                    onPressed: onCancel,
                  ),
                ],
              ),
              const SizedBox(height: SuviSpacing.md),
              TweenAnimationBuilder<double>(
                tween: Tween(end: (progress ?? 0).clamp(0, 1)),
                duration: SuviMotion.medium,
                builder: (_, v, __) => LinearProgressIndicator(
                  value: progress == null ? null : v,
                  minHeight: 6,
                  borderRadius: const BorderRadius.all(Radius.circular(3)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryList extends ConsumerWidget {
  const _HistoryList({required this.entries, required this.padding});
  final List<HistoryEntry> entries;
  final double padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    if (entries.isEmpty) {
      return _Empty(
        icon: Icons.history_rounded,
        title: l.noTransfersYet,
        body: l.noTransfersBody,
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final grouped = <String, List<HistoryEntry>>{};
    for (final e in entries) {
      final d = DateTime(e.timestamp.year, e.timestamp.month, e.timestamp.day);
      final today = DateTime(now.year, now.month, now.day);
      final label = d == today
          ? l.today
          : d == today.subtract(const Duration(days: 1))
          ? l.yesterday
          : '${e.timestamp.day.toString().padLeft(2, '0')}.${e.timestamp.month.toString().padLeft(2, '0')}.${e.timestamp.year}';
      grouped.putIfAbsent(label, () => []).add(e);
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(padding, 0, padding, SuviSpacing.xxl),
      children: [
        for (final entry in grouped.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              SuviSpacing.xs,
              SuviSpacing.md,
              0,
              SuviSpacing.sm,
            ),
            child: Text(
              entry.key,
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          for (final e in entry.value)
            Padding(
              padding: const EdgeInsets.only(bottom: SuviSpacing.sm),
              child: _HistoryTile(entry: e),
            ),
        ],
      ],
    );
  }
}

class _HistoryTile extends ConsumerWidget {
  const _HistoryTile({required this.entry});
  final HistoryEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final sent = entry.direction == HistoryDirection.sent;
    final ok = entry.status == SessionStatus.finished;
    final firstPath = entry.files
        .firstWhere(
          (f) => f.path != null,
          orElse: () => const HistoryFile(name: '', size: 0, mime: ''),
        )
        .path;
    final title = entry.files.isEmpty
        ? (entry.text ?? l.incomingText)
        : entry.files.length == 1
        ? entry.files.first.name
        : '${entry.files.first.name} +${entry.files.length - 1}';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: firstPath != null && !sent
            ? () => OpenFilex.open(firstPath)
            : null,
        leading: CircleAvatar(
          backgroundColor: ok ? scheme.primaryContainer : scheme.errorContainer,
          foregroundColor: ok
              ? scheme.onPrimaryContainer
              : scheme.onErrorContainer,
          child: Icon(
            sent ? Icons.north_east_rounded : Icons.south_west_rounded,
          ),
        ),
        title: Text(title, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${sent ? l.sent : l.received} · ${entry.peerAlias} · ${formatBytes(entry.totalSize)}'
          '${ok ? '' : ' · ${statusLabel(l, entry.status)}'}',
          overflow: TextOverflow.ellipsis,
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            switch (v) {
              case 'open':
                if (firstPath != null) await OpenFilex.open(firstPath);
              case 'folder':
                if (firstPath != null) {
                  final opened = await openContainingFolder(firstPath);
                  if (!opened && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l.openLocationFailed)),
                    );
                  }
                }
              case 'copy':
                if (entry.text != null) {
                  await Clipboard.setData(ClipboardData(text: entry.text!));
                }
              case 'delete':
                await ref.read(historyProvider.notifier).remove(entry.id);
            }
          },
          itemBuilder: (_) => [
            if (firstPath != null)
              PopupMenuItem(
                value: 'open',
                child: ListTile(
                  leading: const Icon(Icons.open_in_new_rounded),
                  title: Text(l.open),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            if (firstPath != null)
              PopupMenuItem(
                value: 'folder',
                child: ListTile(
                  leading: const Icon(Icons.folder_open_rounded),
                  title: Text(l.showInFolder),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            if (entry.text != null)
              PopupMenuItem(
                value: 'copy',
                child: ListTile(
                  leading: const Icon(Icons.copy_rounded),
                  title: Text(l.copy),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            PopupMenuItem(
              value: 'delete',
              child: ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: Text(l.clearHistory),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SuviSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 56,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: SuviSpacing.lg),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: SuviSpacing.sm),
            Text(
              body,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
