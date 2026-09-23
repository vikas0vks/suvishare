import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:suvi_core/suvi_core.dart';

import '../core/util/atomic_file.dart';
import '../platform/multicast_lock.dart';
import '../platform/notifications.dart';
import '../platform/permissions.dart';
import '../platform/transfer_service.dart';
import 'history.dart';
import 'settings.dart';

final _log = Logger('suvi.app');

// ----------------------------------------------------------------- identity

final identityProvider = FutureProvider<SuviIdentity>((ref) async {
  final dir = await getApplicationSupportDirectory();
  final file = File(p.join(dir.path, 'identity.json'));
  if (await file.exists()) {
    try {
      final parsed = SuviIdentity.tryParse(
        jsonDecode(await file.readAsString()),
      );
      if (parsed != null) return parsed;
    } catch (e) {
      _log.warning('identity.json unreadable, regenerating: $e');
    }
  }
  final id = await compute((_) => SuviIdentity.generate(), null);
  await writeAtomic(file, jsonEncode(id.toJson()), private: true);
  return id;
});

// --------------------------------------------------------------- device model

final deviceModelProvider = FutureProvider<String>((ref) async {
  try {
    final info = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final a = await info.androidInfo;
      return '${a.manufacturer} ${a.model}'.trim();
    }
    if (Platform.isWindows) {
      final w = await info.windowsInfo;
      return w.productName.isNotEmpty ? w.productName : 'Windows';
    }
    if (Platform.isLinux) {
      final l = await info.linuxInfo;
      return l.prettyName;
    }
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isIOS) return 'iOS';
  } catch (_) {}
  return Platform.operatingSystem;
});

DeviceType _deviceType() {
  if (Platform.isAndroid || Platform.isIOS) return DeviceType.mobile;
  return DeviceType.desktop;
}

// ---------------------------------------------------------------- trust store

final trustStoreProvider = FutureProvider<TrustStore>((ref) async {
  final dir = await getApplicationSupportDirectory();
  final file = File(p.join(dir.path, 'trusted.json'));
  final store = TrustStore(
    persist: (list) async {
      try {
        await writeAtomic(
          file,
          jsonEncode(list.map((d) => d.toJson()).toList()),
          private: true,
        );
      } catch (_) {}
    },
  );
  if (await file.exists()) {
    try {
      final raw = jsonDecode(await file.readAsString()) as List;
      store.load(raw.map(TrustedDevice.tryParse).whereType<TrustedDevice>());
    } catch (_) {}
  }
  ref.onDispose(store.dispose);
  return store;
});

final trustedDevicesProvider = StreamProvider<List<TrustedDevice>>((
  ref,
) async* {
  final store = await ref.watch(trustStoreProvider.future);
  yield store.all;
  yield* store.updates;
});

// -------------------------------------------------------------- pending/recv

class PendingIncoming {
  PendingIncoming(this.request) : completer = Completer<ReceiveDecision>();
  final IncomingRequest request;
  final Completer<ReceiveDecision> completer;
}

class PendingIncomingNotifier extends Notifier<PendingIncoming?> {
  @override
  PendingIncoming? build() => null;

  void set(PendingIncoming? p) => state = p;

  void resolve(ReceiveDecision d) {
    final cur = state;
    if (cur != null && !cur.completer.isCompleted) cur.completer.complete(d);
    state = null;
  }
}

final pendingIncomingProvider =
    NotifierProvider<PendingIncomingNotifier, PendingIncoming?>(
      PendingIncomingNotifier.new,
    );

class ReceiveSessionNotifier extends Notifier<ReceiveSession?> {
  @override
  ReceiveSession? build() => null;
  void set(ReceiveSession? s) => state = s;
  void clear() => state = null;
}

final receiveSessionProvider =
    NotifierProvider<ReceiveSessionNotifier, ReceiveSession?>(
      ReceiveSessionNotifier.new,
    );

class SendSessionsNotifier extends Notifier<Map<String, SendSession>> {
  @override
  Map<String, SendSession> build() => const {};
  void upsert(SendSession s) => state = {...state, s.localId: s};
  void remove(String id) => state = {...state}..remove(id);
}

final sendSessionsProvider =
    NotifierProvider<SendSessionsNotifier, Map<String, SendSession>>(
      SendSessionsNotifier.new,
    );

// ------------------------------------------------------------ receive policy

class AppReceiveDelegate implements ReceiveDelegate {
  AppReceiveDelegate(this._ref, this._client);
  final Ref _ref;
  final PeerClient _client;

  AppSettings? get _settings => _ref.read(settingsProvider).value;

  @override
  String? get requiredPin {
    final s = _settings;
    if (s == null) return null;
    return s.receiveMode == ReceiveMode.pin && s.pin.isNotEmpty ? s.pin : null;
  }

  @override
  Future<ReceiveDecision> decide(IncomingRequest request) async {
    final s = _settings;
    if (s == null || !s.receiveEnabled) return const ReceiveDecision.decline();
    final trust = _ref.read(trustStoreProvider).value;
    final fp = request.sender.fingerprint;
    if (trust != null && trust.isBlocked(fp)) {
      return const ReceiveDecision.decline();
    }

    final allIds = request.files.map((f) => f.id).toSet();
    final trustedAuto =
        (s.receiveMode == ReceiveMode.trustedAuto ||
            (trust?.autoAccepts(fp) ?? false)) &&
        (trust?.autoAccepts(fp) ?? false);
    var verifiedTrustedAuto = false;
    if (trustedAuto) {
      verifiedTrustedAuto = await _client.verifyPeerIdentity(
        request.senderIp,
        request.sender.port,
        fp,
        protocol: request.sender.protocol,
      );
      if (verifiedTrustedAuto && trust?.get(fp) != null) {
        unawaited(
          trust!.update(
            fp,
            (d) => d.copyWith(
              lastIp: request.senderIp,
              alias: request.sender.alias,
            ),
          ),
        );
      }
    }
    if (s.quickSave || verifiedTrustedAuto) {
      // Even the no-questions path must land somewhere writable: request the
      // runtime permissions (Android) and probe the folder, falling back to an
      // app-owned directory rather than failing every upload with a 500.
      final resolved = await ReceivePrerequisites.prepare(s.saveDirectory);
      return ReceiveDecision.accept(allIds, saveDirectory: resolved.dir);
    }

    final pending = PendingIncoming(request);
    _ref.read(pendingIncomingProvider.notifier).set(pending);
    try {
      return await pending.completer.future.timeout(
        const Duration(seconds: 120),
      );
    } on TimeoutException {
      _ref.read(pendingIncomingProvider.notifier).set(null);
      return const ReceiveDecision.decline();
    }
  }

  /// Tracks whether we have a foreground service held for the receive side.
  bool _fgHeld = false;

  @override
  void onSessionUpdate(ReceiveSession session) {
    _ref.read(receiveSessionProvider.notifier).set(session);
    _syncForegroundService(session);
    if (session.status == SessionStatus.finished && session.files.isNotEmpty) {
      SuviNotifications.receiveFinished(
        'Received from ${session.sender.alias}',
        '${session.finishedCount} file(s) → ${session.saveDirectory}',
      );
    } else if (session.status == SessionStatus.finished &&
        session.files.isEmpty &&
        (session.text?.isNotEmpty ?? false)) {
      // A trusted-device text arrives with no sheet at all — without this it
      // lands silently in History and looks like it never arrived.
      final t = session.text!;
      SuviNotifications.receiveFinished(
        'Message from ${session.sender.alias}',
        t.length > 120 ? '${t.substring(0, 120)}…' : t,
      );
    }
    if (session.status.isTerminal && session.status != SessionStatus.declined) {
      _ref
          .read(historyProvider.notifier)
          .add(
            HistoryEntry(
              id: session.sessionId,
              direction: HistoryDirection.received,
              peerAlias: session.sender.alias,
              peerFingerprint: session.sender.fingerprint,
              status: session.status,
              files: [
                for (final f in session.files.values)
                  HistoryFile(
                    name: f.file.fileName,
                    size: f.file.size,
                    mime: f.file.fileType,
                    path: f.savedPath,
                  ),
              ],
              timestamp: session.endedAt ?? DateTime.now(),
              text: session.text,
            ),
          );
    }
  }

  void _syncForegroundService(ReceiveSession s) {
    final active = s.status == SessionStatus.transferring;
    if (active && !_fgHeld) {
      _fgHeld = true;
      TransferForegroundService.acquire(
        title: 'Receiving from ${s.sender.alias}',
        body: '${s.files.length} file(s)',
      );
    } else if (active) {
      final pct = (s.progress * 100).clamp(0, 100).toStringAsFixed(0);
      TransferForegroundService.update(
        title: 'Receiving from ${s.sender.alias}',
        body: '$pct%',
      );
    } else if (_fgHeld && s.status.isTerminal) {
      _fgHeld = false;
      TransferForegroundService.release();
    }
  }
}

// ----------------------------------------------------------------- services

class AppServices {
  AppServices({
    required this.identity,
    required this.client,
    required this.sessions,
    required this.server,
    required this.discovery,
    required this.sender,
  });

  final SuviIdentity identity;
  final PeerClient client;
  final SessionManager sessions;
  final SuviServer server;
  final DiscoveryService discovery;
  final SendService sender;
}

class AppServicesNotifier extends AsyncNotifier<AppServices> {
  StreamSubscription<SendSession>? _sendSub;
  final MulticastLock _multicastLock = MulticastLock();
  final Map<AppServices, Future<void>> _disposals = Map.identity();
  final Map<AppServices, StreamSubscription<SendSession>> _subscriptions =
      Map.identity();
  final Map<AppServices, Set<String>> _foregroundSessions = Map.identity();

  @override
  Future<AppServices> build() async {
    final identity = await ref.watch(identityProvider.future);
    final settings = await ref.watch(settingsProvider.future);
    final model = await ref.watch(deviceModelProvider.future);
    final trust = await ref.watch(trustStoreProvider.future);

    // The port we actually bound — may differ from settings if the configured
    // port was taken (e.g. a second copy racing at startup). Advertising the
    // configured-but-unbound port would make every peer's connection fail.
    var boundPort = settings.port;

    DeviceInfo selfInfo() {
      final s = ref.read(settingsProvider).value ?? settings;
      return DeviceInfo(
        alias: s.alias,
        version: SuviConstants.protocolVersion,
        deviceModel: model,
        deviceType: _deviceType(),
        fingerprint: identity.fingerprint,
        port: boundPort,
        protocol: PeerProtocol.https,
        download: false,
        avatarColor: s.avatarColor,
      );
    }

    final client = PeerClient(selfInfo: selfInfo);
    final sessions = SessionManager(delegate: AppReceiveDelegate(ref, client));
    final discovery = DiscoveryService(
      selfInfo: selfInfo,
      client: client,
      multicastPort: SuviConstants.defaultPort,
    );
    final server = SuviServer(
      selfInfo: selfInfo,
      sessions: sessions,
      identity: identity,
      onRegister: discovery.onRegisterReceived,
    );
    final sender = SendService(client: client, selfInfo: selfInfo);

    // Start server (fallback to ephemeral port if the configured one is taken).
    // The fallback is runtime-only: the user's configured port is never
    // silently rewritten — next launch tries the configured one again.
    try {
      await server.start(port: settings.port);
    } catch (e) {
      _log.warning(
        'Port ${settings.port} unavailable ($e); falling back to random port',
      );
      await server.start(port: 0);
    }
    boundPort = server.port ?? settings.port;

    await _multicastLock.acquire();
    await discovery.start();

    await _sendSub?.cancel();
    final fgHeldFor = <String>{};
    final sendSub = sender.updates.listen((s) {
      ref.read(sendSessionsProvider.notifier).upsert(s);
      // Keep the process alive on Android while bytes are moving.
      if (s.status == SessionStatus.transferring) {
        if (fgHeldFor.add(s.localId)) {
          TransferForegroundService.acquire(
            title: 'Sending to ${s.target.alias}',
            body: '${s.files.length} file(s)',
          );
        } else {
          final pct = (s.progress * 100).clamp(0, 100).toStringAsFixed(0);
          TransferForegroundService.update(
            title: 'Sending to ${s.target.alias}',
            body: '$pct%',
          );
        }
      } else if (s.status.isTerminal && fgHeldFor.remove(s.localId)) {
        TransferForegroundService.release();
      }
      if (s.status.isTerminal) {
        ref
            .read(historyProvider.notifier)
            .add(
              HistoryEntry(
                id: s.localId,
                direction: HistoryDirection.sent,
                peerAlias: s.target.alias,
                peerFingerprint: s.target.fingerprint,
                status: s.status,
                files: [
                  for (final f in s.files.values)
                    HistoryFile(
                      name: f.dto.fileName,
                      size: f.dto.size,
                      mime: f.dto.fileType,
                      path: f.item.path,
                    ),
                ],
                timestamp: s.endedAt ?? DateTime.now(),
                text: s.text,
              ),
            );
      }
    });

    // Keep trust store referenced so it stays alive with services.
    trust.all;
    final services = AppServices(
      identity: identity,
      client: client,
      sessions: sessions,
      server: server,
      discovery: discovery,
      sender: sender,
    );
    _sendSub = sendSub;
    _subscriptions[services] = sendSub;
    _foregroundSessions[services] = fgHeldFor;
    ref.onDispose(() => unawaited(_disposeServices(services)));
    return services;
  }

  /// Re-bind everything (port change, receive toggle).
  Future<void> restart() async {
    final services = state.value;
    if (services != null) await _disposeServices(services);
    ref.invalidateSelf();
    await future;
  }

  /// Gracefully stop the server, discovery and any in-flight transfers.
  /// Called before quitting from the tray so peers stop seeing us.
  Future<void> shutdown() async {
    final services = state.value;
    if (services == null) return;
    await _disposeServices(services);
  }

  Future<void> _disposeServices(AppServices services) {
    return _disposals.putIfAbsent(services, () async {
      await services.sessions.cancelActive();
      await services.sender.dispose();
      final sub = _subscriptions.remove(services);
      await sub?.cancel();
      if (identical(_sendSub, sub)) _sendSub = null;
      final held = _foregroundSessions.remove(services) ?? const <String>{};
      for (var i = 0; i < held.length; i++) {
        await TransferForegroundService.release();
      }
      await services.discovery.dispose();
      await services.server.stop();
      await services.sessions.dispose();
      services.client.close();
      await _multicastLock.release();
    });
  }
}

final appServicesProvider =
    AsyncNotifierProvider<AppServicesNotifier, AppServices>(
      AppServicesNotifier.new,
    );

// --------------------------------------------------------------------- peers

final peersProvider = StreamProvider<List<Peer>>((ref) async* {
  final services = await ref.watch(appServicesProvider.future);
  yield services.discovery.registry.peers;
  yield* services.discovery.registry.stream;
});

final scanProgressProvider = StreamProvider<(int, int)?>((ref) async* {
  final services = await ref.watch(appServicesProvider.future);
  yield null;
  await for (final p in services.discovery.scanProgress) {
    yield p.$1 >= p.$2 ? null : p;
  }
});

// ------------------------------------------------------------------ local ip

final localIpProvider = StreamProvider<String?>((ref) async* {
  yield await NetworkUtils.primaryIp();
  yield* Stream.periodic(const Duration(seconds: 10))
      .asyncMap((_) => NetworkUtils.primaryIp())
      .distinct();
});
