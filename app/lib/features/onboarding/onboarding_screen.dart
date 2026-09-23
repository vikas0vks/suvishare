import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:suvi_core/suvi_core.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/device_avatar.dart';
import '../../core/widgets/radar.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/settings.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  final _aliasController = TextEditingController();
  int _page = 0;
  bool _aliasInitialised = false;

  @override
  void dispose() {
    _controller.dispose();
    _aliasController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final settings = ref.watch(settingsProvider).value;
    if (settings == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_aliasInitialised) {
      _aliasController.text = settings.alias;
      _aliasInitialised = true;
    }

    final pages = <Widget>[
      _WelcomePage(),
      _NamePage(controller: _aliasController, settings: settings),
      _ReceiveModePage(settings: settings),
      const _PermissionsPage(),
    ];

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              children: [
                Expanded(
                  child: PageView(
                    controller: _controller,
                    onPageChanged: (i) => setState(() => _page = i),
                    children: pages,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(SuviSpacing.xl),
                  child: Row(
                    children: [
                      if (_page > 0)
                        TextButton(
                          onPressed: () => _controller.previousPage(
                            duration: SuviMotion.medium,
                            curve: SuviMotion.emphasized,
                          ),
                          child: Text(l.back),
                        ),
                      const Spacer(),
                      Row(
                        children: [
                          for (var i = 0; i < pages.length; i++)
                            AnimatedContainer(
                              duration: SuviMotion.short,
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              width: i == _page ? 20 : 8,
                              height: 8,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(4),
                                color: i == _page
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHighest,
                              ),
                            ),
                        ],
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: () => _next(pages.length),
                        child: Text(
                          _page == 0
                              ? l.onboardingGetStarted
                              : _page == pages.length - 1
                              ? l.onboardingFinish
                              : l.next,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _next(int pageCount) async {
    // Persist the alias when leaving the name page.
    if (_page == 1) {
      final alias = _aliasController.text.trim();
      if (alias.isNotEmpty) {
        await ref
            .read(settingsProvider.notifier)
            .edit((s) => s.copyWith(alias: alias));
      }
    }
    if (_page < pageCount - 1) {
      await _controller.nextPage(
        duration: SuviMotion.medium,
        curve: SuviMotion.emphasized,
      );
      return;
    }
    await ref
        .read(settingsProvider.notifier)
        .edit((s) => s.copyWith(onboardingDone: true));
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.title, required this.body, this.art, this.extra});
  final String title;
  final String body;
  final Widget? art;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: SuviSpacing.xl,
        vertical: SuviSpacing.xxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (art != null) Center(child: art),
          if (art != null) const SizedBox(height: SuviSpacing.xxl),
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: SuviSpacing.md),
          Text(
            body,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          if (extra != null) ...[
            const SizedBox(height: SuviSpacing.xxl),
            extra!,
          ],
        ],
      ).animate().fadeIn(duration: SuviMotion.medium),
    );
  }
}

class _WelcomePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return _Page(
      title: l.onboardingWelcomeTitle,
      body: l.onboardingWelcomeBody,
      art: RadarView(
        size: 200,
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: [scheme.primary, scheme.tertiary]),
          ),
          child: const Icon(Icons.send_rounded, color: Colors.white, size: 34),
        ),
      ),
      extra: Center(
        child: Text(
          l.tagline,
          style: Theme.of(context).textTheme.labelLarge
              ?.copyWith(color: scheme.primary),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _NamePage extends ConsumerWidget {
  const _NamePage({required this.controller, required this.settings});
  final TextEditingController controller;
  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return _Page(
      title: l.onboardingNameTitle,
      body: l.onboardingNameBody,
      art: DeviceAvatar(
        colorIndex: settings.avatarColor,
        deviceType: (Platform.isAndroid || Platform.isIOS)
            ? DeviceType.mobile
            : DeviceType.desktop,
        size: 88,
      ),
      extra: Column(
        children: [
          TextField(
            controller: controller,
            textAlign: TextAlign.center,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: l.onboardingNameHint,
              suffixIcon: IconButton(
                tooltip: l.onboardingShuffle,
                icon: const Icon(Icons.casino_rounded),
                onPressed: () => controller.text = AliasGenerator.generate(),
              ),
            ),
          ),
          const SizedBox(height: SuviSpacing.xl),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: SuviSpacing.md,
            children: [
              for (var i = 0; i < SuviColors.avatarPalette.length; i++)
                InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: () => ref
                      .read(settingsProvider.notifier)
                      .edit((s) => s.copyWith(avatarColor: i)),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: SuviColors.avatar(i),
                      border: settings.avatarColor == i
                          ? Border.all(
                              color: Theme.of(context).colorScheme.onSurface,
                              width: 3,
                            )
                          : null,
                    ),
                    child: settings.avatarColor == i
                        ? const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 20,
                          )
                        : null,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReceiveModePage extends ConsumerWidget {
  const _ReceiveModePage({required this.settings});
  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final options = <(ReceiveMode, String, String, IconData)>[
      (
        ReceiveMode.ask,
        l.receiveModeAsk,
        l.receiveModeAskDesc,
        Icons.help_outline_rounded,
      ),
      (
        ReceiveMode.trustedAuto,
        l.receiveModeTrusted,
        l.receiveModeTrustedDesc,
        Icons.verified_user_outlined,
      ),
      (
        ReceiveMode.pin,
        l.receiveModePin,
        l.receiveModePinDesc,
        Icons.pin_outlined,
      ),
    ];
    return _Page(
      title: l.onboardingReceiveTitle,
      body: l.onboardingReceiveBody,
      extra: Column(
        children: [
          for (final (mode, title, desc, icon) in options)
            Padding(
              padding: const EdgeInsets.only(bottom: SuviSpacing.sm),
              child: Card(
                color: settings.receiveMode == mode
                    ? Theme.of(context).colorScheme.secondaryContainer
                    : null,
                child: RadioListTile<ReceiveMode>(
                  value: mode,
                  // ignore: deprecated_member_use
                  groupValue: settings.receiveMode,
                  // ignore: deprecated_member_use
                  onChanged: (v) => ref
                      .read(settingsProvider.notifier)
                      .edit(
                        (s) => s.copyWith(receiveMode: v ?? ReceiveMode.ask),
                      ),
                  secondary: Icon(icon),
                  title: Text(title),
                  subtitle: Text(desc),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PermissionsPage extends StatefulWidget {
  const _PermissionsPage();
  @override
  State<_PermissionsPage> createState() => _PermissionsPageState();
}

class _PermissionsPageState extends State<_PermissionsPage> {
  bool _notificationsAsked = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isAndroid = Platform.isAndroid;
    return _Page(
      title: isAndroid ? 'A couple of permissions' : 'One last thing',
      body: isAndroid
          ? 'Suvi Share only asks for what it needs to find devices and tell you when files arrive. It never reads your location.'
          : 'Your firewall will ask whether Suvi Share may communicate on private networks. Choose Allow, or other devices will not see you.',
      art: Icon(
        isAndroid ? Icons.shield_outlined : Icons.security_rounded,
        size: 72,
        color: scheme.primary,
      ),
      extra: Column(
        children: [
          if (isAndroid)
            Card(
              child: ListTile(
                leading: const Icon(Icons.notifications_active_outlined),
                title: const Text('Notifications'),
                subtitle: const Text(
                  'So you see incoming requests and transfer progress.',
                ),
                trailing: _notificationsAsked
                    ? const Icon(Icons.check_circle_rounded)
                    : FilledButton.tonal(
                        onPressed: () async {
                          await Permission.notification.request();
                          if (mounted) {
                            setState(() => _notificationsAsked = true);
                          }
                        },
                        child: const Text('Allow'),
                      ),
              ),
            )
          else
            Card(
              child: ListTile(
                leading: Icon(
                  Icons.info_outline_rounded,
                  color: scheme.primary,
                ),
                title: const Text('Windows Firewall'),
                subtitle: const Text(
                  'If the prompt appears, tick "Private networks" and click Allow access.',
                ),
              ),
            ),
          const SizedBox(height: SuviSpacing.lg),
          Card(
            color: scheme.primaryContainer.withValues(alpha: 0.4),
            child: const ListTile(
              leading: Icon(Icons.lock_outline_rounded),
              title: Text('Private by design'),
              subtitle: Text(
                'No account, no analytics, no internet. Transfers are encrypted with TLS.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
