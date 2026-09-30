import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:flashshare/api/logging_interceptor.dart';
import 'package:flashshare/api/storage_client.dart';
import 'package:flashshare/logs/log_store.dart';
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

// Global backstop: an uncaught error in a release build otherwise terminates
// the whole process (the "app exits to home screen" symptom). Report it and
// keep the app alive instead. Everything lands in the in-app log screen too.
void _reportError(Object error, StackTrace? stack) {
  LogStore.instanceOrNull?.error('Unhandled: $error', stack: stack, source: 'app');
  Fluttertoast.showToast(
    msg: 'Something went wrong: $error',
    toastLength: Toast.LENGTH_LONG,
    gravity: ToastGravity.BOTTOM,
  );
  // ignore: avoid_print
  print('[flashshare] uncaught error: $error\n$stack');
}

void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();

    // Catch framework errors (e.g. during build/layout) with their full
    // details, so an overflow or a bad setState is readable in the log screen.
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      LogStore.instanceOrNull
          ?.recordFlutterError(details, context: details.context?.toDescription());
      _reportError(details.exception, details.stack);
    };
    // Catch async/zone errors that escape everything else.
    PlatformDispatcher.instance.onError = (error, stack) {
      _reportError(error, stack);
      return true; // handled — do not terminate the app.
    };

    // Startup failures (bad prefs, plugin init) must surface, not vanish
    // into an unhandled future that leaves a black screen.
    _startApp();
  }, _reportError);
}

Future<void> _startApp() async {
  // The log is created first: a startup failure in prefs or a plugin is exactly
  // the kind of bug that would otherwise be invisible (a black screen, no log).
  final logs = await LogStore.create();
  try {
    final store = await HistoryStore.create();
    final settings = await SettingsStore.create();
    final token = await store.getVisitorToken();
    final initialMode = _modeFrom(settings.themeMode);
    logs.info(
      'App started — ${kIsWeb ? 'web' : defaultTargetPlatform.name}, '
      'theme=${initialMode.name}, history=${store.getAll().length}',
      source: 'app',
    );
    final apiDio = Dio(BaseOptions(
      baseUrl: 'https://storage.to/api',
      validateStatus: (_) => true,
    ))..interceptors.add(LogStoreInterceptor(source: 'api'));
    final client = HttpStorageClient(apiDio, token);
    // R2 gets the interceptor too: a failed PUT to a presigned URL is the most
    // common upload failure and used to be invisible in the log.
    final r2Dio = Dio(BaseOptions(validateStatus: (_) => true))
      ..interceptors.add(LogStoreInterceptor(source: 'r2'));
    final engine = UploadEngine(client, store, r2Dio);
    await configureBackgroundService();
    engine.onIdle = stopUploadService;
    runApp(FlashShareApp(
      store: store,
      settings: settings,
      engine: engine,
      logs: logs,
      initialMode: initialMode,
    ));
  } catch (e, st) {
    logs.error('Startup failed: $e', stack: st, source: 'app');
    FlutterError.onError?.call(
        FlutterErrorDetails(exception: e, stack: st, library: 'flashshare startup'));
    _reportError(e, st);
  }
}

class FlashShareApp extends StatefulWidget {
  final HistoryStore store;
  final SettingsStore settings;
  final UploadEngine engine;
  final LogStore logs;
  final ThemeMode initialMode;
  const FlashShareApp(
      {super.key,
      required this.store,
      required this.settings,
      required this.engine,
      required this.logs,
      required this.initialMode});

  @override
  State<FlashShareApp> createState() => _FlashShareAppState();
}

class _FlashShareAppState extends State<FlashShareApp>
    with WidgetsBindingObserver {
  late ThemeMode _mode;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Lifecycle transitions are where "it closed itself" bugs live — record them.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    AppLog.debug('lifecycle → ${state.name}', source: 'app');
    if (state == AppLifecycleState.paused) unawaited(widget.logs.flush());
  }

  void _setMode(ThemeMode mode) {
    AppLog.info('Theme mode → ${mode.name}', source: 'ui.settings');
    setState(() => _mode = mode);
  }

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
          logs: widget.logs,
          onThemeMode: _setMode,
        ),
      );
}
