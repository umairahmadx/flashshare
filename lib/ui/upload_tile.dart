import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flashshare/ui/history_filter.dart';
import 'package:flashshare/ui/theme.dart';
import 'package:flashshare/upload/upload_engine.dart';

/// Icon + tint for a filename. The category rules live in [HistoryFilter] so
/// the History filter chips and the tiles can never disagree about what a
/// `.m4v` or `.yaml` is.
({IconData icon, Color color}) fileVisuals(String filename) =>
    AppColors.fileCategories[HistoryFilter.categoryOf(filename)]!;

/// Expiry wording for a raw ISO timestamp. Delegates to [HistoryFilter] so the
/// app has exactly one version of this sentence.
String? expiryText(String? expiresAt) => HistoryFilter.describeExpiry(expiresAt);

/// A live upload row: state label, progress bar, cancel.
class ActiveTile extends StatelessWidget {
  final UploadProgress p;
  final VoidCallback onCancel;
  const ActiveTile({super.key, required this.p, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final ink = InkPalette.of(context);
    final pct = p.total > 0 ? (p.bytesSent / p.total).clamp(0.0, 1.0) : 0.0;
    final showValue =
        p.state == UploadState.uploading || p.state == UploadState.done;

    final isProblem =
        p.state == UploadState.error || p.state == UploadState.cancelled;
    final stateColor = isProblem ? (p.state == UploadState.error
        ? ink.danger
        : ink.muted) : ink.ink;

    final label = switch (p.state) {
      UploadState.queued => 'Queued',
      UploadState.uploading =>
        'Uploading ${(pct * 100).toStringAsFixed(0)}% · ${((p.bytesSent / 1024) / 1024).toStringAsFixed(1)} MB',
      UploadState.confirming => 'Finalizing…',
      UploadState.done => 'Done',
      UploadState.error => 'Error: ${p.error ?? ""}',
      UploadState.cancelled => 'Cancelled',
    };

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: ink.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: ink.line),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _TileVisual(url: p.url ?? '', filename: p.filename),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.filename,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.cardTitle.copyWith(color: ink.ink),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: stateColor),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                tooltip: 'Cancel upload',
                onPressed: p.state == UploadState.done ? null : onCancel,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: showValue ? pct : null,
              minHeight: 6,
              color: stateColor,
              backgroundColor: ink.raised,
            ),
          ),
        ],
      ),
    );
  }
}

/// 48px leading visual: cached thumbnail for image/video/PDF, otherwise a
/// neutral tile with the file-type icon (monochrome — the icon carries the
/// identity, not the fill).
class _TileVisual extends StatelessWidget {
  final String url;
  final String filename;
  const _TileVisual({required this.url, required this.filename});

  @override
  Widget build(BuildContext context) {
    final ink = InkPalette.of(context);
    final isCollection = !filename.contains('.');
    final visuals = fileVisuals(filename);
    final ext = isCollection ? '' : filename.split('.').last.toLowerCase();
    final thumbable = [
      'jpg', 'jpeg', 'png', 'webp', 'gif', 'mp4', 'mov', 'pdf'
    ].contains(ext);

    Widget solid = Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: ink.tileBg,
        borderRadius: BorderRadius.circular(AppRadius.tile),
      ),
      child: Icon(
        isCollection ? Icons.folder_special_rounded : visuals.icon,
        color: ink.onAccent,
        size: 22,
      ),
    );

    if (isCollection || !thumbable || url.isEmpty) return solid;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.tile),
      child: SizedBox(
        width: 48,
        height: 48,
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) => solid,
          placeholder: (_, __) => solid,
        ),
      ),
    );
  }
}

