import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:suvi_core/suvi_core.dart';

import 'app_services.dart';
import 'settings.dart';

final _log = Logger('suvi.webshare');

/// What the UI needs to render the Web Share panel.
@immutable
class WebShareState {
  const WebShareState({
    required this.enabled,
    this.port,
    this.url,
    this.pin,
    this.offeredFiles = 0,
    this.error,
  });

  final bool enabled;
  final int? port;
  final String? url;
  final String? pin;
  final int offeredFiles;
  final String? error;

  bool get isRunning => enabled && url != null;
}

/// Owns the plain-HTTP listener that serves the browser page.
///
/// It is a *separate* server from the HTTPS API listener: browsers reject
/// self-signed certificates, so this one has to be cleartext. It only runs
/// while the user switches Web Share on, and it is PIN-gated by default.
class WebShareNotifier extends AsyncNotifier<WebShareState> {
  SuviServer? _server;
  WebShareHandler? _handler;

  @override
  Future<WebShareState> build() async {
    ref.onDispose(() {
      _server?.stop();
      _server = null;
      _handler = null;
    });
    return const WebShareState(enabled: false);
  }

  WebShareHandler? get handler => _handler;

  Future<void> enable({String? pin}) async {
    if (_server != null) return;
    final services = await ref.read(appServicesProvider.future);
    final settings = await ref.read(settingsProvider.future);
    final ip = await NetworkUtils.primaryIp();
    if (ip == null) {
      state = const AsyncData(
        WebShareState(enabled: false, error: 'not-connected'),
      );
      return;
    }

    // Base on the port the API server actually bound, not the configured one —
    // they differ when the configured port was busy at startup.
    final apiPort = services.server.port ?? settings.port;
    final effectivePin = (pin != null && pin.isNotEmpty)
        ? pin
        : (settings.receiveMode == ReceiveMode.pin && settings.pin.isNotEmpty)
        ? settings.pin
        : (Random.secure().nextInt(900000) + 100000).toString();
    final handler = WebShareHandler(
      loadAsset: _loadAsset,
      deviceAlias: () =>
          ref.read(settingsProvider).value?.alias ?? 'Suvi Share',
      sessionPin: effectivePin,
    );
    final server = SuviServer(
      selfInfo: () => DeviceInfo(
        alias: settings.alias,
        deviceModel: 'Web Share',
        fingerprint: services.identity.fingerprint,
        port: apiPort + SuviConstants.webSharePortOffset,
        protocol: PeerProtocol.http,
        download: true,
        avatarColor: settings.avatarColor,
      ),
      sessions: services.sessions,
      identity: services.identity,
      webHandler: handler.call,
      requiredUploadPin: () => handler.sessionPin,
    );

    final wanted = apiPort + SuviConstants.webSharePortOffset;
    try {
      await server.start(port: wanted, https: false);
    } catch (e) {
      _log.warning('web share port $wanted busy ($e); using a random port');
      await server.start(port: 0, https: false);
    }

    _server = server;
    _handler = handler;
    state = AsyncData(
      WebShareState(
        enabled: true,
        port: server.port,
        url: 'http://$ip:${server.port}',
        pin: effectivePin,
      ),
    );
    _log.info('web share on ${state.value?.url}');
  }

  Future<void> disable() async {
    _handler?.revoke();
    await _server?.stop();
    _server = null;
    _handler = null;
    state = const AsyncData(WebShareState(enabled: false));
  }

  Future<void> toggle({String? pin}) async {
    if (state.value?.isRunning ?? false) {
      await disable();
    } else {
      await enable(pin: pin);
    }
  }

  /// Publishes files for browsers to download.
  Future<void> offer(List<SendItem> items, {String? pin}) async {
    if (_handler == null) await enable(pin: pin);
    final h = _handler;
    if (h == null) return;
    await h.publish(items, pin: pin ?? state.value?.pin);
    final cur = state.value;
    if (cur != null) {
      state = AsyncData(
        WebShareState(
          enabled: cur.enabled,
          port: cur.port,
          url: cur.url,
          pin: pin ?? cur.pin,
          offeredFiles: items.length,
        ),
      );
    }
  }

  /// Stops offering files but keeps the page reachable for uploads.
  void revokeOffer() {
    _handler?.revoke();
    final cur = state.value;
    if (cur != null) {
      state = AsyncData(
        WebShareState(
          enabled: cur.enabled,
          port: cur.port,
          url: cur.url,
          pin: cur.pin,
        ),
      );
    }
  }

  static Future<List<int>?> _loadAsset(String path) async {
    try {
      final data = await rootBundle.load(path);
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } catch (_) {
      return null;
    }
  }
}

final webShareProvider = AsyncNotifierProvider<WebShareNotifier, WebShareState>(
  WebShareNotifier.new,
);
