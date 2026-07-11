import 'package:flutter/material.dart';
import 'package:flashshare/upload/upload_engine.dart';

class MultiFileDialog {
  static Future<UploadMode?> show(BuildContext context, int count) {
    return showDialog<UploadMode>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Share $count files as…'),
        children: [
          SimpleDialogOption(
            child: const Text('Upload separately'),
            onPressed: () => Navigator.pop(ctx, UploadMode.separate),
          ),
          SimpleDialogOption(
            child: const Text('Zip into one file'),
            onPressed: () => Navigator.pop(ctx, UploadMode.zip),
          ),
          SimpleDialogOption(
            child: const Text('As a collection'),
            onPressed: () => Navigator.pop(ctx, UploadMode.collection),
          ),
        ],
      ),
    );
  }
}
