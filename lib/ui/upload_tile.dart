import 'package:flutter/material.dart';
import 'package:flashshare/models.dart';
import 'package:flashshare/ui/theme.dart';
import 'package:flashshare/upload/upload_engine.dart';

/// Pick an icon + accent color for a filename. Colors come from the central
/// AppColors map (spec §1b) — never a hard-coded Color literal here.
({IconData icon, Color color}) fileVisuals(String filename) {
  final ext = filename.contains('.')
      ? filename.split('.').last.toLowerCase()
      : '';
  switch (ext) {
    case 'png' ||
          'jpg' ||
          'jpeg' ||
          'gif' ||
          'webp' ||
          'bmp' ||
          'heic' ||
          'svg':
      return AppColors.fileCategories['image']!;
    case 'mp4' || 'mov' || 'webm' || 'avi' || 'mkv' || 'm4v':
      return AppColors.fileCategories['video']!;
    case 'mp3' || 'wav' || 'ogg' || 'm4a' || 'flac':
      return AppColors.fileCategories['audio']!;
    case 'pdf':
      return AppColors.fileCategories['pdf']!;
    case 'doc' || 'docx' || 'rtf' || 'odt':
      return AppColors.fileCategories['doc']!;
    case 'xls' || 'xlsx' || 'csv':
      return AppColors.fileCategories['sheet']!;
    case 'ppt' || 'pptx' || 'key':
      return AppColors.fileCategories['slide']!;
    case 'zip' || 'rar' || '7z' || 'tar' || 'gz':
      return AppColors.fileCategories['archive']!;
    case 'txt' || 'md' || 'json' || 'xml' || 'yaml' || 'yml':
      return AppColors.fileCategories['text']!;
    case 'apk' || 'exe' || 'dmg' || 'deb':
      return AppColors.fileCategories['app']!;
    default:
      return AppColors.fileCategories['default']!;
  }
}

String formatBytes(int bytes) {
  if (bytes <= 0) return '—';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  final str = (i == 0 || v >= 100) ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  return '$str ${units[i]}';
}

String? expiryText(String? expiresAt) {
  if (expiresAt == null) return null;
  final d = DateTime.tryParse(expiresAt);
  if (d == null) return null;
  final days = d.difference(DateTime.now()).inDays;
  if (days < 0) return 'Expired';
  if (days == 0) return 'Expires today';
  return 'Expires in $days d';
}

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
  Widget build(BuildContext context) {
    final visuals = e.kind == 'collection'
        ? (icon: Icons.folder_special, color: AppColors.collection)
        : fileVisuals(e.filename);
    final expiry = expiryText(e.expiresAt);
    final metaParts = <String>[];
    if (e.kind != 'collection') metaParts.add(formatBytes(e.size));
    if (expiry != null) metaParts.add(expiry);
    final meta = metaParts.join('  •  ');

    return Card(
      child: InkWell(
        onTap: onCopy,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: visuals.color.withValues(alpha: 0.15),
                foregroundColor: visuals.color,
                child: Icon(visuals.icon, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.filename,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    if (meta.isNotEmpty)
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Theme.of(context).hintColor),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy_outlined),
                tooltip: 'Copy link',
                onPressed: onCopy,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete',
                color: Theme.of(context).colorScheme.error,
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ActiveTile extends StatelessWidget {
  final UploadProgress p;
  final VoidCallback onCancel;
  const ActiveTile({super.key, required this.p, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final visuals = fileVisuals(p.filename);
    final pct =
        p.total > 0 ? (p.bytesSent / p.total).clamp(0.0, 1.0) : 0.0;
    final showValue =
        p.state == UploadState.uploading || p.state == UploadState.done;

    final stateColor = switch (p.state) {
      UploadState.error => Theme.of(context).colorScheme.error,
      UploadState.cancelled => AppColors.brand,
      _ => null,
    };

    final label = switch (p.state) {
      UploadState.queued => 'Queued',
      UploadState.uploading =>
        'Uploading ${(pct * 100).toStringAsFixed(0)}%',
      UploadState.confirming => 'Finalizing…',
      UploadState.done => 'Done',
      UploadState.error => 'Error: ${p.error ?? ""}',
      UploadState.cancelled => 'Cancelled',
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: visuals.color.withValues(alpha: 0.15),
                  foregroundColor: visuals.color,
                  child: Icon(visuals.icon, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.filename,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(
                              color: stateColor ??
                                  Theme.of(context).textTheme.bodySmall?.color,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Cancel',
                  onPressed: p.state == UploadState.done ? null : onCancel,
                ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: showValue ? pct : null,
              minHeight: 6,
              borderRadius: const BorderRadius.all(Radius.circular(3)),
              color: stateColor,
            ),
          ],
        ),
      ),
    );
  }
}
