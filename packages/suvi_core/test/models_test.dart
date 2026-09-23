import 'dart:convert';

import 'package:suvi_core/suvi_core.dart';
import 'package:test/test.dart';

void main() {
  group('DeviceInfo', () {
    test('round-trips through JSON', () {
      const info = DeviceInfo(
        alias: 'Brave Peacock',
        fingerprint: 'abc',
        port: 53317,
        deviceModel: 'Windows 11',
        deviceType: DeviceType.desktop,
        download: true,
        announce: true,
        avatarColor: 3,
      );
      final json = jsonDecode(jsonEncode(info.toJson()));
      final back = DeviceInfo.fromJson(json as Map<String, dynamic>);
      expect(back, info);
      expect(back.announce, isTrue);
    });

    test('rejects garbage', () {
      expect(DeviceInfo.tryParse(null), isNull);
      expect(DeviceInfo.tryParse({'alias': 'x'}), isNull);
      expect(
        DeviceInfo.tryParse({'alias': 'x', 'fingerprint': 'f', 'port': 99999}),
        isNull,
      );
      expect(
        DeviceInfo.tryParse({'alias': 'x', 'fingerprint': 'f', 'port': 1.5}),
        isNull,
      );
      expect(
        DeviceInfo.tryParse({
          'alias': 'x',
          'fingerprint': 'f',
          'port': 1,
          'deviceModel': <String>[],
        }),
        isNull,
      );
    });

    test('parses LocalSend-style payload', () {
      final ls = {
        'alias': 'Nice Orange',
        'version': '2.0',
        'deviceModel': 'Samsung',
        'deviceType': 'mobile',
        'fingerprint': 'random string',
        'port': 53317,
        'protocol': 'https',
        'download': true,
        'announce': true,
      };
      final info = DeviceInfo.tryParse(ls);
      expect(info, isNotNull);
      expect(info!.deviceType, DeviceType.mobile);
      expect(info.protocol, PeerProtocol.https);
    });
  });

  group('FileDto / PrepareUploadRequest', () {
    test('round-trip', () {
      final req = PrepareUploadRequest(
        info: const DeviceInfo(alias: 'a', fingerprint: 'f', port: 1),
        files: {
          'id1': FileDto(
            id: 'id1',
            fileName: 'photo.jpg',
            size: 1234,
            fileType: 'image/jpeg',
            modified: DateTime.utc(2026, 1, 1),
          ),
        },
        text: 'hello',
      );
      final back = PrepareUploadRequest.tryParse(
        jsonDecode(jsonEncode(req.toJson())),
      );
      expect(back, isNotNull);
      expect(back!.files['id1'], req.files['id1']);
      expect(back.text, 'hello');
      expect(back.files['id1']!.modified, DateTime.utc(2026, 1, 1));
    });

    test('text-only request is valid', () {
      final back = PrepareUploadRequest.tryParse({
        'info': {'alias': 'a', 'fingerprint': 'f', 'port': 1},
        'files': {},
        'text': 'clip',
      });
      expect(back, isNotNull);
      expect(back!.files, isEmpty);
    });

    test('rejects ambiguous or unsafe file metadata', () {
      const info = {'alias': 'a', 'fingerprint': 'f', 'port': 1};
      Map<String, Object?> file({
        Object? id = 'id1',
        Object? name = 'safe.txt',
        Object? size = 1,
        Object? sha,
        Object? preview,
      }) => {
        'id': id,
        'fileName': name,
        'size': size,
        'fileType': 'text/plain',
        'sha256': sha,
        'preview': preview,
      };

      expect(
        PrepareUploadRequest.tryParse({
          'info': info,
          'files': {'different-key': file()},
        }),
        isNull,
      );
      expect(FileDto.tryParse(file(id: '../escape')), isNull);
      expect(FileDto.tryParse(file(size: 1.5)), isNull);
      expect(FileDto.tryParse(file(sha: 'not-a-sha256')), isNull);
      expect(FileDto.tryParse(file(preview: '%%%')), isNull);
    });
  });

  test('AliasGenerator produces two words', () {
    expect(AliasGenerator.generate().split(' ').length, 2);
  });
}
