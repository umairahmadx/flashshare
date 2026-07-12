import 'dart:typed_data';
import 'app_file.dart';

// Reached only on web. Web has no filesystem paths, so this is unreachable in
// practice: file_picker yields bytes there, and receive_sharing_intent (the
// other caller) is mobile-only and guarded behind kIsWeb.
AppFile fileFromPath(String path) =>
    throw UnsupportedError('fileFromPath is not supported on the web platform');
