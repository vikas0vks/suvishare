import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:suvi_core/suvi_core.dart';
import 'package:test/test.dart';

class _AcceptAll implements ReceiveDelegate {
  _AcceptAll(this.saveDir, {this.pin});
  final bool Function(FileDto)? acceptFilter = null;
  final String saveDir;
  final String? pin;
  final List<ReceiveSession> snapshots = [];
  IncomingRequest? lastRequest;

  @override
  String? get requiredPin => pin;

  @override
  Future<ReceiveDecision> decide(IncomingRequest request) async {
    lastRequest = request;
    final ids = request.files
        .where((f) => acceptFilter?.call(f) ?? true)
        .map((f) => f.id)
        .toSet();
    return ReceiveDecision.accept(ids, saveDirectory: saveDir);
  }

  @override
  void onSessionUpdate(ReceiveSession session) => snapshots.add(session);
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

void main() {
  late SuviIdentity identity;
  late Directory tmp;

  setUpAll(() async {
    identity = await Future(() => SuviIdentity.generate(commonName: 'test'));
    expect(identity.fingerprint.length, 64);
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('suvi_test_');
  });

  tearDown(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  DeviceInfo receiverInfo(int port) => DeviceInfo(
    alias: 'Receiver',
    fingerprint: identity.fingerprint,
    port: port,
    deviceType: DeviceType.desktop,
  );
  const senderInfo = DeviceInfo(
    alias: 'Sender',
    fingerprint: 'sender-fp',
    port: 1,
    deviceType: DeviceType.mobile,
  );

  test('identity: PEM fingerprint is stable and matches DER', () {
    final fp2 = SuviIdentity.fingerprintOfPem(identity.certificatePem);
    expect(fp2, identity.fingerprint);
    expect(identity.shortFingerprint.length, 14); // "XXXX XXXX XXXX"
  });

  test('full HTTPS transfer over loopback with checksum & progress', () async {
    final saveDir = p.join(tmp.path, 'inbox');
    final delegate = _AcceptAll(saveDir);
    final sessions = SessionManager(delegate: delegate);
    var port = 0;
    final server = SuviServer(
      selfInfo: () => receiverInfo(port),
      sessions: sessions,
      identity: identity,
    );
    await server.start(port: 0, address: InternetAddress.loopbackIPv4);
    port = server.port!;

    String? seenFp;
    final client = PeerClient(
      selfInfo: () => senderInfo,
      certificatePolicy: (host, fp) {
        seenFp = fp;
        return true;
      },
    );

    // Prepare a 3 MB file + a small text file with path-traversal name.
    final big = File(p.join(tmp.path, 'big.bin'));
    final bytes = List<int>.generate(3 * 1024 * 1024, (i) => (i * 31) & 0xff);
    await big.writeAsBytes(bytes);
    final small = File(p.join(tmp.path, 'small.txt'));
    await small.writeAsString('hello suvi');

    final sendService = SendService(client: client, selfInfo: () => senderInfo);
    final peer = Peer(
      info: receiverInfo(port),
      ip: '127.0.0.1',
      lastSeen: DateTime.now(),
      source: DiscoverySource.manual,
    );
    final progress = <double>[];
    final sub = sendService.updates.listen((s) => progress.add(s.progress));

    final result = await sendService.send(
      target: peer,
      items: [
        SendItem.file(big.path),
        SendItem.file(small.path, name: '../../evil.txt'),
      ],
      text: 'clipboard text',
    );
    await sub.cancel();

    expect(result.status, SessionStatus.finished);
    expect(result.finishedCount, 2);
    expect(seenFp, identity.fingerprint, reason: 'pinning sees the real cert');
    expect(progress.last, 1.0);

    // Receiver side.
    expect(delegate.lastRequest!.text, 'clipboard text');
    final last = delegate.snapshots.last;
    expect(last.status, SessionStatus.finished);
    final saved = last.files.values.map((f) => f.savedPath!).toList();
    expect(saved.length, 2);
    for (final path in saved) {
      expect(FilenameSanitizer.isInside(saveDir, path), isTrue);
    }
    final evil = saved.firstWhere((s) => s.endsWith('evil.txt'));
    expect(p.basename(evil), 'evil.txt');
    expect(await File(evil).readAsString(), 'hello suvi');
    final bigSaved = saved.firstWhere((s) => s.endsWith('big.bin'));
    expect(await File(bigSaved).length(), bytes.length);
    expect(
      (await File(bigSaved).readAsBytes()).sublist(0, 64),
      bytes.sublist(0, 64),
    );
    // No leftover .suvipart files.
    expect(
      Directory(saveDir).listSync().where((e) => e.path.endsWith('.suvipart')),
      isEmpty,
    );

    // Collision → "(1)" suffix.
    final result2 = await sendService.send(
      target: peer,
      items: [SendItem.file(small.path)],
    );
    expect(result2.status, SessionStatus.finished);
    expect(File(p.join(saveDir, 'small.txt')).existsSync(), isTrue);
    final after = Directory(saveDir)
        .listSync()
        .map((e) => p.basename(e.path))
        .toSet();
    expect(after.contains('small.txt'), isTrue);

    client.close();
    await server.stop();
    await sessions.dispose();
  });

  test('decline → 403 → SessionStatus.declined', () async {
    final sessions = SessionManager(delegate: _DeclineAll());
    var port = 0;
    final server = SuviServer(
      selfInfo: () => receiverInfo(port),
      sessions: sessions,
      identity: identity,
    );
    await server.start(port: 0, address: InternetAddress.loopbackIPv4);
    port = server.port!;
    final client = PeerClient(selfInfo: () => senderInfo);
    final sendService = SendService(client: client, selfInfo: () => senderInfo);
    final peer = Peer(
      info: receiverInfo(port),
      ip: '127.0.0.1',
      lastSeen: DateTime.now(),
      source: DiscoverySource.manual,
    );
    final f = File(p.join(tmp.path, 'x.txt'))..writeAsStringSync('x');
    final r = await sendService.send(
      target: peer,
      items: [SendItem.file(f.path)],
    );
    expect(r.status, SessionStatus.declined);
    client.close();
    await server.stop();
  });

  test('PIN required → 401, correct PIN → accepted', () async {
    final sessions = SessionManager(
      delegate: _AcceptAll(tmp.path, pin: '4321'),
    );
    var port = 0;
    final server = SuviServer(
      selfInfo: () => receiverInfo(port),
      sessions: sessions,
      identity: identity,
    );
    await server.start(port: 0, address: InternetAddress.loopbackIPv4);
    port = server.port!;
    final client = PeerClient(selfInfo: () => senderInfo);
    final req = PrepareUploadRequest(
      info: senderInfo,
      files: {
        'a': const FileDto(
          id: 'a',
          fileName: 'a.txt',
          size: 1,
          fileType: 'text/plain',
        ),
      },
    );
    await expectLater(
      client.prepareUpload('127.0.0.1', port, req),
      throwsA(
        isA<PeerApiException>().having((e) => e.statusCode, 'status', 401),
      ),
    );
    final ok = await client.prepareUpload('127.0.0.1', port, req, pin: '4321');
    expect(ok.files.containsKey('a'), isTrue);
    await client.cancel('127.0.0.1', port, sessionId: ok.sessionId);
    client.close();
    await server.stop();
  });

  test('register + info work and wrong token is 403', () async {
    final sessions = SessionManager(delegate: _AcceptAll(tmp.path));
    var port = 0;
    DeviceInfo? registered;
    final server = SuviServer(
      selfInfo: () => receiverInfo(port),
      sessions: sessions,
      identity: identity,
      onRegister: (info, ip) => registered = info,
    );
    await server.start(port: 0, address: InternetAddress.loopbackIPv4);
    port = server.port!;
    final client = PeerClient(selfInfo: () => senderInfo);

    final theirs = await client.register('127.0.0.1', port);
    expect(theirs?.alias, 'Receiver');
    expect(registered?.alias, 'Sender');
    final info = await client.info('127.0.0.1', port);
    expect(info?.fingerprint, identity.fingerprint);

    final req = PrepareUploadRequest(
      info: senderInfo,
      files: {
        'a': const FileDto(
          id: 'a',
          fileName: 'a.txt',
          size: 3,
          fileType: 'text/plain',
        ),
      },
    );
    final prep = await client.prepareUpload('127.0.0.1', port, req);
    await expectLater(
      client.upload(
        '127.0.0.1',
        port,
        sessionId: prep.sessionId,
        fileId: 'a',
        token: 'wrong',
        body: Stream.value([1, 2, 3]),
        size: 3,
      ),
      throwsA(
        isA<PeerApiException>().having((e) => e.statusCode, 'status', 403),
      ),
    );
    await client.cancel('127.0.0.1', port, sessionId: prep.sessionId);
    client.close();
    await server.stop();
  });
}
