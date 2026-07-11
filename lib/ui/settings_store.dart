import 'package:shared_preferences/shared_preferences.dart';

const _kThemeMode = 'theme_mode'; // 'system' | 'light' | 'dark'

class SettingsStore {
  final SharedPreferences _prefs;
  SettingsStore(this._prefs);

  static Future<SettingsStore> create() async =>
      SettingsStore(await SharedPreferences.getInstance());

  String get themeMode => _prefs.getString(_kThemeMode) ?? 'system';

  Future<void> setThemeMode(String mode) async =>
      _prefs.setString(_kThemeMode, mode);
}
