import 'dart:io';

import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

const _channel = MethodChannel('com.suvishare/open_location');

/// Opens a directory without exposing a `file://` URI on Android.
Future<bool> openDirectoryLocation(String path) async {
  if (Platform.isAndroid) {
    try {
      return await _channel.invokeMethod<bool>('openDirectory', {
            'path': path,
          }) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  return launchUrl(Uri.directory(path));
}

Future<bool> openContainingFolder(String filePath) =>
    openDirectoryLocation(File(filePath).parent.path);
