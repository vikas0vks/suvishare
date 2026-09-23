import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:meta/meta.dart';

/// A device's cryptographic identity: a self-signed X.509 certificate and
/// its private key. The SHA-256 of the DER certificate is the device
/// fingerprint used for discovery de-duplication and certificate pinning.
@immutable
class SuviIdentity {
  const SuviIdentity({
    required this.certificatePem,
    required this.privateKeyPem,
    required this.fingerprint,
  });

  final String certificatePem;
  final String privateKeyPem;

  /// Lowercase hex SHA-256 of the DER-encoded certificate.
  final String fingerprint;

  /// Short, human-comparable form (first 12 hex chars grouped by 4).
  String get shortFingerprint {
    final s = fingerprint.length >= 12
        ? fingerprint.substring(0, 12)
        : fingerprint;
    return [
      for (var i = 0; i < s.length; i += 4)
        s.substring(i, (i + 4).clamp(0, s.length)),
    ].join(' ').toUpperCase();
  }

  /// Builds a `SecurityContext` ready for `HttpServer.bindSecure`.
  SecurityContext toSecurityContext() {
    return SecurityContext()
      ..useCertificateChainBytes(utf8.encode(certificatePem))
      ..usePrivateKeyBytes(utf8.encode(privateKeyPem));
  }

  Map<String, dynamic> toJson() => {
    'certificatePem': certificatePem,
    'privateKeyPem': privateKeyPem,
    'fingerprint': fingerprint,
  };

  static SuviIdentity? tryParse(Object? json) {
    if (json is! Map) return null;
    final c = json['certificatePem'];
    final k = json['privateKeyPem'];
    if (c is! String || k is! String || c.isEmpty || k.isEmpty) return null;
    return SuviIdentity(
      certificatePem: c,
      privateKeyPem: k,
      fingerprint: fingerprintOfPem(c),
    );
  }

  /// Generates a fresh RSA-2048 self-signed certificate valid for 10 years.
  /// CPU-heavy (1–10 s depending on device) — call inside `Isolate.run`.
  static SuviIdentity generate({String commonName = 'Suvi Share'}) {
    final pair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
    final privateKey = pair.privateKey as RSAPrivateKey;
    final publicKey = pair.publicKey as RSAPublicKey;
    final dn = <String, String>{
      'CN': commonName,
      'O': 'Suvi Share',
      'OU': 'Suvi Share',
      'L': 'LAN',
      'S': 'LAN',
      'C': 'IN',
    };
    final csr = X509Utils.generateRsaCsrPem(dn, privateKey, publicKey);
    final certPem = X509Utils.generateSelfSignedCertificate(
      privateKey,
      csr,
      365 * 10,
    );
    final keyPem = CryptoUtils.encodeRSAPrivateKeyToPem(privateKey);
    return SuviIdentity(
      certificatePem: certPem,
      privateKeyPem: keyPem,
      fingerprint: fingerprintOfPem(certPem),
    );
  }

  /// SHA-256 hex of the DER bytes inside a PEM certificate.
  static String fingerprintOfPem(String pem) =>
      fingerprintOfDer(CryptoUtils.getBytesFromPEMString(pem));

  /// SHA-256 hex of DER bytes (e.g. `X509Certificate.der`).
  static String fingerprintOfDer(List<int> der) =>
      crypto.sha256.convert(Uint8List.fromList(der)).toString();
}
