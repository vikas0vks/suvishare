import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:suvi_core/suvi_core.dart';

import '../../core/theme/app_theme.dart';
import '../../core/util/format.dart';
import '../../core/widgets/device_avatar.dart';
import '../../l10n/app_localizations.dart';
import '../../platform/open_location.dart';
import '../../platform/permissions.dart';
import '../../providers/app_services.dart';
import '../../providers/settings.dart';

/// Shows the Accept/Decline UI for an incoming request, then (if accepted)
/// the live receive progress until the session ends.
Future<void> showIncomingRequest(
  BuildContext context,
  WidgetRef ref,
  PendingIncoming pending,
) async {
  final wc = windowClassOf(MediaQuery.sizeOf(context).width);
  final child = _IncomingView(pending: pending);
  if (wc == WindowClass.compact) {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      useSafeArea: true,
      builder: (_) => child,
    );
  } else {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(child: SizedBox(width: 540, child: child)),
    );
  }
  // Safety: if the sheet was dismissed without a decision, decline.
  final cur = ref.read(pendingIncomingProvider);
  if (cur == pending) {
    ref
        .read(pendingIncomingProvider.notifier)
        .resolve(const ReceiveDecision.decline());
  }
}

class _IncomingView extends ConsumerStatefulWidget {
  const _IncomingView({required this.pending});
  final PendingIncoming pending;
  @override
  ConsumerState<_IncomingView> createState() => _IncomingViewState();
}

class _IncomingViewState extends ConsumerState<_IncomingView> {
  bool _decided = false;
  bool _alwaysAccept = false;
  String? _saveDir;
  final _meter = SpeedMeter();
  double _speed = 0;

  IncomingRequest get req => widget.pending.request;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final settings = ref.watch(settingsProvider).value;
    final session = ref.watch(receiveSessionProvider);
    final saveDir = _saveDir ?? settings?.saveDirectory ?? '';

    // The sender can cancel while the user is still deciding — leaving the
    // Accept/Decline sheet up for a request that no longer exists would make
    // the *next* transfer look broken. Dismiss and release the decision.
    ref.listen<ReceiveSession?>(receiveSessionProvider, (prev, s) {
      if (_decided || !mounted) return;
      if (s != null &&
          s.sender.fingerprint == req.sender.fingerprint &&
          s.status == SessionStatus.cancelledBySender) {
        _decided = true;
        ref
            .read(pendingIncomingProvider.notifier)
            .resolve(const ReceiveDecision.decline());
        Navigator.of(context).pop();
      }
    });

    // A brand-new request while this sheet is showing a finished transfer:
    // get out of the way so the shell can present it.
    ref.listen<PendingIncoming?>(pendingIncomingProvider, (prev, next) {
      if (!mounted || next == null || next == widget.pending) return;
      final terminal = session != null && session.status.isTerminal;
      if (_decided && terminal) Navigator.of(context).pop();
    });

    // After accept: show progress for this session.
    if (_decided &&
        session != null &&
        session.sender.fingerprint == req.sender.fingerprint) {
      return _ReceiveProgress(
        session: session,
        speed: _speedFor(session),
        onClose: () => Navigator.of(context).pop(),
      );
    }

    final totalSize = req.totalSize;
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
                    colorIndex: req.sender.avatarColor,
                    deviceType: req.sender.deviceType,
                    size: 52,
                  ),
                  const SizedBox(width: SuviSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.incomingTitle(req.sender.alias),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          req.files.isEmpty
                              ? l.incomingText
                              : l.incomingFiles(
                                  req.files.length,
                                  formatBytes(totalSize),
                                ),
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              )
              .animate()
              .fadeIn(duration: SuviMotion.medium)
              .slideY(begin: 0.05, end: 0),
          const SizedBox(height: SuviSpacing.lg),
          if (req.text != null)
            Container(
              padding: const EdgeInsets.all(SuviSpacing.md),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(SuviRadius.md),
              ),
              child: SelectableText(req.text!, maxLines: 6),
            ),
          if (req.files.isNotEmpty)
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.3,
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final f in req.files.take(6))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        iconForMime(f.fileType),
                        color: scheme.onSurfaceVariant,
                      ),
                      title: Text(f.fileName, overflow: TextOverflow.ellipsis),
                      subtitle: Text(formatBytes(f.size)),
                    ),
                  if (req.files.length > 6)
                    Padding(
                      padding: const EdgeInsets.only(top: SuviSpacing.xs),
                      child: Text(
                        l.moreFiles(req.files.length - 6),
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                ],
              ),
            ),
          if (req.files.isNotEmpty) ...[
            const SizedBox(height: SuviSpacing.md),
            Row(
              children: [
                Icon(
                  Icons.folder_outlined,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: SuviSpacing.sm),
                Expanded(
                  child: Text(
                    l.savesTo(saveDir),
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    final d = await fs.getDirectoryPath();
                    if (d != null && mounted) setState(() => _saveDir = d);
                  },
                  child: Text(l.change),
                ),
              ],
            ),
          ],
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            value: _alwaysAccept,
            onChanged: (v) => setState(() => _alwaysAccept = v ?? false),
            title: Text(l.alwaysAcceptFrom(req.sender.alias)),
          ),
          const SizedBox(height: SuviSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _decided ? null : _decline,
                child: Text(l.decline),
              ),
              const SizedBox(width: SuviSpacing.sm),
              FilledButton.icon(
                onPressed: _decided ? null : () => _accept(saveDir),
                icon: const Icon(Icons.download_rounded),
                label: Text(l.accept),
              ),
            ],
          ),
        ],
      ),
    );
  }

  double _speedFor(ReceiveSession s) {
    if (s.status == SessionStatus.transferring) {
      _speed = _meter.update(s.receivedBytes);
    }
    return _speed;
  }

  void _decline() {
    setState(() => _decided = true);
    ref
        .read(pendingIncomingProvider.notifier)
        .resolve(const ReceiveDecision.decline());
    Navigator.of(context).pop();
  }

  Future<void> _accept(String saveDir) async {
    setState(() => _decided = true);

    // Ask for the runtime permissions (Android notifications/storage) at the
    // moment they matter — right before receiving — and make sure the folder
    // is actually writable, falling back to an app-owned one otherwise.
    final resolved = await ReceivePrerequisites.prepare(saveDir);

    if (_alwaysAccept) {
      final store = await ref.read(trustStoreProvider.future);
      await store.trust(
        req.sender.fingerprint,
        req.sender.alias,
        ip: req.senderIp,
      );
      await store.update(
        req.sender.fingerprint,
        (d) => d.copyWith(autoAccept: true),
      );
    }
    if (_saveDir != null && !resolved.fellBack) {
      await ref
          .read(settingsProvider.notifier)
          .edit((s) => s.copyWith(saveDirectory: _saveDir));
    }
    ref
        .read(pendingIncomingProvider.notifier)
        .resolve(
          ReceiveDecision.accept(
            req.files.map((f) => f.id).toSet(),
            saveDirectory: resolved.dir,
          ),
        );
    if (resolved.fellBack && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).savedTo(resolved.dir)),
        ),
      );
    }
    // Text-only sessions finish instantly — do NOT pop here. The sheet flips
    // to its "received" state so the message is actually READ and copyable;
    // popping immediately made a delivered text look like nothing arrived.
    if (mounted) setState(() {});
  }
}

class _ReceiveProgress extends StatelessWidget {
  const _ReceiveProgress({
    required this.session,
    required this.speed,
    required this.onClose,
  });
  final ReceiveSession session;
  final double speed;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final s = session;
    final terminal = s.status.isTerminal;
    final ok = s.status == SessionStatus.finished;
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
                colorIndex: s.sender.avatarColor,
                deviceType: s.sender.deviceType,
                size: 48,
              ),
              const SizedBox(width: SuviSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      terminal
                          ? (ok
                                ? l.receivedFrom(s.sender.alias)
                                : statusLabel(l, s.status))
                          : l.receivingFrom(s.sender.alias),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      terminal
                          // A text-only session saves nothing to disk — naming
                          // a folder here would be a lie.
                          ? (s.files.isEmpty
                                ? l.incomingText
                                : l.savedTo(s.saveDirectory))
                          : l.progressLine(
                              formatBytes(s.receivedBytes),
                              formatBytes(s.totalBytes),
                              formatBytes(speed.round()),
                            ),
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                ok
                    ? Icons.check_circle_rounded
                    : (terminal ? Icons.error_rounded : Icons.download_rounded),
                color: ok || !terminal ? scheme.primary : scheme.error,
              ),
            ],
          ),
          const SizedBox(height: SuviSpacing.lg),
          TweenAnimationBuilder<double>(
            tween: Tween(end: s.progress.clamp(0, 1)),
            duration: SuviMotion.medium,
            builder: (_, v, __) => LinearProgressIndicator(
              value: v,
              minHeight: 8,
              borderRadius: const BorderRadius.all(Radius.circular(4)),
            ),
          ),
          const SizedBox(height: SuviSpacing.lg),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.35,
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: files.length,
              itemBuilder: (_, i) {
                final f = files[i];
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    iconForMime(f.file.fileType),
                    color: scheme.onSurfaceVariant,
                  ),
                  title: Text(f.file.fileName, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    f.error ??
                        (f.status == FileStatus.sending
                            ? '${formatBytes(f.received)} / ${formatBytes(f.file.size)}'
                            : formatBytes(f.file.size)),
                  ),
                  trailing:
                      f.status == FileStatus.finished && f.savedPath != null
                      ? IconButton(
                          tooltip: l.open,
                          icon: const Icon(Icons.open_in_new_rounded, size: 20),
                          onPressed: () => OpenFilex.open(f.savedPath!),
                        )
                      : Icon(
                          switch (f.status) {
                            FileStatus.queued => Icons.schedule_rounded,
                            FileStatus.sending => Icons.download_rounded,
                            FileStatus.finished => Icons.check_circle_rounded,
                            FileStatus.failed => Icons.error_rounded,
                            FileStatus.skipped =>
                              Icons.remove_circle_outline_rounded,
                          },
                          size: 20,
                          color: f.status == FileStatus.failed
                              ? scheme.error
                              : scheme.onSurfaceVariant,
                        ),
                );
              },
            ),
          ),
          if (s.text != null)
            Container(
              margin: const EdgeInsets.only(top: SuviSpacing.sm),
              padding: const EdgeInsets.all(SuviSpacing.md),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(SuviRadius.md),
              ),
              child: Row(
                children: [
                  Expanded(child: SelectableText(s.text!, maxLines: 4)),
                  IconButton(
                    tooltip: l.copy,
                    icon: const Icon(Icons.copy_rounded),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: s.text!));
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text(l.copied)));
                    },
                  ),
                ],
              ),
            ),
          const SizedBox(height: SuviSpacing.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (terminal && s.files.isNotEmpty)
                TextButton.icon(
                  onPressed: () async {
                    final opened = await openDirectoryLocation(s.saveDirectory);
                    if (!opened && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l.openLocationFailed)),
                      );
                    }
                  },
                  icon: const Icon(Icons.folder_open_rounded),
                  label: Text(l.showInFolder),
                ),
              const SizedBox(width: SuviSpacing.sm),
              if (terminal)
                FilledButton(onPressed: onClose, child: Text(l.done))
              else
                Consumer(
                  builder: (_, ref, __) => OutlinedButton.icon(
                    onPressed: () => ref
                        .read(appServicesProvider)
                        .value
                        ?.sessions
                        .cancelActive(),
                    icon: const Icon(Icons.close_rounded),
                    label: Text(l.cancel),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
