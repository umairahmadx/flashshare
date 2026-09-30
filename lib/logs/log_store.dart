import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Severity, ordered lowest to highest. [debug] is the verbose action trace
/// (every tap, filter change, dialog open) that the log screen shows under
/// "Verbose" — always recorded, just quieter by default.
enum LogLevel { debug, info, warning, error }

class LogEntry {
  final LogLevel level;
  final String message;
  final String? stack; // stack trace string, errors only
  final int timestamp; // ms since epoch
  final String? source; // subsystem tag, e.g. 'api', 'upload', 'ui.history'

  LogEntry(
      {required this.level,
      required this.message,
      this.stack,
      required this.timestamp,
      this.source});

  /// What the copy button puts on the clipboard: message plus stack if any.
  String copyText() {
    final ts = DateTime.fromMillisecondsSinceEpoch(timestamp)
        .toIso8601String()
        .substring(0, 19);
    final tag = source == null ? '' : '[$source] ';
    final base = '[$ts][${level.name}] $tag$message';
    return stack == null ? base : '$base\n\nStack trace:\n$stack';
  }

  Map<String, dynamic> toJson() => {
        'level': level.name,
        'message': message,
        'stack': stack,
        'timestamp': timestamp,
        'source': source,
      };

  static LogEntry fromJson(Map<String, dynamic> j) => LogEntry(
        level: LogLevel.values.firstWhere((l) => l.name == j['level'],
            orElse: () => LogLevel.info),
        message: j['message'] as String,
        stack: j['stack'] as String?,
        timestamp: j['timestamp'] as int,
        // Absent on entries written before `source` existed — tolerate it
        // rather than dropping the whole log file.
        source: j['source'] as String?,
      );
}

/// App-wide log sink. Singleton so the global error handler in main.dart and
/// the upload engine can log without threading a dependency through
/// everything; persisted (capped) to shared_preferences so crash logs survive
/// an app restart.
class LogStore extends ChangeNotifier {
  static const _kKey = 'logs';

  /// High enough to hold a full verbose session, low enough that the JSON
  /// blob stays well inside SharedPreferences' comfortable size.
  static const _cap = 1000;
  static LogStore? _instance;

  List<LogEntry> _entries;

  /// Disk-write throttle. Verbose tracing logs many lines per second; writing
  /// the whole JSON on each one would burn I/O and jank the UI. A timestamp
  /// check is used rather than a Timer on purpose — a Timer outlives a
  /// widget-test body and makes the suite flaky, and the app flushes on pause
  /// anyway, so nothing is lost.
  static const _writeIntervalMs = 1000;
  int _lastWriteMs = 0;

  LogStore._(this._entries);

  static Future<LogStore> create() async {
    if (_instance != null) return _instance!;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kKey);
    var entries = <LogEntry>[];
    if (raw != null) {
      try {
        entries = ((jsonDecode(raw) as List)
                .map((e) => LogEntry.fromJson(e as Map<String, dynamic>)))
            .toList();
      } catch (_) {
        // Corrupted log data is not worth crashing for; start clean.
      }
    }
    return _instance = LogStore._(entries);
  }

  /// Test-only: drop the singleton so a fresh store can be created per test.
  static void resetForTest() => _instance = null;

  /// Sync access for call sites that can't await [create] (e.g. the global
  /// error handler). Null until the store is first created.
  static LogStore? get instanceOrNull => _instance;

  List<LogEntry> get entries => List.unmodifiable(_entries);

  void info(String message, {String? source}) =>
      _add(LogLevel.info, message, source: source);
  void warning(String message, {String? source}) =>
      _add(LogLevel.warning, message, source: source);

  /// Verbose action trace. Recorded always — the log screen filters it.
  void debug(String message, {String? source}) =>
      _add(LogLevel.debug, message, source: source);

  void error(String message, {StackTrace? stack, String? source}) =>
      _add(LogLevel.error, message, stack: stack?.toString(), source: source);

  /// Bridge for FlutterError.onError — anything the framework catches (build
  /// errors, layout overflow, bad assertions) lands here with its stack.
  void recordFlutterError(FlutterErrorDetails details, {String? context}) {
    final prefix = context == null ? '' : '$context: ';
    _add(LogLevel.error, '$prefix${details.exceptionAsString()}',
        stack: details.stack?.toString(), source: 'flutter');
  }

  void _add(LogLevel level, String message, {String? stack, String? source}) {
    _entries.add(LogEntry(
      level: level,
      message: message,
      stack: stack,
      source: source,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    ));
    if (_entries.length > _cap) {
      _entries = _entries.sublist(_entries.length - _cap);
    }
    notifyListeners();
    _schedulePersist();
    // Mirror to the console so `flutter run` output and the in-app log agree.
    if (kDebugMode) {
      debugPrint('[${level.name}] ${source ?? '-'} $message');
    }
  }

  void clear() {
    _entries = [];
    notifyListeners();
    unawaited(_persist());
  }

  void _schedulePersist() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastWriteMs >= _writeIntervalMs) unawaited(_persist());
    // Inside the interval the line is simply carried by the next write — the
    // app also flushes on lifecycle pause, so nothing is lost.
  }

  /// Write pending entries to disk now (tests, app shutdown).
  Future<void> flush() => _persist();

  Future<void> _persist() async {
    try {
      _lastWriteMs = DateTime.now().millisecondsSinceEpoch;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _kKey, jsonEncode(_entries.map((e) => e.toJson()).toList()));
    } catch (_) {
      // Never let logging failures become errors that would be logged. The
      // console still sees it, so a broken store isn't invisible in debug.
      if (kDebugMode) debugPrint('LogStore: persistence failed');
    }
  }
}

/// Zero-dependency logging facade for UI code.
///
/// Widgets call these without holding a LogStore reference; before the store
/// exists they are silent no-ops and never throw.
class AppLog {
  static LogStore? get _store => LogStore.instanceOrNull;

  static void debug(String message, {String? source}) =>
      _store?.debug(message, source: source);
  static void info(String message, {String? source}) =>
      _store?.info(message, source: source);
  static void warning(String message, {String? source}) =>
      _store?.warning(message, source: source);
  static void error(String message, {StackTrace? stack, String? source}) =>
      _store?.error(message, stack: stack, source: source);
}

