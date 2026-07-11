import 'dart:async';
import 'dart:io';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

class ShareHandler {
  final void Function(List<File>) onFiles;
  StreamSubscription? _sub;

  ShareHandler(this.onFiles);

  void init() {
    _sub = ReceiveSharingIntent.instance.getMediaStream().listen((files) {
      if (files.isNotEmpty) {
        onFiles(files.map((m) => File(m.path)).toList());
      }
    });
    ReceiveSharingIntent.instance.getInitialMedia().then((files) {
      if (files.isNotEmpty) {
        onFiles(files.map((m) => File(m.path)).toList());
      }
    });
  }

  void dispose() => _sub?.cancel();
}
