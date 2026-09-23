import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'platform/single_instance.dart';

bool get isDesktop =>
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;

final _log = Logger('suvi.main');

Future<void> main() async {
  // One zone for everything, so no uncaught async error can escape unlogged
  // and take the UI down with it.
  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      Logger.root.level = kDebugMode ? Level.ALL : Level.INFO;
      Logger.root.onRecord.listen((r) {
        debugPrint(
          '[${r.level.name}] ${r.loggerName}: ${r.message}'
          '${r.error != null ? ' — ${r.error}' : ''}',
        );
      });

      // Framework errors: log and keep running instead of freezing the tree.
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        _log.severe(
          'flutter error: ${details.exceptionAsString()}',
          details.exception,
          details.stack,
        );
      };
      // Uncaught platform-dispatcher errors: swallow after logging. A background
      // socket hiccup must never look like an app hang.
      PlatformDispatcher.instance.onError = (error, stack) {
        _log.severe('uncaught: $error', error, stack);
        return true;
      };

      if (isDesktop) {
        // Second launch → focus the running window and quit. (Windows also
        // enforces this natively in the runner before Dart starts.)
        if (!await SingleInstance.acquire()) {
          exit(0);
        }
        try {
          await windowManager.ensureInitialized();
          const options = WindowOptions(
            size: Size(1040, 720),
            minimumSize: Size(420, 600),
            center: true,
            title: 'Suvi Share',
            titleBarStyle: TitleBarStyle.normal,
          );
          await windowManager.waitUntilReadyToShow(options, () async {
            await windowManager.show();
            await windowManager.focus();
          });
        } catch (e, st) {
          // A window-chrome failure must not stop the app from opening at all.
          _log.severe('window init failed: $e', e, st);
        }
      }

      runApp(const ProviderScope(child: SuviApp()));
    },
    (error, stack) {
      _log.severe('zone: $error', error, stack);
    },
  );
}
