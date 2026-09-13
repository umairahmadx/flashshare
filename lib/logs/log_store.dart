import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum LogLevel { info, warning, error }

class LogEntry {
  final LogLevel level;
  final String message;
  final String? stack; // stack trace string, errors only
  final int timestamp; // ms since epoch

  LogEntry(
      {required this.level, required this.message, this.stack, required this.timestamp});

  /// What the copy button puts on the clipboard: message plus stack if any.
  String copyText() {
    final ts = DateTime.fromMillisecondsSinceEpoch(timestamp)
        .toIso8601String()
        .substring(0, 19);
    final base = '[$ts][${level.name}] $message';
    return stack == null ? base : '$base\n\nStack trace:\n$stack';
  }

  Map<String, dynamic> toJson() => {
        'level': level.name,
        'message': message,
        'stack': stack,
        'timestamp': timestamp,
      };

  static LogEntry fromJson(Map<String, dynamic> j) => LogEntry(
        level: LogLevel.values.firstWhere((l) => l.name == j['level']),
        message: j['message'] as String,
        stack: j['stack'] as String?,
        timestamp: j['timestamp'] as int,
      );
}

/// App-wide log sink. Singleton so the global error handler in main.dart and
/// the upload engine can log without threading a dependency through
/// everything; persisted (capped) to shared_preferences so crash logs survive
/// an app restart.
class LogStore extends ChangeNotifier {
  static const _kKey = 'logs';
  static const _cap = 200;
  static LogStore? _instance;

  List<LogEntry> _entries;

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

  void info(String message) => _add(LogLevel.info, message);
  void warning(String message) => _add(LogLevel.warning, message);

  void error(String message, {StackTrace? stack}) =>
      _add(LogLevel.error, message, stack: stack?.toString());

  void _add(LogLevel level, String message, {String? stack}) {
    _entries.add(LogEntry(
      level: level,
      message: message,
      stack: stack,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    ));
    if (_entries.length > _cap) {
      _entries = _entries.sublist(_entries.length - _cap);
    }
    notifyListeners();
    _persist();
  }

  void clear() {
    _entries = [];
    notifyListeners();
    _persist();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _kKey, jsonEncode(_entries.map((e) => e.toJson()).toList()));
    } catch (_) {
      // Never let logging failures become errors that would be logged.
    }
  }
}
