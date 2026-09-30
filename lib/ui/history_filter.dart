import 'package:flashshare/models.dart';

/// Which kind of share to show.
enum HistoryKindFilter { all, files, collections }

/// Order of the resulting list.
enum HistorySort { newest, oldest, largest, expiringSoon }

/// A count + byte total used by the History header metrics.
class HistoryCount {
  final int count;
  final int bytes;
  const HistoryCount(this.count, this.bytes);
}

/// A snapshot of the header metrics for one list.
class HistoryStats {
  final HistoryCount all;
  final HistoryCount files;
  final HistoryCount collections;
  final int active;
  final int expired;

  const HistoryStats({
    required this.all,
    required this.files,
    required this.collections,
    required this.active,
    required this.expired,
  });

  static const HistoryStats empty = HistoryStats(
    all: HistoryCount(0, 0),
    files: HistoryCount(0, 0),
    collections: HistoryCount(0, 0),
    active: 0,
    expired: 0,
  );
}

/// Search, filter, sort and expiry logic for the History screen.
///
/// Deliberately pure Dart (no Flutter import) so the rules are unit-testable
/// without pumping a widget, and so the screen stays a thin view.
class HistoryFilter {
  /// Extension → category key. Keys match [AppColors.fileCategories] so the UI
  /// can go from a filter chip straight to an icon.
  static const Map<String, List<String>> _extensions = {
    'image': ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'heic', 'heif', 'svg'],
    'video': ['mp4', 'mov', 'webm', 'avi', 'mkv', 'm4v'],
    'audio': ['mp3', 'wav', 'ogg', 'm4a', 'flac', 'aac'],
    'pdf': ['pdf'],
    'doc': ['doc', 'docx', 'rtf', 'odt', 'pages'],
    'sheet': ['xls', 'xlsx', 'csv', 'numbers'],
    'slide': ['ppt', 'pptx', 'key'],
    'archive': ['zip', 'rar', '7z', 'tar', 'gz'],
    'text': ['txt', 'md', 'json', 'xml', 'yaml', 'yml', 'log'],
    'app': ['apk', 'exe', 'dmg', 'deb', 'msi', 'ipa'],
  };

  /// Chip order for the category row; 'all' is prepended by the UI.
  static const List<String> categoryOrder = [
    'image', 'video', 'audio', 'pdf', 'doc',
    'sheet', 'slide', 'archive', 'text', 'app',
  ];

  static String _extOf(String filename) {
    final dot = filename.lastIndexOf('.');
    if (dot <= 0 || dot == filename.length - 1) return '';
    return filename.substring(dot + 1).toLowerCase();
  }

  /// Category key for a filename ('default' when nothing matches).
  static String categoryOf(String filename) {
    final ext = _extOf(filename);
    if (ext.isEmpty) return 'default';
    for (final entry in _extensions.entries) {
      if (entry.value.contains(ext)) return entry.key;
    }
    return 'default';
  }

  static DateTime? expiryOf(HistoryEntry e) =>
      e.expiresAt == null ? null : DateTime.tryParse(e.expiresAt!);

  /// An entry whose instant is exactly `now` counts as expired — it matches
  /// [expiryLabel], which already prints "Expired" at that moment.
  static bool isExpired(HistoryEntry e, {DateTime? now}) {
    final at = expiryOf(e);
    return at != null && !at.isAfter(now ?? DateTime.now());
  }

  /// Search matches the filename (case-insensitive, trimmed); a collection's
  /// generated name rarely matches anything, so its id is searched too.
  static bool _matchesSearch(HistoryEntry e, String q) {
    final needle = q.trim().toLowerCase();
    if (needle.isEmpty) return true;
    return e.filename.toLowerCase().contains(needle) ||
        e.id.toLowerCase().contains(needle);
  }


  /// The full pipeline: search → kind → category → expired → sort.
  ///
  /// [hideExpired] drops entries whose expiry already passed; expired shares
  /// stay visible by default, because hiding them would conceal the fact that
  /// a link stopped working.
  static List<HistoryEntry> apply(
    List<HistoryEntry> entries, {
    String query = '',
    HistoryKindFilter kind = HistoryKindFilter.all,
    String? category,
    HistorySort sort = HistorySort.newest,
    bool hideExpired = false,
    DateTime? now,
  }) {
    final reference = now ?? DateTime.now();
    final result = entries.where((e) {
      if (!_matchesSearch(e, query)) return false;
      switch (kind) {
        case HistoryKindFilter.files:
          if (e.kind != 'file') return false;
        case HistoryKindFilter.collections:
          if (e.kind != 'collection') return false;
        case HistoryKindFilter.all:
          break;
      }
      if (category != null && category != 'all') {
        // A collection is a bundle of mixed types — it is never "an image".
        if (e.kind == 'collection') return false;
        if (categoryOf(e.filename) != category) return false;
      }
      if (hideExpired && isExpired(e, now: reference)) return false;
      return true;
    }).toList();

    switch (sort) {
      case HistorySort.newest:
        result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case HistorySort.oldest:
        result.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      case HistorySort.largest:
        result.sort((a, b) => b.size.compareTo(a.size));
      case HistorySort.expiringSoon:
        // No expiry date sorts last: it is the least urgent thing in the list.
        result.sort((a, b) {
          final ea = expiryOf(a);
          final eb = expiryOf(b);
          if (ea == null && eb == null) {
            return b.createdAt.compareTo(a.createdAt);
          }
          if (ea == null) return 1;
          if (eb == null) return -1;
          return ea.compareTo(eb);
        });
    }
    return result;
  }

  /// Metrics for the header, computed over the list it is given so the numbers
  /// always describe what is on screen.
  static HistoryStats summarize(List<HistoryEntry> entries, {DateTime? now}) {
    if (entries.isEmpty) return HistoryStats.empty;
    final reference = now ?? DateTime.now();
    var fileCount = 0, collCount = 0, fileBytes = 0, collBytes = 0;
    var active = 0, expired = 0;
    for (final e in entries) {
      if (e.kind == 'file') {
        fileCount++;
        fileBytes += e.size;
      } else {
        collCount++;
        collBytes += e.size;
      }
      if (isExpired(e, now: reference)) {
        expired++;
      } else {
        active++;
      }
    }
    return HistoryStats(
      all: HistoryCount(entries.length, fileBytes + collBytes),
      files: HistoryCount(fileCount, fileBytes),
      collections: HistoryCount(collCount, collBytes),
      active: active,
      expired: expired,
    );
  }

  /// "Expires in 3 d" / "Expired" / null when the server gave no date.
  ///
  /// Day-granular on purpose: the API only accepts whole days for expiry, so
  /// finer precision would be fabricated.
  static String? expiryLabel(HistoryEntry e, {DateTime? now}) =>
      describeExpiry(e.expiresAt, now: now);

  /// The same sentence from a raw ISO timestamp — the single implementation
  /// both [expiryLabel] and `expiryText` share.
  static String? describeExpiry(String? iso, {DateTime? now}) {
    if (iso == null) return null;
    final at = DateTime.tryParse(iso);
    if (at == null) return null;
    final reference = now ?? DateTime.now();
    if (!at.isAfter(reference)) return 'Expired';
    final days = at.difference(reference).inDays;
    if (days == 0) return 'Expires today';
    return 'Expires in $days d';
  }

  /// "Today" / "Yesterday" / "4 d ago" / "3 w ago" for the row subtitle.
  static String ageLabel(int createdAtMs, {DateTime? now}) {
    final created = DateTime.fromMillisecondsSinceEpoch(createdAtMs);
    final diff = (now ?? DateTime.now()).difference(created);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 14) return '${diff.inDays} d ago';
    if (diff.inDays < 60) return '${diff.inDays ~/ 7} w ago';
    return '${diff.inDays ~/ 30} mo ago';
  }
}

