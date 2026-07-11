import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flashshare/models.dart';
import 'package:flashshare/share/share_handler.dart';
import 'package:flashshare/storage/history_store.dart';
import 'package:flashshare/ui/multi_file_dialog.dart';
import 'package:flashshare/ui/upload_tile.dart';
import 'package:flashshare/upload/upload_engine.dart';

class HomePage extends StatefulWidget {
  final HistoryStore store;
  final UploadEngine engine;
  const HomePage({super.key, required this.store, required this.engine});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<UploadProgress> _active = [];
  List<HistoryEntry> _history = [];
  late final ShareHandler _share;

  @override
  void initState() {
    super.initState();
    _history = widget.store.getAll();
    widget.engine.progress.listen((p) {
      if (!mounted) return;
      setState(() {
        _active.removeWhere((a) => a.key == p.key);
        if (p.state != UploadState.done) _active.add(p);
      });
    });
    _share = ShareHandler((files) => _receive(files));
    _share.init();
  }

  Future<void> _pick() async {
    final res = await FilePicker.pickFiles(allowMultiple: true);
    if (res == null) return;
    final files = res.paths
        .where((p) => p != null)
        .map((p) => File(p!))
        .toList();
    if (files.isNotEmpty) await _receive(files);
  }

  Future<void> _receive(List<File> files) async {
    final mode = files.length > 1
        ? await MultiFileDialog.show(context, files.length)
        : UploadMode.separate;
    if (mode == null) return;
    await widget.engine.enqueue(files, mode);
  }

  Future<void> _delete(HistoryEntry e) async {
    try {
      if (e.kind == 'collection') {
        await widget.engine.client.deleteCollection(e.id, e.ownerToken);
      } else {
        await widget.engine.client.deleteFile(e.id, e.ownerToken);
      }
      await widget.store.remove(e.id);
      if (mounted) setState(() => _history = widget.store.getAll());
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Delete failed: $err')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Flash Share')),
        body: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            ..._active.map((p) => ActiveTile(
                p: p, onCancel: () => widget.engine.cancel(p.key))),
            ..._history.map((e) => HistoryTile(
                  e: e,
                  onCopy: () {
                    Clipboard.setData(ClipboardData(text: e.url));
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('Link copied')));
                  },
                  onDelete: () => _delete(e),
                )),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _pick,
          tooltip: 'Pick files',
          child: const Icon(Icons.upload),
        ),
      );
}
