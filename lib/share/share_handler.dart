import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:flashshare/files/app_file.dart';
import 'package:flashshare/logs/log_store.dart';

class ShareHandler {
  final void Function(List<AppFile>) onFiles;
  StreamSubscription? _sub;

  ShareHandler(this.onFiles);

  void _handle(List<SharedMediaFile> media) {
    // The plugin stuffs shared *text* and *urls* into `path` too — those are
    // not files and must not be "uploaded" as garbage 0-byte files. A text
    // share's `path` is the string itself, which never exists on disk.
    final paths = media
        .where((m) => m.type != SharedMediaType.text && m.type != SharedMediaType.url)
        .map((m) => m.path)
        .where(fileExists)
        .toList();
    if (paths.isNotEmpty) {
      onFiles(paths.map(fileFromPath).toList());
    }
  }

  void init() {
    // receive_sharing_intent has no web implementation; the web share target is
    // not wired up yet, so do nothing there.
    if (kIsWeb) return;
    _sub = ReceiveSharingIntent.instance.getMediaStream().listen(_handle,
        onError: (Object e) {
      // A malformed share must not escape to the app-wide error handler
      // (which would toast "Something went wrong" and, in debug, crash).
      LogStore.instanceOrNull?.warning('Incoming share dropped: $e');
    });
    ReceiveSharingIntent.instance.getInitialMedia().then((files) {
      _handle(files);
      // Plugin contract: consuming the initial media requires reset(),
      // otherwise the last SEND intent replays on the next app start.
      ReceiveSharingIntent.instance.reset();
    }, onError: (Object e) {
      LogStore.instanceOrNull?.warning('Initial share dropped: $e');
    });
  }

  void dispose() => _sub?.cancel();
}
