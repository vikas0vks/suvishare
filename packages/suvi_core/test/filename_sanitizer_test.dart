import 'package:suvi_core/suvi_core.dart';
import 'package:test/test.dart';

void main() {
  group('FilenameSanitizer', () {
    test('strips directories on both separators', () {
      expect(FilenameSanitizer.sanitize('../../etc/passwd'), 'passwd');
      expect(FilenameSanitizer.sanitize(r'..\..\Windows\win.ini'), 'win.ini');
      expect(FilenameSanitizer.sanitize('/abs/path/a.txt'), 'a.txt');
    });

    test('replaces illegal characters', () {
      expect(
        FilenameSanitizer.sanitize('a:b*c?d"e<f>g|h.txt'),
        'a_b_c_d_e_f_g_h.txt',
      );
      expect(FilenameSanitizer.sanitize('bad\x00name.txt'), 'bad_name.txt');
    });

    test('handles empty / dot names', () {
      expect(FilenameSanitizer.sanitize(''), 'file');
      expect(FilenameSanitizer.sanitize('.'), 'file');
      expect(FilenameSanitizer.sanitize('..'), 'file');
      expect(FilenameSanitizer.sanitize('   '), 'file');
    });

    test('prefixes Windows reserved names', () {
      expect(FilenameSanitizer.sanitize('CON'), '_CON');
      expect(FilenameSanitizer.sanitize('com1.txt'), '_com1.txt');
      expect(FilenameSanitizer.sanitize('console.txt'), 'console.txt');
    });

    test('trims trailing dots and spaces', () {
      expect(FilenameSanitizer.sanitize('report.pdf. . '), 'report.pdf');
    });

    test('caps length but keeps extension', () {
      final long = '${'a' * 300}.jpg';
      final s = FilenameSanitizer.sanitize(long);
      expect(s.length, lessThanOrEqualTo(200));
      expect(s.endsWith('.jpg'), isTrue);
    });

    test('isInside', () {
      expect(
        FilenameSanitizer.isInside('/tmp/save', '/tmp/save/a.txt'),
        isTrue,
      );
      expect(
        FilenameSanitizer.isInside('/tmp/save', '/tmp/save/../x.txt'),
        isFalse,
      );
    });
  });
}
