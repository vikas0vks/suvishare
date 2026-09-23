import 'dart:io';

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

void main() {
  late SuviIdentity identity;
  late Directory tmp;

  setUpAll(() => identity = SuviIdentity.generate(commonName: 'resume-e2e'));
  setUp(
    () async => tmp = await Directory.systemTemp.createTemp('suvi_resume_e2e_'),
  );
  tearDown(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  const senderInfo = DeviceInfo(
    alias: 'Sender',
    fingerprint: 'fp-sender',
    port: 1,
  );

  test('a dropped connection resumes and the file arrives intact', () async {
    final saveDir = p.join(tmp.path, 'inbox');
    final delegate = _AcceptAll(saveDir);
    final sessions = SessionManager(delegate: delegate);
    var port = 0;
    final server = SuviServer(
      selfInfo: () => DeviceInfo(
        alias: 'Receiver',
        fingerprint: identity.fingerprint,
        port: port,
      ),
      sessions: sessions,
      identity: identity,
    );
    await server.start(port: 0, address: InternetAddress.loopbackIPv4);
    port = server.port!;

    final client = PeerClient(selfInfo: () => senderInfo);
    final sender = SendService(
      client: client,
      selfInfo: () => senderInfo,
      resumeBackoff: const Duration(milliseconds: 10),
    );
    final peer = Peer(
      info: DeviceInfo(
        alias: 'Receiver',
        fingerprint: identity.fingerprint,
        port: port,
      ),
      ip: '127.0.0.1',
      lastSeen: DateTime.now(),
      source: DiscoverySource.manual,
    );

    // 900 KB in 100 chunks; the first attempt dies after 30 of them.
    const chunkSize = 9000;
    const chunks = 100;
    final data = List<int>.generate(chunkSize * chunks, (i) => (i * 7) & 0xff);
    var attempt = 0;

    Stream<List<int>> opener() async* {
      final thisAttempt = attempt++;
      var sent = 0;
      while (sent < data.length) {
        final end = (sent + chunkSize).clamp(0, data.length);
        yield data.sublist(sent, end);
        sent = end;
        if (thisAttempt == 0 && sent >= chunkSize * 30) {
          // Simulate the Wi-Fi dropping mid-upload.
          throw const SocketException('connection reset by peer');
        }
      }
    }

    final result = await sender.send(
      target: peer,
      items: [
        SendItem.stream(
          name: 'flaky.bin',
          opener: opener,
          size: data.length,
          mime: 'application/octet-stream',
        ),
      ],
    );

    expect(
      attempt,
      greaterThanOrEqualTo(2),
      reason: 'the stream was reopened to resume',
    );
    expect(
      result.status,
      SessionStatus.finished,
      reason: result.errorMessage ?? '',
    );
    expect(result.finishedCount, 1);

    final saved = File(p.join(saveDir, 'flaky.bin'));
    expect(await saved.exists(), isTrue);
    expect(await saved.length(), data.length);
    expect(
      await saved.readAsBytes(),
      data,
      reason: 'resumed bytes must line up exactly',
    );
    expect(
      Directory(saveDir).listSync().where((e) => e.path.endsWith('.suvipart')),
      isEmpty,
    );

    client.close();
    await server.stop();
    await sessions.dispose();
  });

  test(
    'gives up after the retry budget and reports the file as failed',
    () async {
      final saveDir = p.join(tmp.path, 'inbox');
      final sessions = SessionManager(delegate: _AcceptAll(saveDir));
      var port = 0;
      final server = SuviServer(
        selfInfo: () => DeviceInfo(
          alias: 'Receiver',
          fingerprint: identity.fingerprint,
          port: port,
        ),
        sessions: sessions,
        identity: identity,
      );
      await server.start(port: 0, address: InternetAddress.loopbackIPv4);
      port = server.port!;

      final client = PeerClient(selfInfo: () => senderInfo);
      final sender = SendService(
        client: client,
        selfInfo: () => senderInfo,
        maxResumeAttempts: 2,
        resumeBackoff: const Duration(milliseconds: 5),
      );
      final peer = Peer(
        info: DeviceInfo(
          alias: 'Receiver',
          fingerprint: identity.fingerprint,
          port: port,
        ),
        ip: '127.0.0.1',
        lastSeen: DateTime.now(),
        source: DiscoverySource.manual,
      );

      var attempts = 0;
      Stream<List<int>> alwaysBroken() async* {
        attempts++;
        yield List<int>.filled(1000, 1);
        throw const SocketException('always broken');
      }

      final result = await sender.send(
        target: peer,
        items: [
          SendItem.stream(
            name: 'doomed.bin',
            opener: alwaysBroken,
            size: 50000,
          ),
        ],
      );

      expect(
        attempts,
        3,
        reason: 'initial attempt plus maxResumeAttempts retries',
      );
      expect(result.status, SessionStatus.finishedWithErrors);
      expect(result.failedCount, 1);
      expect(File(p.join(saveDir, 'doomed.bin')).existsSync(), isFalse);

      client.close();
      await server.stop();
      await sessions.dispose();
    },
  );

  test('a declined transfer is not retried', () async {
    final sessions = SessionManager(delegate: _DeclineAll());
    var port = 0;
    final server = SuviServer(
      selfInfo: () => DeviceInfo(
        alias: 'Receiver',
        fingerprint: identity.fingerprint,
        port: port,
      ),
      sessions: sessions,
      identity: identity,
    );
    await server.start(port: 0, address: InternetAddress.loopbackIPv4);
    port = server.port!;

    final client = PeerClient(selfInfo: () => senderInfo);
    final sender = SendService(client: client, selfInfo: () => senderInfo);
    final peer = Peer(
      info: DeviceInfo(
        alias: 'Receiver',
        fingerprint: identity.fingerprint,
        port: port,
      ),
      ip: '127.0.0.1',
      lastSeen: DateTime.now(),
      source: DiscoverySource.manual,
    );

    var opens = 0;
    final result = await sender.send(
      target: peer,
      items: [
        SendItem.stream(
          name: 'x.bin',
          opener: () {
            opens++;
            return Stream.value(List<int>.filled(10, 0));
          },
          size: 10,
        ),
      ],
    );

    expect(result.status, SessionStatus.declined);
    expect(
      opens,
      0,
      reason: 'a 403 at prepare time must not open the file at all',
    );

    client.close();
    await server.stop();
    await sessions.dispose();
  });
}

class _DeclineAll implements ReceiveDelegate {
  @override
  String? get requiredPin => null;
  @override
  Future<ReceiveDecision> decide(IncomingRequest request) async =>
      const ReceiveDecision.decline();
  @override
  void onSessionUpdate(ReceiveSession session) {}
}
