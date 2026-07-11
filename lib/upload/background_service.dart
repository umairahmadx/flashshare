import 'package:flutter_background_service/flutter_background_service.dart';

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

void _onStart(ServiceInstance service) {
  // Engine runs in the same isolate (started from main); this keeps the
  // isolate alive while the persistent notification is shown.
  if (service is AndroidServiceInstance) {
    service.on('stop').listen((_) => service.stopSelf());
  }
}

Future<void> startUploadService() => FlutterBackgroundService().startService();

void stopUploadService() => FlutterBackgroundService().invoke('stop');
