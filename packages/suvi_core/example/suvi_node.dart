// A headless Suvi Share node. Useful for testing discovery and transfers on a
// real network without building the Flutter app, and as a reference for how the
// pieces fit together.
//
//   dart run example/suvi_node.dart --name "Laptop" --dir ./inbox
//   dart run example/suvi_node.dart --name "Laptop" --send ./photo.jpg --to "Phone"
//
// Options:
//   --name <alias>     device name shown to peers (default: random)
//   --port <n>         API port (default: 53317)
//   --dir <path>       where received files land (default: ./suvi-inbox)
//   --send <path>      file to send (repeatable)
//   --to <alias>       peer alias to send to; waits until it appears
//   --accept-all       auto-accept incoming transfers (otherwise prompt on stdin)
//   --timeout <secs>   how long to wait for the target peer (default: 30)
//   --web              also serve the browser page over plain HTTP on port+1
//   --web-assets <dir> directory holding index.html/style.css/app.js
//   --offer <path>     offer a file for browsers to download (repeatable)
//   --web-pin <pin>    require this PIN on the browser page

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:suvi_core/suvi_core.dart';

Future<void> main(List<String> args) async {
  final opts = _parse(args);

  Logger.root.level = opts.verbose ? Level.ALL : Level.INFO;
  Logger.root.onRecord.listen(
    (r) => stderr.writeln('[${r.level.name}] ${r.loggerName}: ${r.message}'),
  );

  final saveDir = Directory(opts.dir);
  await saveDir.create(recursive: true);

  stdout.writeln('Generating certificate…');
  final identity = SuviIdentity.generate(commonName: opts.name);
  stdout.writeln('  fingerprint ${identity.shortFingerprint}');

  var port = opts.port;
  DeviceInfo selfInfo() => DeviceInfo(
    alias: opts.name,
    deviceModel: Platform.operatingSystem,
    deviceType: DeviceType.headless,
    fingerprint: identity.fingerprint,
    port: port,
  );

  final sessions = SessionManager(
    delegate: _CliDelegate(saveDir.absolute.path, acceptAll: opts.acceptAll),
  );
  sessions.updates.listen((s) {
    if (s.status == SessionStatus.transferring) {
      final pct = (s.progress * 100).toStringAsFixed(0);
      stdout.write(
        '\r  receiving ${s.finishedCount}/${s.files.length} · $pct%   ',
      );
    } else if (s.status.isTerminal) {
      stdout.writeln(
        '\r  ${s.status.name}: ${s.finishedCount} file(s) → ${s.saveDirectory}   ',
      );
      for (final f in s.files.values) {
        if (f.savedPath != null) stdout.writeln('    ${f.savedPath}');
      }
      if (s.text != null) stdout.writeln('    text: ${s.text}');
    }
  });

  final client = PeerClient(selfInfo: selfInfo);
  final discovery = DiscoveryService(selfInfo: selfInfo, client: client);
  final server = SuviServer(
    selfInfo: selfInfo,
    sessions: sessions,
    identity: identity,
    onRegister: discovery.onRegisterReceived,
  );

  await server.start(port: opts.port);
  port = server.port!;
  final ip = await NetworkUtils.primaryIp();
  stdout.writeln('Listening on https://${ip ?? '?'}:$port as "${opts.name}"');

  SuviServer? webServer;
  if (opts.web) {
    final assetRoot = Directory(opts.webAssets);
    final handler = WebShareHandler(
      loadAsset: (path) async {
        // The core takes assets by callback so it stays Flutter-free; here we
        // read them off disk instead of out of the Flutter asset bundle.
        final file = File(
          '${assetRoot.path}/${path.replaceFirst('assets/web/', '')}',
        );
        return await file.exists() ? file.readAsBytes() : null;
      },
      deviceAlias: () => opts.name,
      sessionPin: opts.webPin,
    );
    if (opts.offerPaths.isNotEmpty) {
      await handler.publish(
        opts.offerPaths.map(SendItem.file).toList(),
        pin: opts.webPin,
      );
    }
    final webPort = port + SuviConstants.webSharePortOffset;
    webServer = SuviServer(
      selfInfo: () =>
          selfInfo().copyWith(protocol: PeerProtocol.http, download: true),
      sessions: sessions,
      identity: identity,
      webHandler: handler.call,
      requiredUploadPin: () => handler.sessionPin,
    );
    await webServer.start(port: webPort, https: false);
    stdout.writeln(
      'Web share on http://${ip ?? '?'}:${webServer.port}'
      '${opts.webPin != null ? ' (PIN ${opts.webPin})' : ''}',
    );
  }

  discovery.registry.stream.listen((peers) {
    stdout.writeln('Peers (${peers.length}):');
    for (final p in peers) {
      stdout.writeln(
        '  ${p.alias.padRight(20)} ${p.ip}:${p.port}  ${p.info.deviceType.name}  ${p.source.name}',
      );
    }
  });
  await discovery.start();

  if (opts.sendPaths.isEmpty) {
    stdout.writeln('Discovering… (Ctrl-C to quit)');
    await ProcessSignal.sigint.watch().first;
  } else {
    final target = await _awaitPeer(
      discovery,
      opts.to,
      Duration(seconds: opts.timeoutSecs),
    );
    if (target == null) {
      stderr.writeln('No peer matching "${opts.to ?? 'any'}" appeared.');
      exitCode = 1;
    } else {
      stdout.writeln(
        'Sending ${opts.sendPaths.length} file(s) to ${target.alias}…',
      );
      final sender = SendService(client: client, selfInfo: selfInfo);
      sender.updates.listen((s) {
        if (s.status == SessionStatus.transferring) {
          stdout.write('\r  ${(s.progress * 100).toStringAsFixed(0)}%   ');
        }
      });
      final result = await sender.send(
        target: target,
        items: opts.sendPaths.map(SendItem.file).toList(),
      );
      stdout.writeln(
        '\r  ${result.status.name}: ${result.finishedCount} sent'
        '${result.errorMessage != null ? ' (${result.errorMessage})' : ''}   ',
      );
      exitCode = result.status == SessionStatus.finished ? 0 : 1;
      await sender.dispose();
    }
  }

  await discovery.dispose();
  await webServer?.stop();
  await server.stop();
  await sessions.dispose();
  client.close();
}

Future<Peer?> _awaitPeer(
  DiscoveryService d,
  String? alias,
  Duration timeout,
) async {
  bool matches(Peer p) =>
      alias == null || p.alias.toLowerCase() == alias.toLowerCase();
  final existing = d.registry.peers.where(matches);
  if (existing.isNotEmpty) return existing.first;

  final completer = Completer<Peer?>();
  final sub = d.registry.stream.listen((peers) {
    final hit = peers.where(matches);
    if (hit.isNotEmpty && !completer.isCompleted) completer.complete(hit.first);
  });
  // A scan covers networks where multicast is filtered.
  unawaited(
    Future<void>.delayed(const Duration(seconds: 3), () {
      if (!completer.isCompleted) d.scanSubnet();
    }),
  );
  final timer = Timer(timeout, () {
    if (!completer.isCompleted) completer.complete(null);
  });
  final peer = await completer.future;
  timer.cancel();
  await sub.cancel();
  return peer;
}

class _CliDelegate implements ReceiveDelegate {
  _CliDelegate(this.saveDir, {required this.acceptAll});
  final String saveDir;
  final bool acceptAll;

  @override
  String? get requiredPin => null;

  @override
  Future<ReceiveDecision> decide(IncomingRequest request) async {
    final ids = request.files.map((f) => f.id).toSet();
    stdout.writeln(
      '\n${request.sender.alias} (${request.senderIp}) wants to send:',
    );
    for (final f in request.files) {
      stdout.writeln('  ${f.fileName}  ${_bytes(f.size)}');
    }
    if (request.text != null) stdout.writeln('  text: ${request.text}');
    if (acceptAll) {
      stdout.writeln('  → auto-accepted');
      return ReceiveDecision.accept(ids, saveDirectory: saveDir);
    }
    stdout.write('Accept? [y/N] ');
    final answer = stdin.readLineSync(encoding: utf8)?.trim().toLowerCase();
    if (answer == 'y' || answer == 'yes') {
      return ReceiveDecision.accept(ids, saveDirectory: saveDir);
    }
    return const ReceiveDecision.decline();
  }

  @override
  void onSessionUpdate(ReceiveSession session) {}

  static String _bytes(int n) {
    if (n < 1024) return '$n B';
    const u = ['KB', 'MB', 'GB'];
    var v = n / 1024, i = 0;
    while (v >= 1024 && i < u.length - 1) {
      v /= 1024;
      i++;
    }
    return '${v.toStringAsFixed(1)} ${u[i]}';
  }
}

class _Opts {
  _Opts({
    required this.name,
    required this.port,
    required this.dir,
    required this.sendPaths,
    required this.to,
    required this.acceptAll,
    required this.timeoutSecs,
    required this.verbose,
    required this.web,
    required this.webAssets,
    required this.offerPaths,
    required this.webPin,
  });
  final String name;
  final int port;
  final String dir;
  final List<String> sendPaths;
  final String? to;
  final bool acceptAll;
  final int timeoutSecs;
  final bool verbose;
  final bool web;
  final String webAssets;
  final List<String> offerPaths;
  final String? webPin;
}

_Opts _parse(List<String> args) {
  String? name, to, webPin;
  var port = SuviConstants.defaultPort;
  var dir = 'suvi-inbox';
  var webAssets = '../../app/assets/web';
  var acceptAll = false, verbose = false, web = false;
  var timeoutSecs = 30;
  final send = <String>[];
  final offer = <String>[];

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--name':
        name = args[++i];
      case '--port':
        port = int.tryParse(args[++i]) ?? port;
      case '--dir':
        dir = args[++i];
      case '--send':
        send.add(args[++i]);
      case '--to':
        to = args[++i];
      case '--timeout':
        timeoutSecs = int.tryParse(args[++i]) ?? timeoutSecs;
      case '--accept-all':
        acceptAll = true;
      case '--web':
        web = true;
      case '--web-assets':
        webAssets = args[++i];
        web = true;
      case '--offer':
        offer.add(args[++i]);
        web = true;
      case '--web-pin':
        webPin = args[++i];
        web = true;
      case '-v' || '--verbose':
        verbose = true;
    }
  }
  return _Opts(
    name: name ?? AliasGenerator.generate(),
    port: port,
    dir: dir,
    sendPaths: send,
    to: to,
    acceptAll: acceptAll,
    timeoutSecs: timeoutSecs,
    verbose: verbose,
    web: web,
    webAssets: webAssets,
    offerPaths: offer,
    webPin: webPin,
  );
}
