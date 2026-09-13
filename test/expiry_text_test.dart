import 'package:flutter_test/flutter_test.dart';
import 'package:flashshare/ui/upload_tile.dart' show expiryText;

void main() {
  test('expiry: already-expired shows "Expired", not "Expires today"', () {
    final past = DateTime.now().subtract(const Duration(hours: 2)).toIso8601String();
    expect(expiryText(past), 'Expired');
  });

  test('expiry: later today shows "Expires today"', () {
    final soon = DateTime.now().add(const Duration(hours: 2)).toIso8601String();
    expect(expiryText(soon), 'Expires today');
  });

  test('expiry: 3 days out shows "Expires in 3 d"', () {
    final d = DateTime.now().add(const Duration(days: 3, hours: 1)).toIso8601String();
    expect(expiryText(d), 'Expires in 3 d');
  });

  test('expiry: null and unparseable values show nothing', () {
    expect(expiryText(null), isNull);
    expect(expiryText('not a date'), isNull);
  });
}
