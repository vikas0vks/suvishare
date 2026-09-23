import 'dart:async';

import '../client/peer_client.dart';
import '../constants.dart';
import '../models/device_info.dart';
import '../util/network_utils.dart';

/// Result of probing one host.
class ScanHit {
  const ScanHit(this.ip, this.info);
  final String ip;
  final DeviceInfo info;
}

/// Brute-force /24 scan: `POST /register` to every host. Last-resort
/// fallback when multicast is filtered (guest Wi-Fi, some Android builds).
class SubnetScanner {
  SubnetScanner(this._client);

  final PeerClient _client;

  /// Scans all local /24 subnets on [port]. Emits hits as they arrive.
  /// [onProgress] receives (done, total).
  Stream<ScanHit> scan({
    required int port,
    PeerProtocol protocol = PeerProtocol.https,
    int concurrency = SuviConstants.scanConcurrency,
    Duration timeout = SuviConstants.scanTimeout,
    void Function(int done, int total)? onProgress,
  }) async* {
    final addresses = await NetworkUtils.localAddresses();
    final hosts = <String>{};
    for (final a in addresses) {
      hosts.addAll(a.subnetHosts());
    }
    final total = hosts.length;
    var done = 0;
    final queue = hosts.toList();
    final controller = StreamController<ScanHit>();

    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final ip = queue.removeLast();
        final info = await _client.register(
          ip,
          port,
          protocol: protocol,
          timeout: timeout,
        );
        done++;
        onProgress?.call(done, total);
        if (info != null && !controller.isClosed) {
          controller.add(ScanHit(ip, info));
        }
      }
    }

    unawaited(
      Future.wait(List.generate(concurrency.clamp(1, 128), (_) => worker()))
          .whenComplete(controller.close),
    );

    yield* controller.stream;
  }
}
