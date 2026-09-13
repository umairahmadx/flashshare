import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:flashshare/files/app_file.dart';
import 'package:flashshare/share/share_handler.dart';

void main() {
  setUp(() {
    ReceiveSharingIntent.setMockValues(
      initialMedia: [],
      mediaStream: const Stream.empty(),
    );
  });

  test('only real files are enqueued, text and url shares are dropped',
      () async {
    final real = File(
        '${Directory.systemTemp.path}/flashshare_share_test.jpg');
    await real.writeAsBytes([1, 2, 3]);
    addTearDown(() => real.deleteSync());

    final received = <List<AppFile>>[];
    ReceiveSharingIntent.setMockValues(
      initialMedia: [
        // A plain-text share: the plugin stuffs the text into `path`.
        SharedMediaFile(path: 'just some shared text', type: SharedMediaType.text),
        SharedMediaFile(path: 'https://example.com/a', type: SharedMediaType.url),
        SharedMediaFile(path: real.path, type: SharedMediaType.file),
      ],
      mediaStream: const Stream.empty(),
    );
    final handler = ShareHandler((files) => received.add(files));
    handler.init();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    handler.dispose();
    expect(received, hasLength(1));
    expect(received.single, hasLength(1));
    expect(received.single.single.name, 'flashshare_share_test.jpg');
  });

  test('initial media is reset after consumption, so it cannot replay',
      () async {
    final real = File(
        '${Directory.systemTemp.path}/flashshare_share_test2.jpg');
    await real.writeAsBytes([1]);
    addTearDown(() => real.deleteSync());

    ReceiveSharingIntent.setMockValues(
      initialMedia: [
        SharedMediaFile(path: real.path, type: SharedMediaType.file),
      ],
      mediaStream: const Stream.empty(),
    );
    final handler = ShareHandler((_) {});
    handler.init();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    handler.dispose();
    expect(await ReceiveSharingIntent.instance.getInitialMedia(), isEmpty);
  });

  test('share stream errors do not crash the app', () async {
    final zoneErrors = <Object>[];
    await runZonedGuarded(() async {
      ReceiveSharingIntent.setMockValues(
        initialMedia: [],
        // The plugin's decode layer can throw (e.g. a null path). A malformed
        // share must surface as a handled error, not an uncaught zone error.
        mediaStream: Stream<List<SharedMediaFile>>.error(StateError('bad')),
      );
      final handler = ShareHandler((_) {});
      handler.init();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      handler.dispose();
    }, (e, s) => zoneErrors.add(e));
    expect(zoneErrors, isEmpty);
  });
}
