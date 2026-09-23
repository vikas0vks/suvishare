import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:suvi_core/suvi_core.dart';

import '../core/theme/app_theme.dart';

enum ReceiveMode { ask, trustedAuto, pin }

@immutable
class AppSettings {
  const AppSettings({
    required this.alias,
    required this.avatarColor,
    required this.port,
    required this.receiveMode,
    required this.pin,
    required this.quickSave,
    required this.saveDirectory,
    required this.themeMode,
    required this.palette,
    required this.dynamicColor,
    required this.closeToTray,
    required this.onboardingDone,
    required this.receiveEnabled,
    required this.locale,
  });

  final String alias;
  final int avatarColor;
  final int port;
  final ReceiveMode receiveMode;
  final String pin;
  final bool quickSave;
  final String saveDirectory;
  final ThemeMode themeMode;
  final AppPalette palette;
  final bool dynamicColor;
  final bool closeToTray;
  final bool onboardingDone;
  final bool receiveEnabled;

  /// `null` = follow system; otherwise language code ('en', 'hi').
  final String? locale;

  AppSettings copyWith({
    String? alias,
    int? avatarColor,
    int? port,
    ReceiveMode? receiveMode,
    String? pin,
    bool? quickSave,
    String? saveDirectory,
    ThemeMode? themeMode,
    AppPalette? palette,
    bool? dynamicColor,
    bool? closeToTray,
    bool? onboardingDone,
    bool? receiveEnabled,
    String? locale,
    bool clearLocale = false,
  }) => AppSettings(
    alias: alias ?? this.alias,
    avatarColor: avatarColor ?? this.avatarColor,
    port: port ?? this.port,
    receiveMode: receiveMode ?? this.receiveMode,
    pin: pin ?? this.pin,
    quickSave: quickSave ?? this.quickSave,
    saveDirectory: saveDirectory ?? this.saveDirectory,
    themeMode: themeMode ?? this.themeMode,
    palette: palette ?? this.palette,
    dynamicColor: dynamicColor ?? this.dynamicColor,
    closeToTray: closeToTray ?? this.closeToTray,
    onboardingDone: onboardingDone ?? this.onboardingDone,
    receiveEnabled: receiveEnabled ?? this.receiveEnabled,
    locale: clearLocale ? null : (locale ?? this.locale),
  );

  Map<String, dynamic> toJson() => {
    'alias': alias,
    'avatarColor': avatarColor,
    'port': port,
    'receiveMode': receiveMode.name,
    'pin': pin,
    'quickSave': quickSave,
    'saveDirectory': saveDirectory,
    'themeMode': themeMode.name,
    'palette': palette.name,
    'dynamicColor': dynamicColor,
    'closeToTray': closeToTray,
    'onboardingDone': onboardingDone,
    'receiveEnabled': receiveEnabled,
    'locale': locale,
  };

  static AppSettings fromJson(Map<String, dynamic> j, AppSettings defaults) {
    T en<T extends Enum>(List<T> values, Object? raw, T fallback) =>
        values.firstWhere((v) => v.name == raw, orElse: () => fallback);
    return AppSettings(
      alias: (j['alias'] as String?) ?? defaults.alias,
      avatarColor: (j['avatarColor'] as num?)?.toInt() ?? defaults.avatarColor,
      port: (j['port'] as num?)?.toInt() ?? defaults.port,
      receiveMode: en(
        ReceiveMode.values,
        j['receiveMode'],
        defaults.receiveMode,
      ),
      pin: (j['pin'] as String?) ?? defaults.pin,
      quickSave: (j['quickSave'] as bool?) ?? defaults.quickSave,
      saveDirectory: (j['saveDirectory'] as String?) ?? defaults.saveDirectory,
      themeMode: en(ThemeMode.values, j['themeMode'], defaults.themeMode),
      palette: en(AppPalette.values, j['palette'], defaults.palette),
      dynamicColor: (j['dynamicColor'] as bool?) ?? defaults.dynamicColor,
      closeToTray: (j['closeToTray'] as bool?) ?? defaults.closeToTray,
      onboardingDone: (j['onboardingDone'] as bool?) ?? defaults.onboardingDone,
      receiveEnabled: (j['receiveEnabled'] as bool?) ?? defaults.receiveEnabled,
      locale: j['locale'] as String?,
    );
  }
}

/// Loads defaults (platform-aware) then persists every change.
class SettingsNotifier extends AsyncNotifier<AppSettings> {
  static const _key = 'suvi.settings.v1';
  SharedPreferences? _prefs;

  @override
  Future<AppSettings> build() async {
    _prefs = await SharedPreferences.getInstance();
    final defaults = AppSettings(
      alias: AliasGenerator.generate(),
      avatarColor: DateTime.now().millisecond % 8,
      port: SuviConstants.defaultPort,
      receiveMode: ReceiveMode.ask,
      pin: '',
      quickSave: false,
      saveDirectory: await _defaultSaveDir(),
      themeMode: ThemeMode.system,
      palette: AppPalette.suvi,
      dynamicColor: Platform.isAndroid,
      closeToTray: true,
      onboardingDone: false,
      receiveEnabled: true,
      locale: null,
    );
    final raw = _prefs!.getString(_key);
    if (raw == null) {
      await _prefs!.setString(_key, jsonEncode(defaults.toJson()));
      return defaults;
    }
    try {
      var loaded = AppSettings.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
        defaults,
      );
      loaded = await _migrate(loaded);
      return loaded;
    } catch (_) {
      return defaults;
    }
  }

  /// One-time repairs for state written by old bugs.
  Future<AppSettings> _migrate(AppSettings s) async {
    const migrationKey = 'suvi.settings.migration';
    final done = _prefs!.getInt(migrationKey) ?? 1;
    var next = s;
    if (done < 2) {
      // v0.1.0 silently persisted a random ephemeral port when the configured
      // one was busy at startup (fixed since — the fallback is runtime-only).
      // A saved port in the ephemeral range can only come from that bug.
      if (next.port >= 49152) {
        next = next.copyWith(port: SuviConstants.defaultPort);
      }
      await _prefs!.setInt(migrationKey, 2);
      await _prefs!.setString(_key, jsonEncode(next.toJson()));
    }
    return next;
  }

  Future<void> edit(AppSettings Function(AppSettings) fn) async {
    final cur = state.value;
    if (cur == null) return;
    final next = fn(cur);
    state = AsyncData(next);
    await _prefs?.setString(_key, jsonEncode(next.toJson()));
  }

  static Future<String> _defaultSaveDir() async {
    try {
      if (Platform.isAndroid) {
        // Public Downloads on Android; created lazily.
        final d = Directory('/storage/emulated/0/Download/Suvi Share');
        return d.path;
      }
      final downloads = await getDownloadsDirectory();
      if (downloads != null) return p.join(downloads.path, 'Suvi Share');
    } catch (_) {}
    final docs = await getApplicationDocumentsDirectory();
    return p.join(docs.path, 'Suvi Share');
  }
}

final settingsProvider = AsyncNotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);
