import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flashshare/api/storage_client.dart';
import 'package:flashshare/storage/history_store.dart';
import 'package:flashshare/ui/home_page.dart';
import 'package:flashshare/ui/settings_store.dart';
import 'package:flashshare/ui/theme.dart';
import 'package:flashshare/upload/background_service.dart';
import 'package:flashshare/upload/upload_engine.dart';

ThemeMode _modeFrom(String s) =>
    switch (s) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await HistoryStore.create();
  final settings = await SettingsStore.create();
  final token = await store.getVisitorToken();
  final apiDio = Dio(BaseOptions(
    baseUrl: 'https://storage.to/api',
    validateStatus: (_) => true,
  ));
  final client = HttpStorageClient(apiDio, token);
  final r2Dio = Dio(BaseOptions(validateStatus: (_) => true));
  final engine = UploadEngine(client, store, r2Dio);
  await configureBackgroundService();
  engine.onIdle = stopUploadService;
  final initialMode = _modeFrom(settings.themeMode);
  runApp(FlashShareApp(
    store: store,
    settings: settings,
    engine: engine,
    initialMode: initialMode,
  ));
}

class FlashShareApp extends StatefulWidget {
  final HistoryStore store;
  final SettingsStore settings;
  final UploadEngine engine;
  final ThemeMode initialMode;
  const FlashShareApp(
      {super.key,
      required this.store,
      required this.settings,
      required this.engine,
      required this.initialMode});

  @override
  State<FlashShareApp> createState() => _FlashShareAppState();
}

class _FlashShareAppState extends State<FlashShareApp> {
  late ThemeMode _mode;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
  }

  void _setMode(ThemeMode mode) => setState(() => _mode = mode);

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Flash Share',
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: _mode,
        home: HomePage(
          store: widget.store,
          settings: widget.settings,
          engine: widget.engine,
          onThemeMode: _setMode,
        ),
      );
}
