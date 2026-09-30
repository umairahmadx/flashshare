import 'package:flutter_test/flutter_test.dart';
import 'package:flashshare/models.dart';
import 'package:flashshare/ui/history_filter.dart';

/// Fixed "now" so expiry math is deterministic.
final _now = DateTime.utc(2026, 7, 11, 12);

HistoryEntry _e({
  String id = 'id',
  String filename = 'file.bin',
  int size = 100,
  String kind = 'file',
  String? expiresAt,
  int? createdAt,
  bool locked = false,
}) =>
    HistoryEntry(
      id: id,
      url: 'https://storage.to/dl/$id',
      filename: filename,
      size: size,
      expiresAt: expiresAt,
      ownerToken: 'tok',
      kind: kind,
      createdAt: createdAt ?? _now.millisecondsSinceEpoch,
      locked: locked,
    );

String? _daysFromNow(int days) =>
    _now.add(Duration(days: days)).toIso8601String();

void main() {
  group('categoryOf', () {
    test('maps extensions to category keys', () {
      expect(HistoryFilter.categoryOf('photo.JPG'), 'image');
      expect(HistoryFilter.categoryOf('clip.mp4'), 'video');
      expect(HistoryFilter.categoryOf('song.mp3'), 'audio');
      expect(HistoryFilter.categoryOf('report.pdf'), 'pdf');
      expect(HistoryFilter.categoryOf('notes.md'), 'text');
      expect(HistoryFilter.categoryOf('app.apk'), 'app');
      expect(HistoryFilter.categoryOf('backup.zip'), 'archive');
    });

    test('falls back to default for unknown, dotted or extensionless names',
        () {
      expect(HistoryFilter.categoryOf('mystery.xyz'), 'default');
      expect(HistoryFilter.categoryOf('archive.tar.gz'), 'archive');
      expect(HistoryFilter.categoryOf('LICENSE'), 'default');
      expect(HistoryFilter.categoryOf('.hidden'), 'default');
      expect(HistoryFilter.categoryOf('trailing.'), 'default');
    });
  });

  group('apply — search', () {
    final entries = [
      _e(id: 'a', filename: 'Holiday-Photo.jpg'),
      _e(id: 'b', filename: 'invoice.pdf'),
    ];

    test('is case-insensitive and trims whitespace', () {
      expect(HistoryFilter.apply(entries, query: '  holiday ').map((e) => e.id),
          ['a']);
      expect(HistoryFilter.apply(entries, query: 'INVOICE').map((e) => e.id),
          ['b']);
    });

    test('empty and whitespace-only queries return everything', () {
      expect(HistoryFilter.apply(entries, query: ''), hasLength(2));
      expect(HistoryFilter.apply(entries, query: '   '), hasLength(2));
    });

    test('matches a collection by id, since its name is generated', () {
      final coll = [
        _e(id: 'coll-42', filename: 'Collection', kind: 'collection'),
      ];
      expect(HistoryFilter.apply(coll, query: 'coll-42'), hasLength(1));
      expect(HistoryFilter.apply(coll, query: 'nothing'), isEmpty);
    });
  });

  group('apply — kind and category', () {
    final entries = [
      _e(id: 'img', filename: 'a.jpg'),
      _e(id: 'vid', filename: 'b.mp4'),
      _e(id: 'coll', filename: 'Collection', kind: 'collection'),
    ];

    test('kind filter keeps only that kind', () {
      expect(
          HistoryFilter.apply(entries, kind: HistoryKindFilter.files)
              .map((e) => e.id),
          ['img', 'vid']);
      expect(
          HistoryFilter.apply(entries, kind: HistoryKindFilter.collections)
              .map((e) => e.id),
          ['coll']);
    });

    test('category filter narrows files and never matches collections', () {
      expect(HistoryFilter.apply(entries, category: 'image').map((e) => e.id),
          ['img']);
      expect(
          HistoryFilter.apply(entries,
                  kind: HistoryKindFilter.collections, category: 'image'),
          isEmpty);
    });

    test("'all' category is a no-op", () {
      expect(HistoryFilter.apply(entries, category: 'all'), hasLength(3));
    });
  });

  group('apply — expiry', () {
    final entries = [
      _e(id: 'live', filename: 'live.jpg', expiresAt: _daysFromNow(2)),
      _e(id: 'dead', filename: 'dead.jpg', expiresAt: _daysFromNow(-1)),
      _e(id: 'forever', filename: 'forever.jpg'),
    ];

    test('expired entries stay visible by default', () {
      expect(HistoryFilter.apply(entries, now: _now).map((e) => e.id),
          contains('dead'));
    });

    test('hideExpired drops them but keeps undated shares', () {
      expect(
          HistoryFilter.apply(entries, now: _now, hideExpired: true)
              .map((e) => e.id),
          ['live', 'forever']);
    });

    test('an entry expiring exactly now counts as expired', () {
      expect(
          HistoryFilter.isExpired(_e(expiresAt: _now.toIso8601String()),
              now: _now),
          isTrue);
    });
  });

  group('apply — sort', () {
    final entries = [
      _e(
          id: 'old',
          createdAt:
              _now.subtract(const Duration(days: 5)).millisecondsSinceEpoch),
      _e(id: 'new', createdAt: _now.millisecondsSinceEpoch, size: 10),
      _e(
          id: 'mid',
          createdAt:
              _now.subtract(const Duration(days: 2)).millisecondsSinceEpoch,
          size: 900),
    ];

    test('newest / oldest / largest', () {
      expect(
          HistoryFilter.apply(entries, sort: HistorySort.newest)
              .map((e) => e.id),
          ['new', 'mid', 'old']);
      expect(
          HistoryFilter.apply(entries, sort: HistorySort.oldest)
              .map((e) => e.id),
          ['old', 'mid', 'new']);
      expect(
          HistoryFilter.apply(entries, sort: HistorySort.largest)
              .map((e) => e.id),
          ['mid', 'old', 'new']);
    });

    test('expiringSoon puts the soonest date first and undated last', () {
      final withDates = [
        _e(id: 'none', filename: 'a.txt'),
        _e(id: 'soon', filename: 'b.txt', expiresAt: _daysFromNow(1)),
        _e(id: 'later', filename: 'c.txt', expiresAt: _daysFromNow(6)),
      ];
      expect(
          HistoryFilter.apply(withDates,
                  sort: HistorySort.expiringSoon, now: _now)
              .map((e) => e.id),
          ['soon', 'later', 'none']);
    });
  });

  group('summarize', () {
    test('counts, bytes and expiry split are correct', () {
      final entries = [
        _e(filename: 'a.jpg', size: 500, expiresAt: _daysFromNow(3)),
        _e(filename: 'b.mp4', size: 1500, expiresAt: _daysFromNow(-2)),
        _e(filename: 'Bundle', size: 2000, kind: 'collection'),
      ];
      final s = HistoryFilter.summarize(entries, now: _now);
      expect(s.all.count, 3);
      expect(s.all.bytes, 4000);
      expect(s.files.count, 2);
      expect(s.files.bytes, 2000);
      expect(s.collections.count, 1);
      expect(s.active, 2);
      expect(s.expired, 1);
    });

    test('empty list yields zeroed stats', () {
      expect(HistoryFilter.summarize([]).all.count, 0);
    });
  });

  group('labels', () {
    test('expiryLabel is day-granular and honest about the past', () {
      expect(
          HistoryFilter.expiryLabel(_e(expiresAt: _daysFromNow(4)), now: _now),
          'Expires in 4 d');
      expect(
          HistoryFilter.expiryLabel(
              _e(expiresAt: _now.add(const Duration(hours: 5)).toIso8601String()),
              now: _now),
          'Expires today');
      expect(
          HistoryFilter.expiryLabel(_e(expiresAt: _daysFromNow(-4)), now: _now),
          'Expired');
      expect(HistoryFilter.expiryLabel(_e(), now: _now), isNull);
    });

    test('ageLabel buckets days into d / w / mo', () {
      String label(int daysAgo) => HistoryFilter.ageLabel(
          _now.subtract(Duration(days: daysAgo)).millisecondsSinceEpoch,
          now: _now);
      expect(label(0), 'Today');
      expect(label(1), 'Yesterday');
      expect(label(6), '6 d ago');
      expect(label(21), '3 w ago');
      expect(label(90), '3 mo ago');
    });
  });
}

