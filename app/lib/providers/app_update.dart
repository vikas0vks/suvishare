import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/update/github_release.dart';

const suviLatestReleaseApi =
    'https://api.github.com/repos/vikas0vks/suvishare/releases/latest';

class AppUpdateState {
  const AppUpdateState({
    required this.currentVersion,
    required this.currentBuild,
    required this.autoCheck,
    this.latest,
    this.asset,
    this.lastChecked,
    this.checking = false,
    this.error,
  });

  final String currentVersion;
  final String currentBuild;
  final bool autoCheck;
  final ReleaseInfo? latest;
  final ReleaseAsset? asset;
  final DateTime? lastChecked;
  final bool checking;
  final String? error;

  String get displayVersion => '$currentVersion+$currentBuild';
  bool get updateAvailable =>
      latest != null && compareVersions(latest!.version, currentVersion) > 0;

  AppUpdateState copyWith({
    bool? autoCheck,
    ReleaseInfo? latest,
    ReleaseAsset? asset,
    DateTime? lastChecked,
    bool? checking,
    String? error,
    bool clearError = false,
    bool clearAsset = false,
  }) => AppUpdateState(
    currentVersion: currentVersion,
    currentBuild: currentBuild,
    autoCheck: autoCheck ?? this.autoCheck,
    latest: latest ?? this.latest,
    asset: clearAsset ? asset : (asset ?? this.asset),
    lastChecked: lastChecked ?? this.lastChecked,
    checking: checking ?? this.checking,
    error: clearError ? null : (error ?? this.error),
  );
}

class AppUpdateNotifier extends AsyncNotifier<AppUpdateState> {
  static const _autoKey = 'suvi.updates.auto.v1';
  static const _checkedKey = 'suvi.updates.checked.v1';
  static const _cacheKey = 'suvi.updates.release.v1';
  static const _checkInterval = Duration(hours: 24);
  static const _maxResponseBytes = 512 * 1024;

  SharedPreferences? _prefs;

  @override
  Future<AppUpdateState> build() async {
    final package = await PackageInfo.fromPlatform();
    _prefs = await SharedPreferences.getInstance();
    final autoCheck = _prefs!.getBool(_autoKey) ?? true;
    final checkedMs = _prefs!.getInt(_checkedKey);
    final lastChecked = checkedMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(checkedMs);

    ReleaseInfo? cached;
    final cachedBody = _prefs!.getString(_cacheKey);
    if (cachedBody != null) {
      try {
        cached = parseGitHubRelease(cachedBody);
      } on FormatException {
        await _prefs!.remove(_cacheKey);
      }
    }

    var initial = AppUpdateState(
      currentVersion: package.version,
      currentBuild: package.buildNumber,
      autoCheck: autoCheck,
      latest: cached,
      asset: cached == null ? null : await _bestAsset(cached),
      lastChecked: lastChecked,
    );
    final due =
        lastChecked == null ||
        DateTime.now().difference(lastChecked) >= _checkInterval;
    if (autoCheck && due) {
      initial = await _fetch(initial);
    }
    return initial;
  }

  Future<void> checkNow() async {
    final current = state.value;
    if (current == null || current.checking) return;
    state = AsyncData(current.copyWith(checking: true, clearError: true));
    state = AsyncData(await _fetch(current));
  }

  Future<void> setAutoCheck(bool enabled) async {
    final current = state.value;
    if (current == null) return;
    await _prefs?.setBool(_autoKey, enabled);
    state = AsyncData(current.copyWith(autoCheck: enabled));
    if (enabled && current.lastChecked == null) await checkNow();
  }

  Future<AppUpdateState> _fetch(AppUpdateState current) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    final attemptedAt = DateTime.now();
    await _prefs?.setInt(_checkedKey, attemptedAt.millisecondsSinceEpoch);
    try {
      final request = await client
          .getUrl(Uri.parse(suviLatestReleaseApi))
          .timeout(const Duration(seconds: 8));
      request.headers
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
        ..set(
          HttpHeaders.userAgentHeader,
          'Suvi-Share/${current.currentVersion}',
        )
        ..set('X-GitHub-Api-Version', '2022-11-28');
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw HttpException('GitHub returned HTTP ${response.statusCode}');
      }

      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(const Duration(seconds: 8))) {
        if (bytes.length + chunk.length > _maxResponseBytes) {
          throw const FormatException('Release response is too large');
        }
        bytes.add(chunk);
      }
      final body = utf8.decode(bytes.takeBytes());
      final latest = parseGitHubRelease(body);
      final now = DateTime.now();
      await _prefs?.setString(_cacheKey, body);
      await _prefs?.setInt(_checkedKey, now.millisecondsSinceEpoch);
      return current.copyWith(
        latest: latest,
        asset: await _bestAsset(latest),
        lastChecked: now,
        checking: false,
        clearAsset: true,
        clearError: true,
      );
    } catch (error) {
      return current.copyWith(
        lastChecked: attemptedAt,
        checking: false,
        error: error.runtimeType.toString(),
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<ReleaseAsset?> _bestAsset(ReleaseInfo release) async {
    var abis = const <String>[];
    if (Platform.isAndroid) {
      try {
        abis = (await DeviceInfoPlugin().androidInfo).supportedAbis;
      } catch (_) {
        // The universal APK remains a safe fallback.
      }
    }
    return selectReleaseAsset(
      release.assets,
      platform: Platform.operatingSystem,
      androidAbis: abis,
    );
  }
}

final appUpdateProvider =
    AsyncNotifierProvider<AppUpdateNotifier, AppUpdateState>(
      AppUpdateNotifier.new,
    );
