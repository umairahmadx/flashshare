import 'package:flutter/material.dart';
import 'package:flashshare/models.dart';
import 'package:flashshare/upload/upload_engine.dart';

class HistoryTile extends StatelessWidget {
  final HistoryEntry e;
  final VoidCallback onCopy;
  final VoidCallback onDelete;
  const HistoryTile(
      {super.key,
      required this.e,
      required this.onCopy,
      required this.onDelete});

  @override
  Widget build(BuildContext context) => ListTile(
        title: Text(e.filename),
        subtitle: Text(e.url, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(icon: const Icon(Icons.copy), onPressed: onCopy),
            IconButton(icon: const Icon(Icons.delete), onPressed: onDelete),
          ],
        ),
      );
}

class ActiveTile extends StatelessWidget {
  final UploadProgress p;
  final VoidCallback onCancel;
  const ActiveTile({super.key, required this.p, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final pct = p.total > 0 ? (p.bytesSent / p.total).clamp(0.0, 1.0) : 0.0;
    final label = switch (p.state) {
      UploadState.queued => 'Queued',
      UploadState.uploading => 'Uploading ${(pct * 100).toStringAsFixed(0)}%',
      UploadState.confirming => 'Finalizing…',
      UploadState.done => 'Done',
      UploadState.error => 'Error: ${p.error ?? ""}',
      UploadState.cancelled => 'Cancelled',
    };
    return ListTile(
      title: Text(p.filename),
      subtitle: p.state == UploadState.error || p.state == UploadState.cancelled
          ? Text(label)
          : LinearProgressIndicator(value: p.state == UploadState.queued ? 0 : pct),
      trailing: IconButton(
          icon: const Icon(Icons.close),
          onPressed: p.state == UploadState.done ? null : onCancel),
    );
  }
}
