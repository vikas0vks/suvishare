@Tags(['perf'])
library;

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
  Future<ReceiveDecision> decide(IncomingRequest r) async =>
      ReceiveDecision.accept(
        r.files.map((f) => f.id).toSet(),
        saveDirectory: saveDir,
      );
  @override
  void onSessionUpdate(ReceiveSession s) {}
}

void main() {
  test('engine throughput over the real loopback TCP stack', () async {
    final identity = SuviIdentity.generate(commonName: 'perf');
    final tmp = await Directory.systemTemp.createTemp('suvi_perf_');
    final saveDir = p.join(tmp.path, 'inbox');
    final sessions = SessionManager(delegate: _AcceptAll(saveDir));
    var port = 0;
    final server = SuviServer(
      selfInfo: () =>
          DeviceInfo(alias: 'R', fingerprint: identity.fingerprint, port: port),
      sessions: sessions,
      identity: identity,
    );
    await server.start(port: 0, address: InternetAddress.loopbackIPv4);
    port = server.port!;

    const senderInfo = DeviceInfo(alias: 'S', fingerprint: 'sfp', port: 1);
    final client = PeerClient(selfInfo: () => senderInfo);
    final sender = SendService(client: client, selfInfo: () => senderInfo);
    final peer = Peer(
      info: DeviceInfo(
        alias: 'R',
        fingerprint: identity.fingerprint,
        port: port,
      ),
      ip: '127.0.0.1',
      lastSeen: DateTime.now(),
      source: DiscoverySource.manual,
    );

    // 200 MB, no sha256 (isolate pure transfer, not hashing).
    const sizeMb = 200;
    final big = File(p.join(tmp.path, 'big.bin'));
    final raf = await big.open(mode: FileMode.write);
    final block = List<int>.filled(1024 * 1024, 0x5A);
    for (var i = 0; i < sizeMb; i++) {
      await raf.writeFrom(block);
    }
    await raf.close();

    final sw = Stopwatch()..start();
    final result = await sender.send(
      target: peer,
      items: [SendItem.file(big.path)],
    );
    sw.stop();
    expect(result.status, SessionStatus.finished);

    final mbps = sizeMb / sw.elapsed.inMilliseconds * 1000;
    // ignore: avoid_print
    print(
      'THROUGHPUT: $sizeMb MB in ${sw.elapsed.inMilliseconds} ms '
      '= ${mbps.toStringAsFixed(1)} MB/s',
    );

    client.close();
    await server.stop();
    await sessions.dispose();
    await tmp.delete(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
