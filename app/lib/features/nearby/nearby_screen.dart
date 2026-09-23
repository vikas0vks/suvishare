import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:suvi_core/suvi_core.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/device_avatar.dart';
import '../../core/widgets/radar.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/app_services.dart';
import '../../providers/settings.dart';
import '../send/send_flow.dart';
import 'device_tile.dart';
import 'qr_scan_screen.dart';

class NearbyScreen extends ConsumerStatefulWidget {
  const NearbyScreen({super.key});

  @override
  ConsumerState<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends ConsumerState<NearbyScreen> {
  bool _showTips = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 8), () {
      if (mounted) setState(() => _showTips = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final settings = ref.watch(settingsProvider).value;
    final services = ref.watch(appServicesProvider);
    final peers = ref.watch(peersProvider).value ?? const <Peer>[];
    final ip = ref.watch(localIpProvider).value;
    final trusted =
        ref.watch(trustedDevicesProvider).value ?? const <TrustedDevice>[];
    final trustedByFp = {for (final t in trusted) t.fingerprint: t};
    final scan = ref.watch(scanProgressProvider).value;
    final wc = windowClassOf(MediaQuery.sizeOf(context).width);

    final favorites = peers
        .where((p) => trustedByFp[p.fingerprint]?.favorite == true)
        .toList();
    final others = peers
        .where((p) => trustedByFp[p.fingerprint]?.favorite != true)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(l.navNearby),
        actions: [
          IconButton(
            tooltip: l.refresh,
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => services.value?.discovery.refresh(),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (v) async {
              switch (v) {
                case 'scan':
                  await services.value?.discovery.scanSubnet();
                case 'address':
                  await _enterAddress(context);
                case 'qr':
                  await _showQr(context);
                case 'scanqr':
                  await _scanQr(context);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'scan',
                child: ListTile(
                  leading: const Icon(Icons.travel_explore_rounded),
                  title: Text(l.scanNetwork),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'address',
                child: ListTile(
                  leading: const Icon(Icons.keyboard_rounded),
                  title: Text(l.enterAddress),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              // Phones carry a camera: they scan. Desktops only display theirs.
              if (canScanQr)
                PopupMenuItem(
                  value: 'scanqr',
                  child: ListTile(
                    leading: const Icon(Icons.qr_code_scanner_rounded),
                    title: Text(l.scanQr),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              PopupMenuItem(
                value: 'qr',
                child: ListTile(
                  leading: const Icon(Icons.qr_code_2_rounded),
                  title: Text(l.showMyQr),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => startSendFlow(context, ref),
        icon: const Icon(Icons.send_rounded),
        label: Text(l.send),
      ),
      body: RefreshIndicator(
        onRefresh: () async => services.value?.discovery.refresh(),
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            wc == WindowClass.compact ? SuviSpacing.lg : SuviSpacing.xl,
            SuviSpacing.sm,
            wc == WindowClass.compact ? SuviSpacing.lg : SuviSpacing.xl,
            96,
          ),
          children: [
            if (settings != null)
              _SelfCard(
                settings: settings,
                ip: ip,
                // The port actually bound, which can differ from the setting.
                port: services.value?.server.port ?? settings.port,
                fingerprint: services.value?.identity.shortFingerprint,
              ),
            const SizedBox(height: SuviSpacing.lg),
            if (scan != null)
              Padding(
                padding: const EdgeInsets.only(bottom: SuviSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.scanning(scan.$1, scan.$2),
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: SuviSpacing.xs),
                    LinearProgressIndicator(
                      value: scan.$2 == 0 ? null : scan.$1 / scan.$2,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
              ),
            if (peers.isEmpty)
              _EmptyState(
                showTips: _showTips,
                ip: ip,
                onEnterAddress: () => _enterAddress(context),
                onScan: () => services.value?.discovery.scanSubnet(),
                onQr: () => _showQr(context),
                onScanQr: canScanQr ? () => _scanQr(context) : null,
              )
            else ...[
              if (favorites.isNotEmpty) ...[
                _SectionHeader(l.favorites),
                for (final p in favorites) _tile(p, trustedByFp[p.fingerprint]),
                const SizedBox(height: SuviSpacing.md),
              ],
              _SectionHeader('${l.nearbyDevices} · ${others.length}'),
              for (final p in others) _tile(p, trustedByFp[p.fingerprint]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tile(Peer p, TrustedDevice? t) => Padding(
    key: ValueKey(p.fingerprint),
    padding: const EdgeInsets.only(bottom: SuviSpacing.sm),
    child: DeviceTile(peer: p, trusted: t)
        .animate()
        .fadeIn(duration: SuviMotion.medium)
        .slideY(
          begin: 0.08,
          end: 0,
          curve: SuviMotion.decelerate,
          duration: SuviMotion.medium,
        ),
  );

  Future<void> _scanQr(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final peer = await scanQrAndConnect(context, ref);
    if (peer != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.connectedTo(peer.alias))));
    }
  }

  Future<void> _enterAddress(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final controller = TextEditingController();
    final addr = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.enterAddress),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(hintText: l.addressHint),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: Text(l.connect),
          ),
        ],
      ),
    );
    if (addr == null || addr.trim().isEmpty) return;
    final services = ref.read(appServicesProvider).value;
    final peer = await services?.discovery.addManual(addr);
    if (!context.mounted) return;
    if (peer == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.deviceNotReachable)));
    }
  }

  Future<void> _showQr(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final ip = ref.read(localIpProvider).value;
    final settings = ref.read(settingsProvider).value;
    final services = ref.read(appServicesProvider).value;
    if (ip == null || settings == null || services == null) return;
    final address = '$ip:${services.server.port ?? settings.port}';
    final payload = 'suvi://$address#${services.identity.fingerprint}';
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.qrTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(SuviSpacing.md),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(SuviRadius.md),
              ),
              child: SizedBox(
                width: 200,
                height: 200,
                child: PrettyQrView.data(data: payload),
              ),
            ),
            const SizedBox(height: SuviSpacing.lg),
            SelectableText(
              address,
              style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: SuviSpacing.sm),
            Text(
              l.qrBody,
              textAlign: TextAlign.center,
              style: Theme.of(ctx).textTheme.bodyMedium,
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: address));
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(l.copied)));
            },
            icon: const Icon(Icons.copy_rounded),
            label: Text(l.copy),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l.close),
          ),
        ],
      ),
    );
  }
}

/// Platform-specific firewall instructions with copyable commands — the #1
/// reason a device is invisible, especially on Linux.
Future<void> showFirewallHelp(BuildContext context) async {
  final l = AppLocalizations.of(context);
  final String body;
  final String? commands;
  if (Platform.isLinux) {
    body = l.errFirewallBody;
    commands =
        'sudo ufw allow 53317/tcp\n'
        'sudo ufw allow 53317/udp\n'
        'sudo ufw allow 53318/tcp\n'
        '# firewalld:\n'
        'sudo firewall-cmd --permanent --add-port=53317/tcp '
        '--add-port=53317/udp --add-port=53318/tcp\n'
        'sudo firewall-cmd --reload';
  } else if (Platform.isWindows) {
    body = l.errFirewallBody;
    commands =
        'netsh advfirewall firewall add rule name="Suvi Share" '
        'dir=in action=allow program="%ProgramFiles%\\Suvi Share\\suvi_share.exe" '
        'enable=yes profile=private';
  } else {
    body = l.errNoWifiBody;
    commands = null;
  }
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l.errFirewallTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(body),
          if (commands != null) ...[
            const SizedBox(height: SuviSpacing.lg),
            Container(
              width: double.maxFinite,
              padding: const EdgeInsets.all(SuviSpacing.md),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(SuviRadius.sm),
              ),
              child: SelectableText(
                commands,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ],
        ],
      ),
      actions: [
        if (commands != null)
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: commands!));
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(l.copied)));
            },
            icon: const Icon(Icons.copy_rounded),
            label: Text(l.copy),
          ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(l.close),
        ),
      ],
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(
      left: SuviSpacing.xs,
      bottom: SuviSpacing.sm,
      top: SuviSpacing.xs,
    ),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelLarge
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
}

class _SelfCard extends ConsumerWidget {
  const _SelfCard({
    required this.settings,
    required this.ip,
    required this.port,
    required this.fingerprint,
  });
  final AppSettings settings;
  final String? ip;
  final int port;
  final String? fingerprint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.primaryContainer.withValues(alpha: 0.55),
      child: Padding(
        padding: const EdgeInsets.all(SuviSpacing.lg),
        child: Row(
          children: [
            DeviceAvatar(
              colorIndex: settings.avatarColor,
              deviceType: (Platform.isAndroid || Platform.isIOS)
                  ? DeviceType.mobile
                  : DeviceType.desktop,
              size: 48,
            ),
            const SizedBox(width: SuviSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.youAre(settings.alias),
                    style: Theme.of(context).textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        ip == null
                            ? Icons.wifi_off_rounded
                            : Icons.wifi_rounded,
                        size: 16,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: SuviSpacing.xs),
                      Flexible(
                        child: Text(
                          ip == null
                              ? l.notConnected
                              : l.visibleOn('$ip:$port'),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: SuviSpacing.sm),
            Tooltip(
              message: settings.receiveEnabled ? l.receiveOn : l.receiveOff,
              child: Switch(
                value: settings.receiveEnabled,
                onChanged: (v) => ref
                    .read(settingsProvider.notifier)
                    .edit((s) => s.copyWith(receiveEnabled: v)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.showTips,
    required this.ip,
    required this.onEnterAddress,
    required this.onScan,
    required this.onQr,
    this.onScanQr,
  });
  final bool showTips;
  final String? ip;
  final VoidCallback onEnterAddress;
  final VoidCallback onScan;
  final VoidCallback onQr;

  /// Camera platforms only.
  final VoidCallback? onScanQr;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        const SizedBox(height: SuviSpacing.xl),
        RadarView(
          size: 220,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.primaryContainer,
            ),
            child: Icon(
              Icons.wifi_tethering_rounded,
              color: scheme.onPrimaryContainer,
            ),
          ),
        ),
        const SizedBox(height: SuviSpacing.xl),
        Text(
          showTips ? l.noDevicesTitle : l.lookingForDevices,
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: SuviSpacing.sm),
        if (showTips)
          ...[
            Text(
              l.noDevicesBody,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: SuviSpacing.lg),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: SuviSpacing.sm,
              runSpacing: SuviSpacing.sm,
              children: [
                Chip(
                  avatar: const Icon(Icons.wifi_rounded, size: 18),
                  label: Text(l.tipSameWifi),
                ),
                ActionChip(
                  avatar: const Icon(Icons.security_rounded, size: 18),
                  label: Text(l.tipFirewall),
                  onPressed: () => showFirewallHelp(context),
                ),
                ActionChip(
                  avatar: const Icon(Icons.travel_explore_rounded, size: 18),
                  label: Text(l.scanNetwork),
                  onPressed: onScan,
                ),
                ActionChip(
                  avatar: const Icon(Icons.keyboard_rounded, size: 18),
                  label: Text(l.enterAddress),
                  onPressed: onEnterAddress,
                ),
                if (onScanQr != null)
                  ActionChip(
                    avatar: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                    label: Text(l.scanQr),
                    onPressed: onScanQr,
                  ),
                ActionChip(
                  avatar: const Icon(Icons.qr_code_2_rounded, size: 18),
                  label: Text(l.showMyQr),
                  onPressed: onQr,
                ),
              ],
            ),
          ].animate(interval: 60.ms).fadeIn(duration: SuviMotion.medium),
      ],
    );
  }
}
