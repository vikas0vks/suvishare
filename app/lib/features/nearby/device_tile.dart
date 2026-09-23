import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:suvi_core/suvi_core.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/device_avatar.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/app_services.dart';
import '../send/send_flow.dart';

class DeviceTile extends ConsumerWidget {
  const DeviceTile({
    super.key,
    required this.peer,
    this.trusted,
    this.onTap,
    this.selected = false,
  });

  final Peer peer;
  final TrustedDevice? trusted;

  /// When provided, tap calls this instead of opening the send flow.
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final mismatch =
        peer.verifiedFingerprint != null &&
        peer.verifiedFingerprint != peer.fingerprint;
    final isTrusted = trusted != null && !trusted!.blocked && !mismatch;
    final isBlocked = trusted?.blocked == true;

    final subtitleParts = <String>[
      if (peer.info.deviceModel != null && peer.info.deviceModel!.isNotEmpty)
        peer.info.deviceModel!,
      peer.ip,
      if (isTrusted) l.trusted,
      if (isBlocked) l.blocked,
      if (mismatch) l.unverified,
    ];

    return Card(
      color: selected ? scheme.secondaryContainer : null,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap ?? () => startSendFlow(context, ref, target: peer),
        leading: DeviceAvatar(
          colorIndex: peer.info.avatarColor,
          deviceType: peer.info.deviceType,
          badge: mismatch
              ? _Badge(icon: Icons.warning_rounded, color: scheme.error)
              : isTrusted
              ? _Badge(icon: Icons.verified_rounded, color: scheme.primary)
              : null,
        ),
        title: Text(
          peer.alias,
          style: Theme.of(context).textTheme.titleMedium,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          subtitleParts.join(' · '),
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (trusted?.favorite == true)
              const Icon(
                Icons.star_rounded,
                color: SuviColors.signalAmber,
                size: 20,
              ),
            if (onTap == null)
              IconButton.filledTonal(
                tooltip: l.sendTo(peer.alias),
                icon: const Icon(Icons.send_rounded),
                onPressed: () => startSendFlow(context, ref, target: peer),
              ),
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (v) => _onMenu(context, ref, v),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'fav',
                  child: ListTile(
                    leading: Icon(
                      trusted?.favorite == true
                          ? Icons.star_outline_rounded
                          : Icons.star_rounded,
                    ),
                    title: Text(
                      trusted?.favorite == true ? l.unfavorite : l.favorite,
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'trust',
                  child: ListTile(
                    leading: Icon(
                      isTrusted
                          ? Icons.remove_moderator_outlined
                          : Icons.verified_user_outlined,
                    ),
                    title: Text(isTrusted ? l.untrustDevice : l.trustDevice),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'block',
                  child: ListTile(
                    leading: Icon(
                      isBlocked ? Icons.lock_open_rounded : Icons.block_rounded,
                    ),
                    title: Text(isBlocked ? l.unblockDevice : l.blockDevice),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'details',
                  child: ListTile(
                    leading: const Icon(Icons.info_outline_rounded),
                    title: Text(l.deviceDetails),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onMenu(BuildContext context, WidgetRef ref, String v) async {
    final l = AppLocalizations.of(context);
    final store = await ref.read(trustStoreProvider.future);
    if (!context.mounted) return;
    switch (v) {
      case 'fav':
        if (store.get(peer.fingerprint) == null) {
          if (!await _verifyIdentity(context, ref)) return;
          await store.trust(peer.fingerprint, peer.alias, ip: peer.ip);
        }
        await store.update(
          peer.fingerprint,
          (d) => d.copyWith(favorite: !(d.favorite)),
        );
      case 'trust':
        if (trusted != null && !trusted!.blocked) {
          await store.remove(peer.fingerprint);
        } else {
          if (!await _verifyIdentity(context, ref)) return;
          await store.trust(peer.fingerprint, peer.alias, ip: peer.ip);
          await store.update(
            peer.fingerprint,
            (d) => d.copyWith(autoAccept: true),
          );
        }
      case 'block':
        if (trusted?.blocked == true) {
          await store.remove(peer.fingerprint);
        } else {
          await store.block(peer.fingerprint, peer.alias);
        }
      case 'details':
        if (!context.mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(peer.alias),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _kv(ctx, 'Model', peer.info.deviceModel ?? '—'),
                _kv(ctx, 'Type', peer.info.deviceType.name),
                _kv(ctx, 'Address', '${peer.ip}:${peer.port}'),
                _kv(
                  ctx,
                  'Protocol',
                  '${peer.info.protocol.name.toUpperCase()} · v${peer.info.version}',
                ),
                _kv(ctx, 'Fingerprint', peer.fingerprint, mono: true),
                if (peer.verifiedFingerprint != null)
                  _kv(ctx, 'Seen cert', peer.verifiedFingerprint!, mono: true),
                _kv(ctx, 'Source', peer.source.name),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: peer.fingerprint));
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(l.copied)));
                },
                child: Text(l.copy),
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

  Future<bool> _verifyIdentity(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final observed = peer.verifiedFingerprint;
    if (peer.info.protocol == PeerProtocol.https &&
        observed == peer.fingerprint) {
      return true;
    }
    final services = await ref.read(appServicesProvider.future);
    final verified = await services.client.verifyPeerIdentity(
      peer.ip,
      peer.port,
      peer.fingerprint,
      protocol: peer.info.protocol,
    );
    if (!verified && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.identityVerificationFailed)));
    }
    return verified;
  }

  Widget _kv(BuildContext ctx, String k, String v, {bool mono = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: SuviSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              k,
              style: Theme.of(ctx).textTheme.labelSmall
                  ?.copyWith(color: Theme.of(ctx).colorScheme.onSurfaceVariant),
            ),
            SelectableText(
              v,
              style: mono
                  ? const TextStyle(fontFamily: 'monospace', fontSize: 12)
                  : Theme.of(ctx).textTheme.bodyMedium,
            ),
          ],
        ),
      );
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.color});
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(1.5),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      shape: BoxShape.circle,
    ),
    child: Icon(icon, size: 16, color: color),
  );
}
