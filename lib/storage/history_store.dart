import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flashshare/models.dart';

class HistoryStore {
  static const _kToken = 'visitor_token';
  static const _kHistory = 'history';
  final SharedPreferences _prefs;

  HistoryStore(this._prefs);

  static Future<HistoryStore> create() async {
    return HistoryStore(await SharedPreferences.getInstance());
  }

  Future<String> getVisitorToken() async {
    var t = _prefs.getString(_kToken);
    if (t == null) {
      t = _genToken();
      await _prefs.setString(_kToken, t);
    }
    return t;
  }

  List<HistoryEntry> getAll() {
    final raw = _prefs.getString(_kHistory);
    if (raw == null) return [];
    try {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      return list.map(HistoryEntry.fromJson).toList();
    } catch (_) {
      // Corrupted prefs shouldn't crash the UI; start clean.
      return [];
    }
  }

  Future<void> add(HistoryEntry e) async {
    final all = getAll();
    all.insert(0, e);
    await _prefs.setString(
        _kHistory, jsonEncode(all.map((x) => x.toJson()).toList()));
  }

  Future<void> remove(String id) async {
    final all = getAll().where((e) => e.id != id).toList();
    await _prefs.setString(
        _kHistory, jsonEncode(all.map((x) => x.toJson()).toList()));
  }

  // ponytail: non-crypto random; fine as an anonymous quota id, not a secret.
  String _genToken() {
    final rnd = Random();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    final ts = DateTime.now().millisecondsSinceEpoch;
    return base64Url.encode([...bytes, ...utf8.encode(ts.toString())]);
  }
}
