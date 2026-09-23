import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'l10n/app_localizations.dart';
import 'providers/settings.dart';
import 'router.dart';

class SuviApp extends ConsumerWidget {
  const SuviApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).value;
    final router = ref.watch(routerProvider);

    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        final useDynamic = settings?.dynamicColor ?? false;
        final palette = settings?.palette ?? AppPalette.suvi;
        return MaterialApp.router(
          title: 'Suvi Share',
          debugShowCheckedModeBanner: false,
          routerConfig: router,
          themeMode: settings?.themeMode ?? ThemeMode.system,
          theme: SuviTheme.light(
            useDynamic ? lightDynamic?.harmonized() : null,
            palette: palette,
          ),
          darkTheme: SuviTheme.dark(
            useDynamic ? darkDynamic?.harmonized() : null,
            palette: palette,
          ),
          themeAnimationDuration: SuviMotion.medium,
          themeAnimationCurve: SuviMotion.emphasized,
          locale: settings?.locale == null ? null : Locale(settings!.locale!),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
        );
      },
    );
  }
}
