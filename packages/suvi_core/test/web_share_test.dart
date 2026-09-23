import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:suvi_core/suvi_core.dart';
import 'package:test/test.dart';

class _AcceptAll implements ReceiveDelegate {
  _AcceptAll(this.saveDir);
  final String saveDir;
  IncomingRequest? last;
  final List<ReceiveSession> snapshots = [];

  @override
  String? get requiredPin => null;

  @override
  Future<ReceiveDecision> decide(IncomingRequest request) async {
    last = request;
    return ReceiveDecision.accept(
      request.files.map((f) => f.id).toSet(),
      saveDirectory: saveDir,
    );
  }

  @override
  void onSessionUpdate(ReceiveSession session) => snapshots.add(session);
}

void main() {
  late SuviIdentity identity;
  late Directory tmp;

  // A tiny in-memory stand-in for the Flutter asset bundle.
  final assets = <String, List<int>>{
    'assets/web/index.html': utf8.encode(
      '<!DOCTYPE html><title>Suvi Share</title><body>ok',
    ),
    'assets/web/style.css': utf8.encode(':root{--teal:#00897B}'),
    'assets/web/app.js': utf8.encode('console.log("suvi")'),
  };
  Future<List<int>?> loadAsset(String path) async => assets[path];

  setUpAll(() => identity = SuviIdentity.generate(commonName: 'web-test'));

  setUp(() async => tmp = await Directory.systemTemp.createTemp('suvi_web_'));
  tearDown(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  /// Boots an HTTP (not HTTPS) server on loopback with the web handler mounted,
  /// exactly like the app's web-share listener.
  Future<(SuviServer, WebShareHandler, SessionManager, String)> boot({
    _AcceptAll? delegate,
    String? sessionPin,
  }) async {
    final d = delegate ?? _AcceptAll(p.join(tmp.path, 'inbox'));
    final sessions = SessionManager(delegate: d);
    final web = WebShareHandler(
      loadAsset: loadAsset,
      deviceAlias: () => 'Brave Peacock',
      sessionPin: sessionPin,
    );
    var port = 0;
    final server = SuviServer(
      selfInfo: () => DeviceInfo(
        alias: 'Brave Peacock',
        fingerprint: identity.fingerprint,
        port: port,
        protocol: PeerProtocol.http,
        download: true,
      ),
      sessions: sessions,
      identity: identity,
      webHandler: web.call,
      requiredUploadPin: () => web.sessionPin,
    );
    await server.start(
      port: 0,
      https: false,
      address: InternetAddress.loopbackIPv4,
    );
    port = server.port!;
    return (server, web, sessions, 'http://127.0.0.1:$port');
  }

  test(
    'serves the browser page and its assets, and blocks path traversal',
    () async {
      final (server, _, sessions, base) = await boot();

      final index = await http.get(Uri.parse(base));
      expect(index.statusCode, 200);
      expect(index.headers['content-type'], contains('text/html'));
      expect(index.body, contains('Suvi Share'));

      final css = await http.get(Uri.parse('$base/style.css'));
      expect(css.statusCode, 200);
      expect(css.headers['content-type'], contains('text/css'));

      final js = await http.get(Uri.parse('$base/app.js'));
      expect(js.statusCode, 200);
      expect(js.headers['content-type'], contains('javascript'));

      // Unknown paths fall back to the SPA shell, not a 404 page.
      final unknown = await http.get(Uri.parse('$base/whatever'));
      expect(unknown.statusCode, 200);
      expect(unknown.body, contains('Suvi Share'));

      // ..%2F escapes must not reach outside the asset folder.
      final traversal = await http.get(Uri.parse('$base/..%2F..%2Fsecret.txt'));
      expect(traversal.statusCode, anyOf(403, 200));
      expect(traversal.body, isNot(contains('BEGIN')));

      await server.stop();
      await sessions.dispose();
    },
  );

  test('web-info reports the alias and whether anything is offered', () async {
    final (server, web, sessions, base) = await boot();

    var info = jsonDecode(
      (await http.get(Uri.parse('$base/api/suvi/v1/web-info'))).body,
    ) as Map;
    expect(info['alias'], 'Brave Peacock');
    expect(info['hasOffer'], isFalse);
    expect(info['pinRequired'], isFalse);

    final f = File(p.join(tmp.path, 'notes.txt'))
      ..writeAsStringSync('hello from the desktop');
    await web.publish([SendItem.file(f.path)]);

    info = jsonDecode(
      (await http.get(Uri.parse('$base/api/suvi/v1/web-info'))).body,
    ) as Map;
    expect(info['hasOffer'], isTrue);
    expect(info['fileCount'], 1);
    expect(info['totalSize'], greaterThan(0));

    await server.stop();
    await sessions.dispose();
  });

  test('browser downloads an offered file', () async {
    final (server, web, sessions, base) = await boot();
    final content = 'hello from the desktop';
    final f = File(p.join(tmp.path, 'notes.txt'))..writeAsStringSync(content);
    final offer = await web.publish([SendItem.file(f.path)]);

    final prep = await http.post(
      Uri.parse('$base/api/suvi/v1/prepare-download'),
    );
    expect(prep.statusCode, 200);
    final body = jsonDecode(prep.body) as Map<String, dynamic>;
    expect(body['sessionId'], offer.sessionId);
    final files = (body['files'] as Map).values.toList();
    expect(files.length, 1);
    final fileId = (files.first as Map)['id'] as String;

    final dl = await http.get(
      Uri.parse(
        '$base/api/suvi/v1/download?sessionId=${offer.sessionId}&fileId=$fileId',
      ),
    );
    expect(dl.statusCode, 200);
    expect(dl.body, content);
    expect(dl.headers['content-disposition'], contains('notes.txt'));

    final partial = await http.get(
      Uri.parse(
        '$base/api/suvi/v1/download'
        '?sessionId=${offer.sessionId}&fileId=$fileId',
      ),
      headers: {'range': 'bytes=6-9'},
    );
    expect(partial.statusCode, 206);
    expect(partial.body, 'from');
    expect(partial.headers['content-range'], 'bytes 6-9/${content.length}');
    expect(partial.headers['accept-ranges'], 'bytes');

    // After revoking, the same URL must stop working.
    web.revoke();
    final after = await http.get(
      Uri.parse(
        '$base/api/suvi/v1/download?sessionId=${offer.sessionId}&fileId=$fileId',
      ),
    );
    expect(after.statusCode, 404);

    await server.stop();
    await sessions.dispose();
  });

  test('PIN gates prepare-download and download', () async {
    final (server, web, sessions, base) = await boot();
    final f = File(p.join(tmp.path, 'secret.txt'))
      ..writeAsStringSync('classified');
    final offer = await web.publish([SendItem.file(f.path)], pin: '2468');

    final noPin = await http.post(
      Uri.parse('$base/api/suvi/v1/prepare-download'),
    );
    expect(noPin.statusCode, 401);

    final wrong = await http.post(
      Uri.parse('$base/api/suvi/v1/prepare-download?pin=1111'),
    );
    expect(wrong.statusCode, 401);

    final ok = await http.post(
      Uri.parse('$base/api/suvi/v1/prepare-download?pin=2468'),
    );
    expect(ok.statusCode, 200);

    final fileId = ((jsonDecode(ok.body) as Map)['files'] as Map).keys.first;
    final dl = await http.get(
      Uri.parse(
        '$base/api/suvi/v1/download?sessionId=${offer.sessionId}&fileId=$fileId',
      ),
    );
    expect(
      dl.statusCode,
      200,
      reason: 'the IP is authorised after a correct PIN',
    );

    await server.stop();
    await sessions.dispose();
  });

  test(
    'session PIN gates browser uploads before prompting the receiver',
    () async {
      final delegate = _AcceptAll(p.join(tmp.path, 'inbox'));
      final (server, _, sessions, base) = await boot(
        delegate: delegate,
        sessionPin: '654321',
      );
      final body = jsonEncode({
        'info': {
          'alias': 'Browser',
          'fingerprint': 'web-test',
          'port': 0,
          'protocol': 'http',
        },
        'files': <String, Object?>{},
        'text': 'hello',
      });

      final denied = await http.post(
        Uri.parse('$base/api/suvi/v1/prepare-upload'),
        headers: {'content-type': 'application/json'},
        body: body,
      );
      expect(denied.statusCode, 401);
      expect(delegate.last, isNull);

      final accepted = await http.post(
        Uri.parse('$base/api/suvi/v1/prepare-upload?pin=654321'),
        headers: {'content-type': 'application/json'},
        body: body,
      );
      expect(accepted.statusCode, 200);
      expect(delegate.last?.text, 'hello');

      await server.stop();
      await sessions.dispose();
    },
  );

  test('an expired offer stops serving', () async {
    final (server, web, sessions, base) = await boot();
    final f = File(p.join(tmp.path, 'x.txt'))..writeAsStringSync('x');
    await web.publish([
      SendItem.file(f.path),
    ], ttl: const Duration(milliseconds: 30));
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(web.hasOffer, isFalse);
    final prep = await http.post(
      Uri.parse('$base/api/suvi/v1/prepare-download'),
    );
    expect(prep.statusCode, 404);
    await server.stop();
    await sessions.dispose();
  });

  test('a browser uploads to the device through the shared API', () async {
    final saveDir = p.join(tmp.path, 'inbox');
    final delegate = _AcceptAll(saveDir);
    final (server, _, sessions, base) = await boot(delegate: delegate);

    const payload = 'sent from a phone browser';
    final prepRes = await http.post(
      Uri.parse('$base/api/suvi/v1/prepare-upload'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'info': {
          'alias': 'Browser · iPhone',
          'version': '1.0',
          'deviceType': 'web',
          'fingerprint': 'web-abc',
          'port': 0,
          'protocol': 'http',
        },
        'files': {
          'w1': {
            'id': 'w1',
            'fileName': 'from-browser.txt',
            'size': payload.length,
            'fileType': 'text/plain',
          },
        },
      }),
    );
    expect(prepRes.statusCode, 200);
    final prep = jsonDecode(prepRes.body) as Map<String, dynamic>;
    expect(delegate.last!.sender.deviceType, DeviceType.web);

    final token = (prep['files'] as Map)['w1'] as String;
    final up = await http.post(
      Uri.parse(
        '$base/api/suvi/v1/upload'
        '?sessionId=${prep['sessionId']}&fileId=w1&token=$token',
      ),
      headers: {'content-type': 'application/octet-stream'},
      body: payload,
    );
    expect(up.statusCode, 200, reason: up.body);

    final saved = File(p.join(saveDir, 'from-browser.txt'));
    expect(await saved.exists(), isTrue);
    expect(await saved.readAsString(), payload);

    await server.stop();
    await sessions.dispose();
  });

  test('the API still answers while the web handler is mounted', () async {
    final (server, _, sessions, base) = await boot();
    final info = await http.get(Uri.parse('$base/api/suvi/v1/info'));
    expect(info.statusCode, 200);
    final parsed = DeviceInfo.tryParse(jsonDecode(info.body));
    expect(parsed?.alias, 'Brave Peacock');
    expect(parsed?.download, isTrue);
    await server.stop();
    await sessions.dispose();
  });
}
