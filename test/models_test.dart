import 'package:flutter_test/flutter_test.dart';
import 'package:flashshare/models.dart';

void main() {
  test('guessContentType maps common extensions', () {
    expect(guessContentType('a.pdf'), 'application/pdf');
    expect(guessContentType('b.PNG'), 'image/png');
    expect(guessContentType('c.mp4'), 'video/mp4');
    expect(guessContentType('d.unknown'), 'application/octet-stream');
  });
}
