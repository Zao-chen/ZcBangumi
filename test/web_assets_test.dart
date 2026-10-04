import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('web fonts and their license are included in the project', () async {
    for (final font in ['Chinese', 'Latin']) {
      final bytes = await File(
        'assets/fonts/NotoSansSC-$font.woff2',
      ).readAsBytes();
      expect(ascii.decode(bytes.take(4).toList()), 'wOF2');
      expect(bytes.length, greaterThan(10000));
    }
    expect(
      await File('assets/fonts/OFL.txt').readAsString(),
      contains('SIL OPEN FONT LICENSE'),
    );
    final manifest = await File('pubspec.yaml').readAsString();
    expect(manifest, contains('assets/fonts/NotoSansSC-Chinese.woff2'));
    expect(manifest, contains('assets/fonts/NotoSansSC-Latin.woff2'));
    expect(manifest, contains('assets/fonts/OFL.txt'));
  });
}
