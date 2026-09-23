import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suvi_core/suvi_core.dart';
import 'package:suvi_share/core/theme/app_theme.dart';
import 'package:suvi_share/core/update/github_release.dart';
import 'package:suvi_share/core/util/format.dart';
import 'package:suvi_share/core/widgets/device_avatar.dart';
import 'package:suvi_share/core/widgets/radar.dart';
import 'package:suvi_share/features/send/file_category.dart';
import 'package:suvi_share/l10n/app_localizations.dart';
import 'package:suvi_share/providers/settings.dart';

Widget wrap(Widget child, {Locale? locale, Size size = const Size(400, 800)}) {
  return MaterialApp(
    locale: locale,
    theme: SuviTheme.light(null),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: Scaffold(body: child),
    ),
  );
}

void main() {
  group('formatting', () {
    test('formatBytes', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(512), '512 B');
      expect(formatBytes(1024), '1.0 KB');
      expect(formatBytes(1536), '1.5 KB');
      expect(formatBytes(1024 * 1024), '1.0 MB');
      expect(formatBytes(150 * 1024 * 1024), '150 MB');
      expect(formatBytes(3 * 1024 * 1024 * 1024), '3.0 GB');
    });

    test('iconForMime picks sensible icons', () {
      expect(iconForMime('image/png'), Icons.image_rounded);
      expect(iconForMime('video/mp4'), Icons.movie_rounded);
      expect(iconForMime('application/pdf'), Icons.picture_as_pdf_rounded);
      expect(
        iconForMime('application/vnd.android.package-archive'),
        Icons.android_rounded,
      );
      expect(iconForMime('application/zip'), Icons.folder_zip_rounded);
      expect(
        iconForMime('application/x-thing'),
        Icons.insert_drive_file_rounded,
      );
    });

    test('iconForDevice covers every device type', () {
      for (final t in DeviceType.values) {
        expect(iconForDevice(t), isA<IconData>());
      }
    });

    test('SpeedMeter reports a positive rate', () async {
      final m = SpeedMeter();
      m.update(0);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      final v = m.update(600000);
      expect(v, greaterThan(0));
    });
  });

  group('theme', () {
    test('window classes match Material 3 breakpoints', () {
      expect(windowClassOf(599), WindowClass.compact);
      expect(windowClassOf(600), WindowClass.medium);
      expect(windowClassOf(839), WindowClass.medium);
      expect(windowClassOf(840), WindowClass.expanded);
    });

    test('avatar palette wraps around', () {
      expect(SuviColors.avatar(0), SuviColors.avatarPalette.first);
      expect(SuviColors.avatar(8), SuviColors.avatarPalette.first);
      expect(SuviColors.avatar(9), SuviColors.avatarPalette[1]);
    });

    test('light and dark themes both build with the brand seed', () {
      final light = SuviTheme.light(null);
      final dark = SuviTheme.dark(null);
      expect(light.brightness, Brightness.light);
      expect(dark.brightness, Brightness.dark);
      expect(light.useMaterial3, isTrue);
    });

    test('every color palette builds in light and dark with a unique seed', () {
      final primaryColors = <Color>{};
      for (final palette in AppPalette.values) {
        final light = SuviTheme.light(null, palette: palette);
        final dark = SuviTheme.dark(null, palette: palette);
        expect(light.brightness, Brightness.light);
        expect(dark.brightness, Brightness.dark);
        expect(light.colorScheme.primary, isNot(dark.colorScheme.primary));
        primaryColors.add(palette.seed);
      }
      expect(primaryColors, hasLength(AppPalette.values.length));
    });
  });

  group('file categories', () {
    test('general keeps the picker unrestricted', () {
      expect(ShareFileCategory.general.mimeTypes, isNull);
      expect(ShareFileCategory.general.extensions, isNull);
    });

    test('specialized categories expose useful filters', () {
      expect(
        ShareFileCategory.documents.mimeTypes,
        contains('application/pdf'),
      );
      expect(ShareFileCategory.documents.extensions, contains('docx'));
      expect(ShareFileCategory.images.mimeTypes, const ['image/*']);
      expect(ShareFileCategory.videos.mimeTypes, const ['video/*']);
      expect(ShareFileCategory.music.mimeTypes, const ['audio/*']);
      expect(
        ShareFileCategory.compressed.extensions,
        containsAll(['zip', '7z', 'rar']),
      );
      expect(
        ShareFileCategory.other.extensions,
        containsAll(['apk', 'exe', 'deb']),
      );
    });
  });

  group('settings compatibility', () {
    const defaults = AppSettings(
      alias: 'Test Device',
      avatarColor: 0,
      port: 53317,
      receiveMode: ReceiveMode.ask,
      pin: '',
      quickSave: false,
      saveDirectory: 'downloads',
      themeMode: ThemeMode.system,
      palette: AppPalette.suvi,
      dynamicColor: false,
      closeToTray: true,
      onboardingDone: true,
      receiveEnabled: true,
      locale: null,
    );

    test('old settings without a palette migrate to the default', () {
      final loaded = AppSettings.fromJson(<String, dynamic>{
        'alias': 'Saved Device',
      }, defaults);
      expect(loaded.alias, 'Saved Device');
      expect(loaded.palette, AppPalette.suvi);
    });

    test('selected palette survives JSON persistence', () {
      final saved = defaults.copyWith(palette: AppPalette.lavender).toJson();
      final loaded = AppSettings.fromJson(saved, defaults);
      expect(loaded.palette, AppPalette.lavender);
    });
  });

  group('GitHub release updates', () {
    test('semantic versions compare without v prefix or build metadata', () {
      expect(compareVersions('v0.4.1', '0.4.0+7'), greaterThan(0));
      expect(compareVersions('0.4.0', '0.4.0+7'), 0);
      expect(compareVersions('1.0.0', '1.0.0-beta.2'), greaterThan(0));
      expect(compareVersions('1.0.0-beta.10', '1.0.0-beta.2'), greaterThan(0));
    });

    test('latest release parser keeps only trusted HTTPS assets', () {
      final release = parseGitHubRelease(
        jsonEncode({
          'tag_name': 'v0.5.0',
          'name': 'Suvi Share 0.5.0',
          'html_url':
              'https://github.com/vikas0vks/suvishare/releases/tag/v0.5.0',
          'published_at': '2026-09-23T10:00:00Z',
          'assets': [
            {
              'name': 'SuviShare-0.5.0-android-universal.apk',
              'browser_download_url': 'https://github.com/vikas0vks/suvishare/releases/download/v0.5.0/app.apk',
              'size': 42,
            },
            {
              'name': 'not-trusted.apk',
              'browser_download_url': 'https://example.com/not-trusted.apk',
              'size': 42,
            },
          ],
        }),
      );

      expect(release.version, '0.5.0');
      expect(release.assets, hasLength(1));
      expect(release.assets.single.downloadUri.host, 'github.com');
    });

    test('asset selection chooses platform and Android ABI', () {
      ReleaseAsset asset(String name) => ReleaseAsset(
        name: name,
        downloadUri: Uri.parse('https://github.com/vikas0vks/suvishare/$name'),
        size: 1,
      );
      final assets = [
        asset('SuviShare-0.5.0-android-arm64.apk'),
        asset('SuviShare-0.5.0-android-universal.apk'),
        asset('SuviShare-0.5.0-windows-x64-setup.exe'),
        asset('SuviShare-0.5.0-linux-amd64.deb'),
      ];

      expect(
        selectReleaseAsset(
          assets,
          platform: 'android',
          androidAbis: ['arm64-v8a'],
        )?.name,
        contains('android-arm64'),
      );
      expect(
        selectReleaseAsset(assets, platform: 'windows')?.name,
        endsWith('windows-x64-setup.exe'),
      );
      expect(
        selectReleaseAsset(assets, platform: 'linux')?.name,
        endsWith('linux-amd64.deb'),
      );
    });
  });

  testWidgets('DeviceAvatar renders the device glyph', (tester) async {
    await tester.pumpWidget(
      wrap(const DeviceAvatar(colorIndex: 2, deviceType: DeviceType.mobile)),
    );
    expect(find.byIcon(Icons.smartphone_rounded), findsOneWidget);
  });

  testWidgets('RadarView keeps animating by default', (tester) async {
    await tester.pumpWidget(wrap(const RadarView(size: 200)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(RadarView), findsOneWidget);
    expect(tester.hasRunningAnimations, isTrue);
    // Tear down cleanly so the repeating controller does not leak into the
    // next test.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('RadarView settles when reduced motion is requested', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(body: RadarView(size: 200)),
        ),
      ),
    );
    // pumpAndSettle would time out if the radar kept looping.
    await tester.pumpAndSettle();
    expect(find.byType(RadarView), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
  });

  group('localization', () {
    testWidgets('English strings load', (tester) async {
      late AppLocalizations l;
      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (c) {
              l = AppLocalizations.of(c);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(l.appName, 'Suvi Share');
      expect(l.youAre('Brave Peacock'), contains('Brave Peacock'));
      expect(l.incomingFiles(1, '2 MB'), contains('1 file'));
      expect(l.incomingFiles(3, '2 MB'), contains('3 files'));
      expect(l.categoryCompressed, 'Compressed');
      expect(l.paletteLavender, 'Lavender');
    });

    testWidgets('Hindi strings load', (tester) async {
      late AppLocalizations l;
      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (c) {
              l = AppLocalizations.of(c);
              return const SizedBox();
            },
          ),
          locale: const Locale('hi'),
        ),
      );
      expect(l.navNearby, 'आस-पास');
      expect(l.send, 'भेजें');
      expect(l.youAre('Brave Peacock'), contains('Brave Peacock'));
      expect(l.categoryDocuments, 'डॉक्यूमेंट');
    });

    test('every supported locale is declared', () {
      expect(
        AppLocalizations.supportedLocales.map((l) => l.languageCode).toSet(),
        containsAll(<String>{'en', 'hi'}),
      );
    });
  });
}
