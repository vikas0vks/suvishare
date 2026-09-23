import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:suvi_core/suvi_core.dart';

import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/app_services.dart';

/// Camera platforms only — desktop shows its QR, phones scan it.
bool get canScanQr => Platform.isAndroid || Platform.isIOS;

/// Opens the scanner; resolves with the connected [Peer] or null.
Future<Peer?> scanQrAndConnect(BuildContext context, WidgetRef ref) async {
  if (!canScanQr) return null;
  return Navigator.of(
    context,
    rootNavigator: true,
  ).push<Peer>(MaterialPageRoute(builder: (_) => const _QrScanScreen()));
}

class _QrScanScreen extends ConsumerStatefulWidget {
  const _QrScanScreen();
  @override
  ConsumerState<_QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends ConsumerState<_QrScanScreen> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Accepts `suvi://ip:port#fingerprint`, a web-share URL, or a bare
  /// `ip[:port]` — anything another Suvi Share screen can display.
  static String? addressOf(String raw) {
    final v = raw.trim();
    final uri = Uri.tryParse(v);
    if (uri != null &&
        (uri.scheme == 'suvi' ||
            uri.scheme == 'http' ||
            uri.scheme == 'https')) {
      if (uri.host.isEmpty) return null;
      return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
    }
    final bare = RegExp(r'^\d{1,3}(\.\d{1,3}){3}(:\d{1,5})?$');
    return bare.hasMatch(v) ? v : null;
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy || !mounted) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;
    final address = addressOf(raw);
    if (address == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final services = await ref.read(appServicesProvider.future);
      final peer = await services.discovery.addManual(address);
      if (!mounted) return;
      if (peer != null) {
        Navigator.of(context).pop(peer);
      } else {
        setState(() {
          _busy = false;
          _error = AppLocalizations.of(context).deviceNotReachable;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = AppLocalizations.of(context).deviceNotReachable;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(l.scanQr),
        actions: [
          IconButton(
            tooltip: 'Torch',
            icon: const Icon(Icons.flashlight_on_rounded),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          // Framing overlay so it is obvious where to aim.
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(color: scheme.primary, width: 3),
                borderRadius: BorderRadius.circular(SuviRadius.xl),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 48,
            child: Column(
              children: [
                if (_busy)
                  const CircularProgressIndicator(color: Colors.white)
                else
                  Text(
                    _error ?? l.scanQrHint,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _error != null
                          ? scheme.errorContainer
                          : Colors.white,
                      fontSize: 15,
                      shadows: const [
                        Shadow(blurRadius: 8, color: Colors.black),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
