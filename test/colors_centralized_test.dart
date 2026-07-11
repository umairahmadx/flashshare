import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flashshare/ui/theme.dart';

void main() {
  test('AppColors.brand is blue', () {
    expect(AppColors.brand.value, 0xFF1565FF);
  });

  test('no hard-coded color literals outside lib/ui/theme.dart', () {
    final libDir = Directory('lib');
    final offenders = <String>[];
    final pattern = RegExp(
        r'(?<![A-Za-z0-9_])Colors\.\w+|Color\(0x[0-9A-Fa-f]{6,8}\)|0x[0-9A-Fa-f]{6,8}');
    for (final f in libDir.listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (f.path.replaceAll('\\', '/').endsWith('lib/ui/theme.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (pattern.hasMatch(lines[i])) {
          offenders.add('${f.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'Color literals must live only in lib/ui/theme.dart.\n'
            'Offenders:\n${offenders.join('\n')}');
  });
}
