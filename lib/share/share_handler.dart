import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:flashshare/files/app_file.dart';

class ShareHandler {
  final void Function(List<AppFile>) onFiles;
  StreamSubscription? _sub;

  ShareHandler(this.onFiles);

  void init() {
    // receive_sharing_intent has no web implementation; the web share target is
    // not wired up yet, so do nothing there.
    if (kIsWeb) return;
    _sub = ReceiveSharingIntent.instance.getMediaStream().listen((files) {
      if (files.isNotEmpty) {
        onFiles(files.map((m) => fileFromPath(m.path)).toList());
      }
    });
    ReceiveSharingIntent.instance.getInitialMedia().then((files) {
      if (files.isNotEmpty) {
        onFiles(files.map((m) => fileFromPath(m.path)).toList());
      }
    });
  }

  void dispose() => _sub?.cancel();
}
