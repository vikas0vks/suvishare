import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:suvi_core/suvi_core.dart';
import 'package:test/test.dart';

class _AcceptAll implements ReceiveDelegate {
  _AcceptAll(this.saveDir);
  final String saveDir;
  @override
  String? get requiredPin => null;
  @override
  Future<ReceiveDecision> decide(IncomingRequest request) async =>
      ReceiveDecision.accept(
        request.files.map((f) => f.id).toSet(),
        saveDirectory: saveDir,
      );
  @override
  void onSessionUpdate(ReceiveSession session) {}
}

void main() {
  late SuviIdentity identity;
  late Directory tmp;

  setUpAll(() => identity = SuviIdentity.generate(commonName: 'reach-test'));
  setUp(() async => tmp = await Directory.systemTemp.createTemp('suvi_reach_'));
  tearDown(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  const senderInfo = DeviceInfo(alias: 'Sender', fingerprint: 'fp-s', port: 1);

  test('a dead peer is classified unreachable, quickly', () async {
    final client = PeerClient(
      selfInfo: () => senderInfo,
      connectTimeout: const Duration(seconds: 2),
    );
    final sender = SendService(client: client, selfInfo: () => senderInfo);
    // Nothing listens on this port.
    final peer = Peer(
      info: DeviceInfo(alias: 'Ghost', fingerprint: 'fp-g', port: 59999),
      ip: '127.0.0.1',
      lastSeen: DateTime.now(),
      source: DiscoverySource.manual,
    );
    final f = File(p.join(tmp.path, 'x.txt'))..writeAsStringSync('x');
    final sw = Stopwatch()..start();
    final result = await sender.send(
      target: peer,
      items: [SendItem.file(f.path)],
    );
    sw.stop();
    expect(result.status, SessionStatus.failed);
    expect(result.failure, SendFailure.unreachable);
    expect(
      sw.elapsed.inSeconds,
      lessThan(15),
      reason: 'connect-refused must fail fast, not sit on long timeouts',
    );
    client.close();
    await sender.dispose();
  });

  test(
    'a peer that restarted (stale keep-alive) succeeds via the retry',
    () async {
      final saveDir = p.join(tmp.path, 'inbox');
      final sessions = SessionManager(delegate: _AcceptAll(saveDir));
      var port = 0;
      DeviceInfo self() =>
          DeviceInfo(alias: 'R', fingerprint: identity.fingerprint, port: port);

      // First server: talk to it once so the client pools a keep-alive socket.
      var server = SuviServer(
        selfInfo: self,
        sessions: sessions,
        identity: identity,
      );
      await server.start(port: 0, address: InternetAddress.loopbackIPv4);
      port = server.port!;
      final fixedPort = port;

      final client = PeerClient(selfInfo: () => senderInfo);
      expect(await client.register('127.0.0.1', fixedPort), isNotNull);

      // Simulate the app on the other device restarting: kill and rebind the
      // same port with a fresh server. The pooled socket is now dead.
      await server.stop();
      server = SuviServer(
        selfInfo: self,
        sessions: sessions,
        identity: identity,
      );
      await server.start(
        port: fixedPort,
        address: InternetAddress.loopbackIPv4,
      );

      final sender = SendService(client: client, selfInfo: () => senderInfo);
      final peer = Peer(
        info: DeviceInfo(
          alias: 'R',
          fingerprint: identity.fingerprint,
          port: fixedPort,
        ),
        ip: '127.0.0.1',
        lastSeen: DateTime.now(),
        source: DiscoverySource.manual,
      );
      final f = File(p.join(tmp.path, 'y.txt'))
        ..writeAsStringSync('after restart');
      final result = await sender.send(
        target: peer,
        items: [SendItem.file(f.path)],
      );

      expect(
        result.status,
        SessionStatus.finished,
        reason: result.errorMessage ?? '',
      );
      expect(File(p.join(saveDir, 'y.txt')).existsSync(), isTrue);

      client.close();
      await sender.dispose();
      await server.stop();
      await sessions.dispose();
    },
  );
}
