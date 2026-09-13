import 'dart:io';
import 'dart:typed_data';
import 'app_file.dart';

class _IoFile implements AppFile {
  final File _file;
  _IoFile(this._file);

  @override
  String get name => _file.path.split(RegExp(r'[/\\]')).last;

  @override
  String? get path => _file.path;

  @override
  Future<int> getSize() => _file.length();

  @override
  Future<Uint8List> readAsBytes() => _file.readAsBytes();

  @override
  Future<Uint8List> readRange(int start, int end) async {
    final raf = await _file.open();
    try {
      await raf.setPosition(start);
      return await raf.read(end - start);
    } finally {
      await raf.close();
    }
  }

  @override
  Stream<List<int>> openRead([int? start, int? end]) =>
      _file.openRead(start, end);
}

AppFile fileFromPath(String path) => _IoFile(File(path));

/// Whether [path] points at a real file on disk. Used to tell a shared
/// *text string* (which the plugin also puts in `path`) from a shared file.
bool fileExists(String path) => File(path).existsSync();
