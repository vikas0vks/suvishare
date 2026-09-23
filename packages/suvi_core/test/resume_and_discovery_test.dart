import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:suvi_core/suvi_core.dart';
import 'package:test/test.dart';

class _AcceptAll implements ReceiveDelegate {
  _AcceptAll(this.saveDir);
  final String saveDir;
  final List<ReceiveSession> snapshots = [];

  @override
  String? get requiredPin => null;

  @override
  Future<ReceiveDecision> decide(IncomingRequest request) async =>
      ReceiveDecision.accept(
        request.files.map((f) => f.id).toSet(),
        saveDirectory: saveDir,
      );

  @override
  void onSessionUpdate(ReceiveSession session) => snapshots.add(session);
}

/// Emits [prefix] bytes then throws, simulating a dropped connection.
Stream<List<int>> _truncated(List<int> data, int prefix) async* {
  yield data.sublist(0, prefix);
  throw const SocketException('connection reset');
}

void main() {
  late Directory tmp;

  setUp(
    () async => tmp = await Directory.systemTemp.createTemp('suvi_resume_'),
  );
  tearDown(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  const sender = DeviceInfo(alias: 'Sender', fingerprint: 'fp-sender', port: 1);

  group('SessionManager resume', () {
    test('reports bytes on disk and accepts an offset continuation', () async {
      final saveDir = p.join(tmp.path, 'inbox');
      final delegate = _AcceptAll(saveDir);
      final sessions = SessionManager(delegate: delegate);
      final data = List<int>.generate(200000, (i) => i & 0xff);

      final prepared = await sessions.prepareUpload(
        PrepareUploadRequest(
          info: sender,
          files: {
            'f1': FileDto(
              id: 'f1',
              fileName: 'big.bin',
              size: data.length,
              fileType: 'application/octet-stream',
            ),
          },
        ),
        '10.0.0.5',
      );
      expect(prepared, isA<PrepareAccepted>());
      final accepted = prepared as PrepareAccepted;
      final token = accepted.fileTokens['f1']!;

      // First attempt dies halfway through.
      final failed = await sessions.upload(
        sessionId: accepted.sessionId,
        fileId: 'f1',
        token: token,
        senderIp: '10.0.0.5',
        body: _truncated(data, 80000),
        contentLength: data.length,
      );
      expect(failed.ok, isFalse);
      expect(failed.status, 500);

      // Receiver reports what it kept.
      final status = await sessions.uploadStatus(
        accepted.sessionId,
        'f1',
        token,
        '10.0.0.5',
      );
      expect(status.ok, isTrue);
      final onDisk = int.parse(status.message);
      expect(onDisk, 80000);

      // Resume from that offset.
      final resumed = await sessions.upload(
        sessionId: accepted.sessionId,
        fileId: 'f1',
        token: token,
        senderIp: '10.0.0.5',
        body: Stream.value(data.sublist(onDisk)),
        offset: onDisk,
        contentLength: data.length - onDisk,
      );
      expect(resumed.ok, isTrue, reason: resumed.message);

      final saved = File(p.join(saveDir, 'big.bin'));
      expect(await saved.exists(), isTrue);
      expect(await saved.length(), data.length);
      expect(await saved.readAsBytes(), data);
      expect(
        Directory(saveDir)
            .listSync()
            .where((e) => e.path.endsWith('.suvipart')),
        isEmpty,
      );
      await sessions.dispose();
    });

    test('verifies the full checksum after a resumed upload', () async {
      final saveDir = p.join(tmp.path, 'checksum-inbox');
      final sessions = SessionManager(delegate: _AcceptAll(saveDir));
      final data = List<int>.generate(120000, (i) => (i * 17) & 0xff);
      final expected = sha256.convert(data).toString();
      final prepared = await sessions.prepareUpload(
        PrepareUploadRequest(
          info: sender,
          files: {
            'hash': FileDto(
              id: 'hash',
              fileName: 'hashed.bin',
              size: data.length,
              fileType: 'application/octet-stream',
              sha256: expected,
            ),
          },
        ),
        '10.0.0.5',
      ) as PrepareAccepted;
      final token = prepared.fileTokens['hash']!;

      await sessions.upload(
        sessionId: prepared.sessionId,
        fileId: 'hash',
        token: token,
        senderIp: '10.0.0.5',
        body: _truncated(data, 40000),
        contentLength: data.length,
      );
      final resumed = await sessions.upload(
        sessionId: prepared.sessionId,
        fileId: 'hash',
        token: token,
        senderIp: '10.0.0.5',
        body: Stream.value([
          ...data.sublist(40000, data.length - 1),
          data.last ^ 0xff,
        ]),
        offset: 40000,
        contentLength: data.length - 40000,
      );
      expect(resumed.status, 422);
      expect(File(p.join(saveDir, 'hashed.bin')).existsSync(), isFalse);
      await sessions.dispose();
    });

    test('rejects an offset beyond what was received', () async {
      final sessions = SessionManager(delegate: _AcceptAll(tmp.path));
      final prepared = await sessions.prepareUpload(
        PrepareUploadRequest(
          info: sender,
          files: {
            'a': const FileDto(
              id: 'a',
              fileName: 'a.bin',
              size: 100,
              fileType: 'x',
            ),
          },
        ),
        '10.0.0.5',
      ) as PrepareAccepted;
      final out = await sessions.upload(
        sessionId: prepared.sessionId,
        fileId: 'a',
        token: prepared.fileTokens['a']!,
        senderIp: '10.0.0.5',
        body: Stream.value([1]),
        offset: 50,
        contentLength: 50,
      );
      expect(out.status, 416);
      await sessions.dispose();
    });

    test(
      'rejects a Content-Length that disagrees with the declared size',
      () async {
        final sessions = SessionManager(delegate: _AcceptAll(tmp.path));
        final prepared = await sessions.prepareUpload(
          PrepareUploadRequest(
            info: sender,
            files: {
              'a': const FileDto(
                id: 'a',
                fileName: 'a.bin',
                size: 100,
                fileType: 'x',
              ),
            },
          ),
          '10.0.0.5',
        ) as PrepareAccepted;
        final out = await sessions.upload(
          sessionId: prepared.sessionId,
          fileId: 'a',
          token: prepared.fileTokens['a']!,
          senderIp: '10.0.0.5',
          body: Stream.value(List.filled(90, 0)),
          contentLength: 90,
        );
        expect(out.status, 400);
        await sessions.dispose();
      },
    );

    test('a second sender gets 409 while a session is active', () async {
      final sessions = SessionManager(delegate: _AcceptAll(tmp.path));
      final first = await sessions.prepareUpload(
        PrepareUploadRequest(
          info: sender,
          files: {
            'a': const FileDto(
              id: 'a',
              fileName: 'a.bin',
              size: 10,
              fileType: 'x',
            ),
          },
        ),
        '10.0.0.5',
      );
      expect(first, isA<PrepareAccepted>());
      final second = await sessions.prepareUpload(
        PrepareUploadRequest(
          info: const DeviceInfo(
            alias: 'Other',
            fingerprint: 'fp-other',
            port: 2,
          ),
          files: {
            'b': const FileDto(
              id: 'b',
              fileName: 'b.bin',
              size: 10,
              fileType: 'x',
            ),
          },
        ),
        '10.0.0.9',
      );
      expect(second, isA<PrepareError>());
      expect((second as PrepareError).status, 409);
      await sessions.dispose();
    });

    test('rate limits repeated prepare-upload from one IP', () async {
      final sessions = SessionManager(delegate: _AcceptAll(tmp.path));
      PrepareOutcome? last;
      for (var i = 0; i < SuviConstants.prepareRateLimitPerMinute + 2; i++) {
        last = await sessions.prepareUpload(
          PrepareUploadRequest(info: sender, files: const {}, text: 'hi'),
          '10.0.0.7',
        );
        await sessions.cancelActive();
      }
      expect(last, isA<PrepareError>());
      expect((last! as PrepareError).status, 429);
      await sessions.dispose();
    });
  });

  group('SendItem.stream', () {
    test('streams without a path and honours a resume offset', () async {
      final data = List<int>.generate(1000, (i) => i & 0xff);
      final item = SendItem.stream(
        name: 'from-content-uri.bin',
        opener: () =>
            Stream.fromIterable([data.sublist(0, 400), data.sublist(400)]),
        sizer: () async => data.length,
      );
      expect(await item.resolveSize(), 1000);
      expect(item.path, isNull);

      final all = <int>[];
      await for (final c in item.open(0)) {
        all.addAll(c);
      }
      expect(all, data);

      final tail = <int>[];
      await for (final c in item.open(600)) {
        tail.addAll(c);
      }
      expect(tail, data.sublist(600));
    });
  });

  group('PeerRegistry', () {
    test('upserts, dedupes by fingerprint and expires stale peers', () async {
      final registry = PeerRegistry(ttl: const Duration(milliseconds: 1));
      const info = DeviceInfo(alias: 'A', fingerprint: 'fp-a', port: 53317);

      expect(
        registry.upsert(info, '192.168.1.5', DiscoverySource.multicast),
        isTrue,
      );
      expect(registry.peers.length, 1);
      // Same data again → no change reported.
      expect(
        registry.upsert(info, '192.168.1.5', DiscoverySource.multicast),
        isFalse,
      );
      // Changed alias → change reported, still one entry.
      expect(
        registry.upsert(
          info.copyWith(alias: 'A2'),
          '192.168.1.5',
          DiscoverySource.register,
        ),
        isTrue,
      );
      expect(registry.peers.length, 1);
      expect(registry.peers.single.alias, 'A2');
      // Stronger source wins.
      expect(registry.peers.single.source, DiscoverySource.register);

      registry.remove('fp-a');
      expect(registry.peers, isEmpty);
      await registry.dispose();
    });

    test('ignores browser clients that cannot be connected back to', () async {
      final registry = PeerRegistry();
      // A browser advertises port 0 and deviceType web: not a send target.
      expect(
        registry.upsert(
          const DeviceInfo(
            alias: 'Browser',
            fingerprint: 'web-1',
            port: 0,
            deviceType: DeviceType.web,
          ),
          '192.168.1.30',
          DiscoverySource.register,
        ),
        isFalse,
      );
      expect(registry.peers, isEmpty);
      await registry.dispose();
    });

    test('manual peers survive expiry sweeps', () async {
      final registry = PeerRegistry(ttl: Duration.zero);
      registry.upsert(
        const DeviceInfo(alias: 'M', fingerprint: 'fp-m', port: 1),
        '192.168.1.9',
        DiscoverySource.manual,
      );
      registry.start();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(registry.peers.length, 1);
      await registry.dispose();
    });
  });

  group('NetworkUtils', () {
    test('classifies private IPv4 ranges', () {
      bool priv(String ip) => NetworkUtils.isPrivateIPv4(InternetAddress(ip));
      expect(priv('192.168.1.10'), isTrue);
      expect(priv('10.1.2.3'), isTrue);
      expect(priv('172.16.0.1'), isTrue);
      expect(priv('172.31.255.254'), isTrue);
      expect(priv('169.254.1.1'), isTrue); // link-local
      expect(priv('100.64.0.1'), isTrue); // CGNAT / phone hotspot
      expect(priv('8.8.8.8'), isFalse);
      expect(priv('172.32.0.1'), isFalse);
    });

    test('flags virtual adapters so VPNs are not preferred', () {
      expect(NetworkUtils.looksVirtual('vEthernet (Default Switch)'), isTrue);
      expect(NetworkUtils.looksVirtual('docker0'), isTrue);
      expect(NetworkUtils.looksVirtual('Tailscale'), isTrue);
      expect(NetworkUtils.looksVirtual('Wi-Fi'), isFalse);
      expect(NetworkUtils.looksVirtual('Ethernet'), isFalse);
    });

    test('enumerates /24 hosts and skips itself', () {
      final addr = LocalAddress(
        interfaceName: 'Wi-Fi',
        address: InternetAddress('192.168.1.20'),
      );
      final hosts = addr.subnetHosts().toList();
      expect(hosts.length, 253);
      expect(hosts.contains('192.168.1.20'), isFalse);
      expect(hosts.first, '192.168.1.1');
      expect(hosts.last, '192.168.1.254');
    });
  });

  group('TrustStore', () {
    test('tracks trust, auto-accept, favorites and blocking', () async {
      final saved = <List<TrustedDevice>>[];
      final store = TrustStore(persist: (l) async => saved.add(l));

      expect(store.isTrusted('fp'), isFalse);
      expect(store.levelFor('fp'), TrustLevel.unknown);

      await store.trust('fp', 'Office PC', ip: '192.168.1.4');
      expect(store.isTrusted('fp'), isTrue);
      expect(store.autoAccepts('fp'), isFalse);
      expect(store.levelFor('fp'), TrustLevel.trusted);

      await store.update(
        'fp',
        (d) => d.copyWith(autoAccept: true, favorite: true),
      );
      expect(store.autoAccepts('fp'), isTrue);
      expect(store.get('fp')!.favorite, isTrue);

      // A different certificate on the wire must demote the device.
      expect(
        store.levelFor('fp', observedFp: 'something-else'),
        TrustLevel.mismatch,
      );

      await store.block('fp', 'Office PC');
      expect(store.isBlocked('fp'), isTrue);
      expect(store.autoAccepts('fp'), isFalse);
      expect(store.levelFor('fp'), TrustLevel.blocked);

      expect(saved, isNotEmpty);
      await store.dispose();
    });
  });

  group('AliasGenerator', () {
    test('produces varied two-word aliases', () {
      final seen = {for (var i = 0; i < 50; i++) AliasGenerator.generate()};
      expect(seen.length, greaterThan(10));
      for (final a in seen) {
        expect(a.split(' ').length, 2);
      }
    });
  });
}
