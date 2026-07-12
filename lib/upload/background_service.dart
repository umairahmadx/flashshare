import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io' show Platform;

const _notificationChannelId = 'flashshare_uploads';

/// Configure the Android foreground service. Call once at startup (main).
Future<void> configureBackgroundService() async {
  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: _onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: _notificationChannelId,
      initialNotificationTitle: 'Flash Share',
      initialNotificationContent: 'Uploading files…',
      foregroundServiceTypes: [AndroidForegroundType.dataSync],
    ),
    iosConfiguration: IosConfiguration(autoStart: false),
  );
}

/// This callback is launched by Android in a separate Dart isolate. Keep it as
/// an entry point so it is retained in release builds when the service starts.
@pragma('vm:entry-point')
void _onStart(ServiceInstance service) {
  // UploadEngine remains in the app isolate. This separate foreground-service
  // isolate exists only to keep the upload notification/service lifecycle up.
  if (service is AndroidServiceInstance) {
    service.on('stop').listen((_) => service.stopSelf());
  }
}

/// Starts the foreground service. Best-effort: any failure (e.g. notification
/// permission not granted, service already running) must NOT propagate — this
/// is called before enqueue and from the idle callback, so a throw there would
/// escape a `finally` and crash the app.
Future<void> startUploadService() async {
  try {
    // On Android 13+ (API 33), POST_NOTIFICATIONS is a runtime permission
    // required to show the foreground service notification. Request it first.
    if (Platform.isAndroid) {
      final status = await Permission.notification.request();
      if (!status.isGranted) {
        // Permission denied — skip the foreground service, uploads will still
        // run on the UI isolate without the persistent notification.
        return;
      }
    }
    await FlutterBackgroundService().startService();
  } catch (_) {
    // ignore — uploads still run on the UI isolate without the notification.
  }
}

/// Stops the foreground service. Must never throw: it's invoked from
/// `UploadEngine.onIdle`, which runs inside a `finally` block, so any exception
/// here would escape the upload and terminate the process.
void stopUploadService() {
  try {
    FlutterBackgroundService().invoke('stop');
  } catch (_) {
    // ignore — service may already be stopped or never started.
  }
}
