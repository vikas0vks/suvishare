/// Suvi Share core — protocol models, LAN discovery, HTTPS server, peer client
/// and security primitives. Pure Dart; no Flutter dependency.
library;

export 'src/client/peer_client.dart';
export 'src/constants.dart';
export 'src/discovery/discovery_service.dart';
export 'src/discovery/multicast_discovery.dart';
export 'src/discovery/peer.dart';
export 'src/discovery/peer_registry.dart';
export 'src/discovery/subnet_scanner.dart';
export 'src/models/device_info.dart';
export 'src/models/file_dto.dart';
export 'src/models/session.dart';
export 'src/security/filename_sanitizer.dart';
export 'src/security/identity.dart';
export 'src/security/trust_store.dart';
export 'src/server/receive_session.dart';
export 'src/server/session_manager.dart';
export 'src/server/suvi_server.dart';
export 'src/server/web_share.dart';
export 'src/transfer/send_service.dart';
export 'src/util/alias_generator.dart';
export 'src/util/network_utils.dart';
