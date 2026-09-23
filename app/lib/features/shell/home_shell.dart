import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:suvi_core/suvi_core.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/theme/app_theme.dart';
import '../../core/util/format.dart';
import '../../l10n/app_localizations.dart';
import '../../platform/desktop_tray.dart';
import '../../platform/notifications.dart';
import '../../platform/share_intent.dart';
import '../../platform/transfer_service.dart';
import '../../providers/app_services.dart';
import '../../providers/app_update.dart';
import '../../providers/settings.dart';
import '../receive/incoming_sheet.dart';
import '../send/send_flow.dart';

/// Adaptive scaffold: NavigationBar (compact) ↔ NavigationRail (medium/expanded).
/// Also hosts app-wide listeners: incoming requests, drag-and-drop.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell>
    with WidgetsBindingObserver {
  bool _dragging = false;
  bool _sheetOpen = false;
  bool _trayInstalled = false;
  bool _receiverServiceHeld = false;
  final _shareIntent = ShareIntentListener();
  StreamSubscription<SharedPayload>? _shareSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SuviNotifications.init();
    // Anything shared to us from another app's share sheet opens the send flow
    // already loaded, so the user only has to pick a device.
    _shareSub = _shareIntent.payloads.listen((payload) async {
      if (!mounted) return;
      await startSendFlow(
        context,
        ref,
        initialItems: payload.items,
        initialText: payload.text,
      );
    });
    _shareIntent.start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _shareSub?.cancel();
    _shareIntent.dispose();
    if (_trayInstalled) desktopTray.dispose();
    super.dispose();
  }

  /// Android kills backgrounded apps freely — and a dead app is exactly the
  /// "device shows in the list but nothing arrives" report. While Receiving is
  /// on, hold a lightweight foreground service whenever the app leaves the
  /// foreground so the server and discovery announcements stay alive.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!Platform.isAndroid) return;
    final receiving = ref.read(settingsProvider).value?.receiveEnabled ?? false;
    final alias = ref.read(settingsProvider).value?.alias ?? 'Suvi Share';
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        if (receiving && !_receiverServiceHeld) {
          _receiverServiceHeld = true;
          TransferForegroundService.acquire(
            title: 'Suvi Share is receiving',
            body: 'Visible as "$alias" on this Wi-Fi',
          );
        }
      case AppLifecycleState.resumed:
        if (_receiverServiceHeld) {
          _receiverServiceHeld = false;
          TransferForegroundService.release();
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  Future<void> _ensureTray(AppSettings settings) async {
    if (!isDesktopPlatform) return;
    if (!_trayInstalled) {
      _trayInstalled = true;
      desktopTray.onReceiveToggled = (v) => ref
          .read(settingsProvider.notifier)
          .edit((s) => s.copyWith(receiveEnabled: v));
      desktopTray.onQuit = () async =>
          ref.read(appServicesProvider.notifier).shutdown();
      await desktopTray.install(
        closeToTray: settings.closeToTray,
        receiving: settings.receiveEnabled,
      );
    } else {
      await desktopTray.setCloseToTray(settings.closeToTray);
      await desktopTray.setReceiving(settings.receiveEnabled);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final wc = windowClassOf(width);

    // Start services as soon as the shell is up.
    ref.watch(appServicesProvider);
    final updateAvailable =
        ref.watch(appUpdateProvider).value?.updateAvailable ?? false;

    final settings = ref.watch(settingsProvider).value;
    if (settings != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _ensureTray(settings),
      );
    }

    // Incoming-request listener (modal sheet / dialog). A request that arrives
    // while the window is hidden in the tray or the phone is in the background
    // must never be a black hole: bring the desktop window to the front and
    // post a notification everywhere.
    ref.listen<PendingIncoming?>(pendingIncomingProvider, (prev, next) async {
      if (next == null || _sheetOpen) return;
      _sheetOpen = true;
      final req = next.request;
      SuviNotifications.incomingRequest(
        'Incoming from ${req.sender.alias}',
        req.files.isEmpty
            ? 'A message'
            : '${req.files.length} file(s) · ${formatBytes(req.totalSize)}',
      );
      if (isDesktopPlatform) {
        try {
          await windowManager.show();
          await windowManager.focus();
        } catch (_) {}
      }
      try {
        // A follow-up request can arrive while the previous sheet is still
        // showing its "done" state (which pops itself to make room) — keep
        // presenting until nothing is pending.
        PendingIncoming? current = next;
        while (current != null) {
          if (!mounted) break;
          if (!context.mounted) break;
          await showIncomingRequest(context, ref, current);
          final again = ref.read(pendingIncomingProvider);
          current = (again != null && again != current) ? again : null;
        }
      } finally {
        _sheetOpen = false;
        SuviNotifications.clearIncoming();
      }
    });

    final destinations = [
      _Dest(Icons.radar_rounded, Icons.radar_rounded, l.navNearby),
      _Dest(Icons.swap_vert_rounded, Icons.swap_vert_rounded, l.navTransfers),
      _Dest(Icons.settings_outlined, Icons.settings_rounded, l.navSettings),
    ];

    Widget body = widget.shell;

    // Desktop drag-and-drop anywhere.
    final isDesktop =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    if (isDesktop) {
      body = CallbackShortcuts(
        bindings: {
          SuviShortcuts.pickFiles: () => startSendFlow(context, ref),
          SuviShortcuts.refresh: () =>
              ref.read(appServicesProvider).value?.discovery.refresh(),
          // Ctrl+Shift+V: send whatever is on the clipboard — screenshot or text.
          SuviShortcuts.sendClipboard: () async {
            final c = await readClipboardContent();
            if (!context.mounted || c == null) return;
            switch (c) {
              case ClipboardImage(:final sendItem):
                await startSendFlow(context, ref, initialItems: [sendItem]);
              case ClipboardText(:final text):
                await startSendFlow(context, ref, initialText: text);
            }
          },
        },
        child: Focus(autofocus: true, child: body),
      );
      body = DropTarget(
        onDragEntered: (_) => setState(() => _dragging = true),
        onDragExited: (_) => setState(() => _dragging = false),
        onDragDone: (detail) async {
          setState(() => _dragging = false);
          final items = <SendItem>[];
          for (final f in detail.files) {
            final type = FileSystemEntity.typeSync(f.path);
            if (type == FileSystemEntityType.directory) {
              items.addAll(await collectDirectory(f.path));
            } else {
              items.add(SendItem.file(f.path));
            }
          }
          if (items.isNotEmpty && context.mounted) {
            await startSendFlow(context, ref, initialItems: items);
          }
        },
        child: Stack(children: [body, if (_dragging) const _DropOverlay()]),
      );
    }

    if (wc == WindowClass.compact) {
      return Scaffold(
        body: body,
        bottomNavigationBar: NavigationBar(
          selectedIndex: widget.shell.currentIndex,
          onDestinationSelected: _go,
          destinations: [
            for (final d in destinations)
              NavigationDestination(
                icon: _DestinationIcon(
                  icon: d.icon,
                  showBadge: updateAvailable && d == destinations.last,
                ),
                selectedIcon: _DestinationIcon(
                  icon: d.selected,
                  showBadge: updateAvailable && d == destinations.last,
                ),
                label: d.label,
              ),
          ],
        ),
      );
    }

    final extended = wc == WindowClass.expanded;
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: widget.shell.currentIndex,
            onDestinationSelected: _go,
            extended: extended,
            minExtendedWidth: 200,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: SuviSpacing.lg),
              child: _Brand(compact: !extended),
            ),
            destinations: [
              for (final d in destinations)
                NavigationRailDestination(
                  icon: _DestinationIcon(
                    icon: d.icon,
                    showBadge: updateAvailable && d == destinations.last,
                  ),
                  selectedIcon: _DestinationIcon(
                    icon: d.selected,
                    showBadge: updateAvailable && d == destinations.last,
                  ),
                  label: Text(d.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ],
      ),
    );
  }

  void _go(int index) => widget.shell.goBranch(
    index,
    initialLocation: index == widget.shell.currentIndex,
  );
}

class _Dest {
  const _Dest(this.icon, this.selected, this.label);
  final IconData icon;
  final IconData selected;
  final String label;
}

class _DestinationIcon extends StatelessWidget {
  const _DestinationIcon({required this.icon, required this.showBadge});

  final IconData icon;
  final bool showBadge;

  @override
  Widget build(BuildContext context) =>
      Badge(isLabelVisible: showBadge, smallSize: 8, child: Icon(icon));
}

class _Brand extends StatelessWidget {
  const _Brand({required this.compact});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final logo = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: [scheme.primary, scheme.tertiary]),
      ),
      child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
    );
    if (compact) return logo;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        logo,
        const SizedBox(width: SuviSpacing.md),
        Text('Suvi Share', style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}

class _DropOverlay extends StatelessWidget {
  const _DropOverlay();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: scheme.surface.withValues(alpha: 0.85),
          margin: const EdgeInsets.all(SuviSpacing.lg),
          child: CustomPaint(
            painter: _DashedBorderPainter(scheme.primary),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.file_download_rounded,
                    size: 64,
                    color: scheme.primary,
                  ),
                  const SizedBox(height: SuviSpacing.lg),
                  Text(
                    'Drop to send',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(SuviRadius.xl),
    );
    final path = Path()..addRRect(rrect);
    const dash = 10.0, gap = 8.0;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter old) => old.color != color;
}
