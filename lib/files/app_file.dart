import 'dart:typed_data';

export 'native_file_stub.dart' if (dart.library.io) 'native_file_io.dart';

/// Platform-neutral handle to a file's contents.
///
/// The upload pipeline used to thread `dart:io File` everywhere, which crashes
/// on web. This abstraction is backed by in-memory bytes on web and by a native
/// `File` on mobile (see the conditional export above), so callers never touch
/// `dart:io` directly.
abstract class AppFile {
  String get name;
  Future<int> getSize();
  Future<Uint8List> readAsBytes();

  /// Reads `[start, end)` of the contents, for bounded multipart chunks.
  Future<Uint8List> readRange(int start, int end);

  /// Streaming read for PUT bodies. Avoids buffering the whole file in RAM,
  /// which previously OOM-killed the app on large uploads (see upload_engine).
  Stream<List<int>> openRead([int? start, int? end]);
}

/// In-memory file, works on every platform.
class BytesFile implements AppFile {
  @override
  final String name;
  final Uint8List _bytes;

  BytesFile(this.name, this._bytes);

  @override
  Future<int> getSize() async => _bytes.length;

  @override
  Future<Uint8List> readAsBytes() async => _bytes;

  @override
  Future<Uint8List> readRange(int start, int end) async =>
      Uint8List.sublistView(_bytes, start, end);

  @override
  Stream<List<int>> openRead([int? start, int? end]) =>
      Stream.value(Uint8List.sublistView(_bytes, start ?? 0, end ?? _bytes.length));
}
