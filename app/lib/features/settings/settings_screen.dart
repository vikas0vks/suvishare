import 'dart:io';

import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:suvi_core/suvi_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/device_avatar.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/app_services.dart';
import '../../providers/app_update.dart';
import '../../providers/settings.dart';
import '../../providers/web_share.dart';

final _versionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return '${info.version}+${info.buildNumber}';
});

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final settings = ref.watch(settingsProvider).value;
    final services = ref.watch(appServicesProvider).value;
    final trusted =
        ref.watch(trustedDevicesProvider).value ?? const <TrustedDevice>[];
    final version = ref.watch(_versionProvider).value ?? '—';
    final wc = windowClassOf(MediaQuery.sizeOf(context).width);
    final pad = wc == WindowClass.compact ? SuviSpacing.lg : SuviSpacing.xl;

    if (settings == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final notifier = ref.read(settingsProvider.notifier);
    final isDesktop =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;

    return Scaffold(
      appBar: AppBar(title: Text(l.navSettings)),
      body: ListView(
        padding: EdgeInsets.fromLTRB(pad, 0, pad, SuviSpacing.xxl),
        children: [
          // ------------------------------------------------------- device
          _Section(l.settingsDevice),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: DeviceAvatar(
                    colorIndex: settings.avatarColor,
                    deviceType: (Platform.isAndroid || Platform.isIOS)
                        ? DeviceType.mobile
                        : DeviceType.desktop,
                    size: 40,
                  ),
                  title: Text(l.settingsDeviceName),
                  subtitle: Text(settings.alias),
                  trailing: const Icon(Icons.edit_rounded),
                  onTap: () => _editAlias(context, ref, settings.alias),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    SuviSpacing.lg,
                    SuviSpacing.md,
                    SuviSpacing.lg,
                    SuviSpacing.lg,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.settingsAvatarColor,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: SuviSpacing.md),
                      Wrap(
                        spacing: SuviSpacing.md,
                        runSpacing: SuviSpacing.sm,
                        children: [
                          for (
                            var i = 0;
                            i < SuviColors.avatarPalette.length;
                            i++
                          )
                            InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: () => notifier.edit(
                                (s) => s.copyWith(avatarColor: i),
                              ),
                              child: Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: SuviColors.avatar(i),
                                  border: settings.avatarColor == i
                                      ? Border.all(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface,
                                          width: 3,
                                        )
                                      : null,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ---------------------------------------------------- receiving
          _Section(l.settingsReceiving),
          Card(
            child: Column(
              children: [
                for (final mode in ReceiveMode.values)
                  RadioListTile<ReceiveMode>(
                    value: mode,
                    // ignore: deprecated_member_use
                    groupValue: settings.receiveMode,
                    // ignore: deprecated_member_use
                    onChanged: (v) =>
                        notifier.edit((s) => s.copyWith(receiveMode: v)),
                    title: Text(switch (mode) {
                      ReceiveMode.ask => l.receiveModeAsk,
                      ReceiveMode.trustedAuto => l.receiveModeTrusted,
                      ReceiveMode.pin => l.receiveModePin,
                    }),
                    subtitle: Text(switch (mode) {
                      ReceiveMode.ask => l.receiveModeAskDesc,
                      ReceiveMode.trustedAuto => l.receiveModeTrustedDesc,
                      ReceiveMode.pin => l.receiveModePinDesc,
                    }),
                  ),
                if (settings.receiveMode == ReceiveMode.pin) ...[
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.pin_rounded),
                    title: Text(l.settingsPin),
                    subtitle: Text(
                      settings.pin.isEmpty
                          ? l.settingsPinDesc
                          : '•' * settings.pin.length,
                    ),
                    trailing: const Icon(Icons.edit_rounded),
                    onTap: () => _editPin(context, ref, settings.pin),
                  ),
                ],
                const Divider(height: 1),
                SwitchListTile(
                  secondary: Icon(
                    Icons.flash_on_rounded,
                    color: settings.quickSave ? SuviColors.signalAmber : null,
                  ),
                  title: Text(l.settingsQuickSave),
                  subtitle: Text(l.settingsQuickSaveDesc),
                  value: settings.quickSave,
                  onChanged: (v) =>
                      notifier.edit((s) => s.copyWith(quickSave: v)),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(l.settingsSaveFolder),
                  subtitle: Text(
                    settings.saveDirectory,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    final d = await fs.getDirectoryPath();
                    if (d != null) {
                      await notifier.edit((s) => s.copyWith(saveDirectory: d));
                    }
                  },
                ),
              ],
            ),
          ),

          // ---------------------------------------------- trusted devices
          _Section('${l.settingsTrustedDevices} (${trusted.length})'),
          Card(
            child: trusted.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(SuviSpacing.lg),
                    child: Text(
                      l.settingsNoTrusted,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : Column(
                    children: [
                      for (final d in trusted)
                        ListTile(
                          leading: Icon(
                            d.blocked
                                ? Icons.block_rounded
                                : Icons.verified_user_rounded,
                            color: d.blocked
                                ? Theme.of(context).colorScheme.error
                                : null,
                          ),
                          title: Text(d.alias),
                          subtitle: Text(
                            '${d.fingerprint.substring(0, 12).toUpperCase()}'
                            '${d.autoAccept ? ' · auto-accept' : ''}'
                            '${d.favorite ? ' · ★' : ''}',
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                            ),
                          ),
                          trailing: IconButton(
                            tooltip: l.untrustDevice,
                            icon: const Icon(Icons.delete_outline_rounded),
                            onPressed: () async {
                              final store = await ref.read(
                                trustStoreProvider.future,
                              );
                              await store.remove(d.fingerprint);
                            },
                          ),
                        ),
                    ],
                  ),
          ),

          // ------------------------------------------------------ network
          _Section(l.settingsNetwork),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.settings_ethernet_rounded),
                  title: Text(l.settingsPort),
                  subtitle: Text(
                    '${services?.server.port ?? settings.port} · ${l.settingsPortDesc}',
                  ),
                  trailing: const Icon(Icons.edit_rounded),
                  onTap: () => _editPort(context, ref, settings.port),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.lock_rounded),
                  title: Text(l.settingsEncryption),
                  subtitle: Text(
                    services == null
                        ? '…'
                        : l.settingsEncryptionDesc(
                            services.identity.shortFingerprint,
                          ),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.copy_rounded),
                    onPressed: services == null
                        ? null
                        : () {
                            Clipboard.setData(
                              ClipboardData(
                                text: services.identity.fingerprint,
                              ),
                            );
                            ScaffoldMessenger.of(
                              context,
                            ).showSnackBar(SnackBar(content: Text(l.copied)));
                          },
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.travel_explore_rounded),
                  title: Text(l.scanNetwork),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => services?.discovery.scanSubnet(),
                ),
              ],
            ),
          ),

          // ---------------------------------------------------- web share
          _Section(l.settingsWebShare),
          const _WebShareCard(),

          // --------------------------------------------------- appearance
          _Section(l.settingsAppearance),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.brightness_6_rounded),
                  title: Text(l.settingsTheme),
                  trailing: SegmentedButton<ThemeMode>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: ThemeMode.system,
                        label: Text(l.themeSystem),
                      ),
                      const ButtonSegment(
                        value: ThemeMode.light,
                        icon: Icon(Icons.light_mode_rounded),
                      ),
                      const ButtonSegment(
                        value: ThemeMode.dark,
                        icon: Icon(Icons.dark_mode_rounded),
                      ),
                    ],
                    selected: {settings.themeMode},
                    onSelectionChanged: (s) =>
                        notifier.edit((x) => x.copyWith(themeMode: s.first)),
                  ),
                ),
                const Divider(height: 1),
                _PaletteSelector(
                  selected: settings.palette,
                  onSelected: (palette) => notifier.edit(
                    (s) => s.copyWith(palette: palette, dynamicColor: false),
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.palette_outlined),
                  title: Text(l.settingsDynamicColor),
                  subtitle: Text(l.settingsPaletteHint),
                  value: settings.dynamicColor,
                  onChanged: (v) =>
                      notifier.edit((s) => s.copyWith(dynamicColor: v)),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.translate_rounded),
                  title: Text(l.settingsLanguage),
                  trailing: DropdownButton<String?>(
                    value: settings.locale,
                    underline: const SizedBox.shrink(),
                    items: [
                      DropdownMenuItem(value: null, child: Text(l.themeSystem)),
                      const DropdownMenuItem(
                        value: 'en',
                        child: Text('English'),
                      ),
                      const DropdownMenuItem(
                        value: 'hi',
                        child: Text('हिन्दी'),
                      ),
                    ],
                    onChanged: (v) => notifier.edit(
                      (s) => v == null
                          ? s.copyWith(clearLocale: true)
                          : s.copyWith(locale: v),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ------------------------------------------------------ desktop
          if (isDesktop) ...[
            _Section(l.settingsDesktop),
            Card(
              child: SwitchListTile(
                secondary: const Icon(Icons.dock_rounded),
                title: Text(l.settingsMinimizeToTray),
                subtitle: Text(l.settingsMinimizeToTrayDesc),
                value: settings.closeToTray,
                onChanged: (v) =>
                    notifier.edit((s) => s.copyWith(closeToTray: v)),
              ),
            ),
          ],

          // ------------------------------------------------------- updates
          _Section(l.settingsUpdates),
          const _UpdateCard(),

          // -------------------------------------------------------- about
          _Section(l.settingsAbout),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.info_outline_rounded),
                  title: const Text('Suvi Share'),
                  subtitle: Text(l.settingsVersion(version)),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.shield_outlined),
                  title: Text(l.settingsPrivacy),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(
                    Icons.code_rounded,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(
                    l.developedBy,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editAlias(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final l = AppLocalizations.of(context);
    final c = TextEditingController(text: current);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.settingsDeviceName),
        content: TextField(
          controller: c,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: l.onboardingNameHint,
            suffixIcon: IconButton(
              tooltip: l.onboardingShuffle,
              icon: const Icon(Icons.casino_rounded),
              onPressed: () => c.text = AliasGenerator.generate(),
            ),
          ),
          onSubmitted: (x) => Navigator.of(ctx).pop(x),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(c.text),
            child: Text(l.save),
          ),
        ],
      ),
    );
    if (v != null && v.trim().isNotEmpty) {
      await ref
          .read(settingsProvider.notifier)
          .edit((s) => s.copyWith(alias: v.trim()));
    }
  }

  Future<void> _editPin(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final l = AppLocalizations.of(context);
    final c = TextEditingController(text: current);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.settingsPin),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          maxLength: 8,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(hintText: l.pinHint),
          onSubmitted: (x) => Navigator.of(ctx).pop(x),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(c.text),
            child: Text(l.save),
          ),
        ],
      ),
    );
    if (v != null) {
      await ref
          .read(settingsProvider.notifier)
          .edit((s) => s.copyWith(pin: v.trim()));
    }
  }

  Future<void> _editPort(
    BuildContext context,
    WidgetRef ref,
    int current,
  ) async {
    final l = AppLocalizations.of(context);
    final c = TextEditingController(text: '$current');
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.settingsPort),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(helperText: l.settingsPortDesc),
          onSubmitted: (x) => Navigator.of(ctx).pop(x),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(c.text),
            child: Text(l.save),
          ),
        ],
      ),
    );
    final port = int.tryParse(v ?? '');
    if (port == null || port < 1024 || port > 65535 || port == current) return;
    await ref
        .read(settingsProvider.notifier)
        .edit((s) => s.copyWith(port: port));
    await ref.read(appServicesProvider.notifier).restart();
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$port ✓')));
    }
  }
}

/// Toggles the plain-HTTP browser listener and shows the address + QR.
class _WebShareCard extends ConsumerWidget {
  const _WebShareCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final web = ref.watch(webShareProvider).value;
    final running = web?.isRunning ?? false;
    final noWifi = web?.error == 'not-connected';

    return Card(
      child: Column(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.language_rounded),
            title: Text(l.settingsWebShare),
            subtitle: Text(l.settingsWebShareDesc),
            value: running,
            onChanged: (_) => ref.read(webShareProvider.notifier).toggle(),
          ),
          if (noWifi)
            ListTile(
              leading: Icon(Icons.wifi_off_rounded, color: scheme.error),
              title: Text(l.webShareNoWifi),
            ),
          if (running) ...[
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.link_rounded),
              title: SelectableText(
                web!.url!,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              subtitle: Text(l.webShareOn),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: l.copy,
                    icon: const Icon(Icons.copy_rounded),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: web.url!));
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text(l.copied)));
                    },
                  ),
                  IconButton(
                    tooltip: l.showMyQr,
                    icon: const Icon(Icons.qr_code_2_rounded),
                    onPressed: () => _showQr(context, web.url!, l),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.password_rounded),
              title: SelectableText(
                web.pin ?? '—',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                  letterSpacing: 3,
                ),
              ),
              subtitle: Text(l.webShareSessionPin),
              trailing: IconButton(
                tooltip: l.copy,
                icon: const Icon(Icons.copy_rounded),
                onPressed: web.pin == null
                    ? null
                    : () {
                        Clipboard.setData(ClipboardData(text: web.pin!));
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text(l.copied)));
                      },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                SuviSpacing.lg,
                0,
                SuviSpacing.lg,
                SuviSpacing.lg,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: SuviSpacing.sm),
                  Expanded(
                    child: Text(
                      l.webShareHttpNote,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showQr(BuildContext context, String url, AppLocalizations l) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.settingsWebShare),
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
                width: 220,
                height: 220,
                child: PrettyQrView.data(data: url),
              ),
            ),
            const SizedBox(height: SuviSpacing.lg),
            SelectableText(url, style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: SuviSpacing.sm),
            Text(
              l.webShareOn,
              textAlign: TextAlign.center,
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l.close),
          ),
        ],
      ),
    );
  }
}

class _UpdateCard extends ConsumerWidget {
  const _UpdateCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final asyncUpdate = ref.watch(appUpdateProvider);
    final update = asyncUpdate.value;
    final checking = asyncUpdate.isLoading || (update?.checking ?? false);
    final available = update?.updateAvailable ?? false;
    final failed =
        update?.error != null ||
        (update != null && update.latest == null && update.lastChecked != null);
    final updateUri = update?.asset?.downloadUri ?? update?.latest?.releaseUri;
    final scheme = Theme.of(context).colorScheme;

    final status = checking
        ? l.updateChecking
        : failed
        ? l.updateCheckFailed
        : available
        ? l.updateAvailable(update?.latest?.version ?? '')
        : update?.lastChecked == null
        ? l.updateNeverChecked
        : l.updateUpToDate;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SwitchListTile(
            secondary: Icon(
              available
                  ? Icons.system_update_alt_rounded
                  : Icons.update_rounded,
              color: available ? scheme.primary : null,
            ),
            title: Text(l.updateAutoCheck),
            subtitle: Text(l.updateAutoCheckDesc),
            value: update?.autoCheck ?? true,
            onChanged: update == null
                ? null
                : ref.read(appUpdateProvider.notifier).setAutoCheck,
          ),
          const Divider(height: 1),
          ListTile(
            leading: checking
                ? const SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : Icon(
                    available
                        ? Icons.new_releases_rounded
                        : failed
                        ? Icons.cloud_off_rounded
                        : Icons.verified_rounded,
                    color: available
                        ? scheme.primary
                        : failed
                        ? scheme.error
                        : scheme.secondary,
                  ),
            title: Text(status),
            subtitle: update == null
                ? null
                : Text(l.settingsVersion(update.displayVersion)),
            trailing: IconButton(
              tooltip: l.updateCheckNow,
              onPressed: checking
                  ? null
                  : ref.read(appUpdateProvider.notifier).checkNow,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ),
          if (available && updateUri != null) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                SuviSpacing.lg,
                SuviSpacing.md,
                SuviSpacing.lg,
                SuviSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed: () => _openUpdate(context, updateUri),
                    icon: const Icon(Icons.download_rounded),
                    label: Text(
                      update?.asset == null
                          ? l.updateOpenRelease
                          : l.updateDownload,
                    ),
                  ),
                  const SizedBox(height: SuviSpacing.sm),
                  Text(
                    l.updateInstallNote,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openUpdate(BuildContext context, Uri uri) async {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).updateOpenFailed)),
      );
    }
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      SuviSpacing.xs,
      SuviSpacing.xl,
      0,
      SuviSpacing.sm,
    ),
    child: Text(
      title,
      style: Theme.of(context).textTheme.labelLarge
          ?.copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );
}

class _PaletteSelector extends StatelessWidget {
  const _PaletteSelector({required this.selected, required this.onSelected});

  final AppPalette selected;
  final ValueChanged<AppPalette> onSelected;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SuviSpacing.lg,
        SuviSpacing.md,
        SuviSpacing.lg,
        SuviSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.color_lens_rounded, color: scheme.onSurfaceVariant),
              const SizedBox(width: SuviSpacing.lg),
              Text(
                l.settingsColorPalette,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
          ),
          const SizedBox(height: SuviSpacing.md),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final palette in AppPalette.values) ...[
                  _PaletteSwatch(
                    palette: palette,
                    label: _paletteLabel(l, palette),
                    selected: palette == selected,
                    onTap: () => onSelected(palette),
                  ),
                  if (palette != AppPalette.values.last)
                    const SizedBox(width: SuviSpacing.sm),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _paletteLabel(AppLocalizations l, AppPalette palette) =>
      switch (palette) {
        AppPalette.suvi => l.paletteSuvi,
        AppPalette.ocean => l.paletteOcean,
        AppPalette.sunset => l.paletteSunset,
        AppPalette.forest => l.paletteForest,
        AppPalette.lavender => l.paletteLavender,
        AppPalette.rose => l.paletteRose,
      };
}

class _PaletteSwatch extends StatelessWidget {
  const _PaletteSwatch({
    required this.palette,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final AppPalette palette;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(SuviRadius.md),
        onTap: onTap,
        child: AnimatedContainer(
          duration: SuviMotion.short,
          curve: SuviMotion.decelerate,
          width: 82,
          padding: const EdgeInsets.symmetric(
            horizontal: SuviSpacing.sm,
            vertical: SuviSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: selected
                ? scheme.primaryContainer.withValues(alpha: 0.55)
                : scheme.surfaceContainerHighest.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(SuviRadius.md),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [palette.seed, palette.accent],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: palette.seed.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: selected
                    ? const Icon(Icons.check_rounded, color: Colors.white)
                    : null,
              ),
              const SizedBox(height: SuviSpacing.xs),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
