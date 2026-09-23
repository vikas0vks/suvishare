import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:suvi_core/suvi_core.dart';

import '../../core/theme/app_theme.dart';
import '../../core/util/format.dart';
import '../../core/widgets/device_avatar.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/app_services.dart';

/// Shows a modal progress sheet/dialog for a send session identified by
/// [localId]; resolves with the terminal session when the user closes it.
Future<SendSession?> showSendProgress(
  BuildContext context,
  WidgetRef ref,
  String localId,
  Future<SendSession> completion,
) async {
  final wc = windowClassOf(MediaQuery.sizeOf(context).width);
  final child = _SendProgressView(localId: localId, completion: completion);
  if (wc == WindowClass.compact) {
    return showModalBottomSheet<SendSession>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      useSafeArea: true,
      builder: (_) => child,
    );
  }
  return showDialog<SendSession>(
    context: context,
    barrierDismissible: false,
    builder: (_) => Dialog(child: SizedBox(width: 520, child: child)),
  );
}

class _SendProgressView extends ConsumerStatefulWidget {
  const _SendProgressView({required this.localId, required this.completion});
  final String localId;
  final Future<SendSession> completion;

  @override
  ConsumerState<_SendProgressView> createState() => _SendProgressViewState();
}

class _SendProgressViewState extends ConsumerState<_SendProgressView> {
  final _meter = SpeedMeter();
  double _speed = 0;
  SendSession? _final;

  @override
  void initState() {
    super.initState();
    widget.completion.then((s) {
      if (mounted) setState(() => _final = s);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final live = ref.watch(
      sendSessionsProvider.select((m) => m[widget.localId]),
    );
    final s = _final ?? live;
    if (s == null) {
      return const Padding(
        padding: EdgeInsets.all(SuviSpacing.xxl),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (s.status == SessionStatus.transferring) {
      _speed = _meter.update(s.sentBytes);
    }

    final terminal = s.status.isTerminal;
    final (title, icon, color) = switch (s.status) {
      SessionStatus.waiting => (
        l.waitingForAccept(s.target.alias),
        Icons.hourglass_top_rounded,
        scheme.primary,
      ),
      SessionStatus.transferring => (
        l.sendingTo(s.target.alias),
        Icons.upload_rounded,
        scheme.primary,
      ),
      SessionStatus.finished => (
        l.sentTo(s.target.alias),
        Icons.check_circle_rounded,
        scheme.primary,
      ),
      SessionStatus.finishedWithErrors => (
        l.transferFailed,
        Icons.error_rounded,
        scheme.error,
      ),
      SessionStatus.declined => (
        l.declinedBy(s.target.alias),
        Icons.block_rounded,
        scheme.onSurfaceVariant,
      ),
      SessionStatus.cancelledBySender || SessionStatus.cancelledByReceiver => (
        l.transferCancelled,
        Icons.cancel_rounded,
        scheme.onSurfaceVariant,
      ),
      _ => (l.transferFailed, Icons.error_rounded, scheme.error),
    };

    final files = s.files.values.toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SuviSpacing.xl,
        SuviSpacing.lg,
        SuviSpacing.xl,
        SuviSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              DeviceAvatar(
                colorIndex: s.target.info.avatarColor,
                deviceType: s.target.info.deviceType,
                size: 48,
              ),
              const SizedBox(width: SuviSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      s.status == SessionStatus.transferring
                          ? l.progressLine(
                              formatBytes(s.sentBytes),
                              formatBytes(s.totalBytes),
                              formatBytes(_speed.round()),
                            )
                          : s.errorMessage ??
                                // "0 items · 0 B" for a text message reads like a
                                // failure — show the message itself instead.
                                (files.isEmpty && s.text != null
                                    ? s.text!
                                    : l.itemsSelected(
                                        files.length,
                                        formatBytes(s.totalBytes),
                                      )),
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: SuviSpacing.sm),
              Icon(icon, color: color, size: 28)
                  .animate(key: ValueKey(s.status), target: terminal ? 1 : 0)
                  .scale(
                    begin: const Offset(0.6, 0.6),
                    end: const Offset(1, 1),
                    curve: Curves.elasticOut,
                    duration: 600.ms,
                  ),
            ],
          ),
          const SizedBox(height: SuviSpacing.lg),
          if (s.status == SessionStatus.waiting)
            const LinearProgressIndicator(
              borderRadius: BorderRadius.all(Radius.circular(4)),
            )
          else
            TweenAnimationBuilder<double>(
              tween: Tween(end: s.progress.clamp(0, 1)),
              duration: SuviMotion.medium,
              builder: (_, v, __) => LinearProgressIndicator(
                value: v,
                minHeight: 8,
                borderRadius: const BorderRadius.all(Radius.circular(4)),
                color:
                    s.status == SessionStatus.finishedWithErrors ||
                        s.status == SessionStatus.failed
                    ? scheme.error
                    : null,
              ),
            ),
          const SizedBox(height: SuviSpacing.lg),
          if (files.isNotEmpty)
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.35,
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: files.length,
                itemBuilder: (_, i) => _FileRow(f: files[i]),
              ),
            ),
          if (s.text != null && files.isEmpty)
            Container(
              padding: const EdgeInsets.all(SuviSpacing.md),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(SuviRadius.md),
              ),
              child: Text(
                s.text!,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          const SizedBox(height: SuviSpacing.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (!terminal)
                OutlinedButton.icon(
                  onPressed: () => ref
                      .read(appServicesProvider)
                      .value
                      ?.sender
                      .cancel(widget.localId),
                  icon: const Icon(Icons.close_rounded),
                  label: Text(l.cancel),
                )
              else
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(s),
                  child: Text(l.done),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.f});
  final SendingFile f;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (f.status) {
      FileStatus.queued => (Icons.schedule_rounded, scheme.onSurfaceVariant),
      FileStatus.sending => (Icons.upload_rounded, scheme.primary),
      FileStatus.finished => (Icons.check_circle_rounded, scheme.primary),
      FileStatus.failed => (Icons.error_rounded, scheme.error),
      FileStatus.skipped => (
        Icons.remove_circle_outline_rounded,
        scheme.onSurfaceVariant,
      ),
    };
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        iconForMime(f.dto.fileType),
        color: scheme.onSurfaceVariant,
      ),
      title: Text(f.dto.fileName, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        f.error ??
            (f.status == FileStatus.sending
                ? '${formatBytes(f.sent)} / ${formatBytes(f.dto.size)}'
                : formatBytes(f.dto.size)),
      ),
      trailing: Icon(icon, color: color, size: 20),
    );
  }
}
