/// Protocol-wide constants for Suvi Share Protocol v1 (SSP/1).
/// See docs/05-protocol-spec.md.
class SuviConstants {
  SuviConstants._();

  /// Multicast group — kept inside 224.0.0.0/24 because some Android builds
  /// reject other groups.
  static const String multicastGroup = '224.0.0.167';

  /// UDP discovery port and default TCP API port.
  static const int defaultPort = 53317;

  /// Web-share HTTP port offset from the API port.
  static const int webSharePortOffset = 1;

  /// mDNS / DNS-SD service type.
  static const String mdnsServiceType = '_suvishare._tcp';

  /// API path prefix.
  static const String apiPrefix = '/api/suvi/v1';

  /// Protocol version advertised in device info.
  static const String protocolVersion = '1.0';

  /// How often to announce while actively discovering.
  static const Duration announceIntervalActive = Duration(seconds: 5);

  /// How often to announce when idle (still discoverable).
  static const Duration announceIntervalIdle = Duration(seconds: 30);

  /// Peers not seen for this long are dropped.
  static const Duration peerTtl = Duration(seconds: 75);

  /// Subnet-scan concurrency and per-host timeout.
  static const int scanConcurrency = 50;
  static const Duration scanTimeout = Duration(milliseconds: 1200);

  /// Block size used when reading a file to stream it.
  ///
  /// Dart's `File.openRead()` yields 64 KB chunks, which is the classic Dart
  /// throughput killer for HTTP transfers — on a real network (even 1 ms RTT)
  /// the per-chunk overhead collapses gigabit links to ~1 MB/s. Reading in
  /// 1 MB blocks routinely takes the same transfer from single-digit MB/s to
  /// tens of MB/s.
  static const int chunkSize = 1024 * 1024;

  /// Receiver-side coalescing window. Android's asynchronous file bridge has
  /// noticeable per-write overhead, so a bounded 4 MB window keeps
  /// backpressure while avoiding thousands of small native I/O calls.
  static const int receiveWriteBufferSize = 4 * 1024 * 1024;

  /// Maximum cadence for transfer snapshots consumed by the UI. Four updates
  /// per second stay visually smooth while avoiding hot-path map allocation,
  /// provider rebuild, and platform notification work for every TLS record.
  static const int progressUpdateIntervalMs = 250;

  /// Limits.
  static const int maxFilesPerSession = 10000;
  static const int maxPreviewBytes = 32 * 1024;
  static const int maxTextBytes = 1024 * 1024;
  static const int maxJsonBodyBytes = 8 * 1024 * 1024;
  static const int maxFileNameBytes = 1024;
  static const int maxFileIdBytes = 128;
  static const int maxMimeBytes = 255;
  static const int maxDeclaredFileBytes = 16 * 1024 * 1024 * 1024 * 1024;
  static const int prepareRateLimitPerMinute = 10;

  /// Default number of parallel uploads per session.
  static const int parallelUploads = 2;
}
