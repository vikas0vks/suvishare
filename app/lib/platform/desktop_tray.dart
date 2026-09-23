import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

bool get isDesktopPlatform =>
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;

/// System-tray icon + close-to-tray behaviour for Windows/Linux.
///
/// The app keeps receiving while the window is hidden, which is the whole
/// point of the tray. Crucially: if the tray cannot be set up (icon missing,
/// no tray on this desktop), close-to-tray is force-disabled — otherwise the
/// window would hide with no way to bring it back, which reads as "the app
/// hung and disappeared".
class DesktopTray with TrayListener, WindowListener {
  DesktopTray({required this.appName});

  static final _log = Logger('suvi.tray');
  final String appName;

  bool _installed = false;
  bool _functional = false;
  bool _closeToTray = true;
  bool _receiving = true;

  /// Called when the user toggles "Receiving" from the tray menu.
  void Function(bool enabled)? onReceiveToggled;

  /// Called when the user picks Quit.
  Future<void> Function()? onQuit;

  /// Whether the tray actually works; when false, closing the window quits.
  bool get isFunctional => _functional;

  /// Resolves the tray icon inside the Flutter asset bundle, which is real
  /// files on disk in every desktop build — debug, release, and installed —
  /// always relative to the executable. (A repo-relative path like
  /// `windows/runner/resources/...` only exists when running from source,
  /// which is exactly why the installed build used to lose its tray icon.)
  static String? _iconPath() {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final assetRoot = p.join(
      exeDir,
      'data',
      'flutter_assets',
      'assets',
      'icon',
    );
    final candidates = Platform.isWindows
        ? [p.join(assetRoot, 'app_icon.ico')]
        : [
            p.join(assetRoot, 'tray.png'),
            p.join(assetRoot, 'suvi-share-256.png'),
          ];
    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    return null;
  }

  /// Returns `true` when the tray is usable. On failure the window's close
  /// button quits the app (safe default) regardless of [closeToTray].
  Future<bool> install({
    required bool closeToTray,
    required bool receiving,
  }) async {
    if (!isDesktopPlatform || _installed) return _functional;
    _closeToTray = closeToTray;
    _receiving = receiving;
    _installed = true;
    windowManager.addListener(this);

    final icon = _iconPath();
    if (icon == null) {
      _log.warning('tray icon asset not found; disabling close-to-tray');
      _functional = false;
      await windowManager.setPreventClose(false);
      return false;
    }
    try {
      trayManager.addListener(this);
      await trayManager.setIcon(icon);
      await trayManager.setToolTip(appName);
      await _rebuildMenu();
      _functional = true;
    } catch (e) {
      _log.warning('tray setup failed ($e); disabling close-to-tray');
      _functional = false;
    }
    await windowManager.setPreventClose(_functional && _closeToTray);
    return _functional;
  }

  Future<void> setCloseToTray(bool value) async {
    _closeToTray = value;
    if (isDesktopPlatform && _installed) {
      await windowManager.setPreventClose(_functional && value);
    }
  }

  Future<void> setReceiving(bool value) async {
    if (_receiving == value) return;
    _receiving = value;
    if (_installed && _functional) await _rebuildMenu();
  }

  Future<void> _rebuildMenu() async {
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'show', label: 'Open $appName'),
          MenuItem.separator(),
          MenuItem.checkbox(
            key: 'receive',
            label: 'Receiving',
            checked: _receiving,
          ),
          MenuItem.separator(),
          MenuItem(key: 'quit', label: 'Quit'),
        ],
      ),
    );
  }

  Future<void> _show() async {
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  void onTrayIconMouseDown() => _show();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        _show();
      case 'receive':
        _receiving = !_receiving;
        onReceiveToggled?.call(_receiving);
        _rebuildMenu();
      case 'quit':
        _quit();
    }
  }

  Future<void> _quit() async {
    try {
      await onQuit?.call().timeout(const Duration(seconds: 5));
    } catch (e) {
      _log.warning('shutdown during quit failed: $e');
    }
    try {
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
    } catch (_) {
      exit(0);
    }
  }

  @override
  void onWindowClose() async {
    if (_functional && _closeToTray) {
      await windowManager.hide();
    } else {
      await _quit();
    }
  }

  Future<void> dispose() async {
    if (!_installed) return;
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    try {
      await trayManager.destroy();
    } catch (_) {}
    _installed = false;
    _functional = false;
  }
}

/// Global instance wired up from the app shell.
final desktopTray = DesktopTray(appName: 'Suvi Share');

/// Keyboard shortcuts for desktop (see docs/02 §2.7).
class SuviShortcuts {
  SuviShortcuts._();

  static const pickFiles = SingleActivator(
    LogicalKeyboardKey.keyO,
    control: true,
  );
  static const sendClipboard = SingleActivator(
    LogicalKeyboardKey.keyV,
    control: true,
    shift: true,
  );
  static const refresh = SingleActivator(LogicalKeyboardKey.f5);
}
