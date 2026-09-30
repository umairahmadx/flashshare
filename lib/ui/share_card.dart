import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flashshare/models.dart';
import 'package:flashshare/ui/history_filter.dart';
import 'package:flashshare/ui/theme.dart';

/// One share in the History / recent list: thumbnail tile, name, meta line,
/// status chips and the four actions that matter.
///
/// Deliberately stateless — the parent owns every action so the log sees one
/// consistent event per tap.
class ShareCard extends StatelessWidget {
  final HistoryEntry entry;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final VoidCallback onQr;
  final VoidCallback onEditOptions;
  final VoidCallback onDelete;

  /// Set while the list is filtering so the card can dim itself instead of
  /// animating out (a card that vanishes mid-tap is a bug magnet).
  final bool dimmed;

  const ShareCard({
    super.key,
    required this.entry,
    required this.onCopy,
    required this.onShare,
    required this.onQr,
    required this.onEditOptions,
    required this.onDelete,
    this.dimmed = false,
  });

  @override
  Widget build(BuildContext context) {
    final ink = InkPalette.of(context);
    final e = entry;
    final expired = HistoryFilter.isExpired(e);
    final expiry = HistoryFilter.expiryLabel(e);
    final isCollection = e.kind == 'collection';

    return Opacity(
      opacity: dimmed ? 0.5 : 1,
      child: Container(
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
                _ShareThumb(url: e.url, filename: e.filename, expired: expired),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              e.filename,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.cardTitle.copyWith(color: ink.ink),
                            ),
                          ),
                          if (e.locked)
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: Icon(Icons.lock_outline_rounded,
                                  size: 16, color: ink.muted),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        [
                          isCollection ? 'Collection' : formatBytes(e.size),
                          HistoryFilter.ageLabel(e.createdAt),
                        ].join(' · '),
                        style: TextStyle(fontSize: 12.5, color: ink.muted),
                      ),
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (isCollection) const _Chip('COLLECTION'),
                          if (expired)
                            _Chip('EXPIRED', tone: _ChipTone.danger)
                          else if (expiry != null)
                            _Chip(expiry.toUpperCase()),
                          if (e.locked) const _Chip('PASSWORD'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                _CardAction(
                    icon: Icons.link_rounded, label: 'Copy', onTap: onCopy),
                _CardAction(
                    icon: Icons.ios_share_rounded,
                    label: 'Share',
                    onTap: onShare),
                _CardAction(
                    icon: Icons.qr_code_2_rounded, label: 'QR', onTap: onQr),
                _CardAction(
                    icon: Icons.tune_rounded,
                    label: 'Options',
                    onTap: onEditOptions),
                _CardAction(
                    icon: Icons.delete_outline_rounded,
                    label: 'Delete',
                    onTap: onDelete,
                    danger: true),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Thumbnail: real image when the share has a cached one, file-type icon
/// otherwise. Monochrome — the tile fill is always the neutral surface.
class _ShareThumb extends StatelessWidget {
  final String url;
  final String filename;
  final bool expired;
  const _ShareThumb(
      {required this.url, required this.filename, required this.expired});

  @override
  Widget build(BuildContext context) {
    final ink = InkPalette.of(context);
    final isCollection = !filename.contains('.');
    final ext =
        filename.contains('.') ? filename.split('.').last.toLowerCase() : '';
    final thumbable = [
      'jpg', 'jpeg', 'png', 'webp', 'gif', 'mp4', 'mov', 'pdf'
    ].contains(ext);

    Widget fallback = Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: ink.tileBg,
        borderRadius: BorderRadius.circular(AppRadius.tile),
      ),
      child: Icon(
        isCollection
            ? Icons.folder_special_rounded
            : AppColors
                    .fileCategories[HistoryFilter.categoryOf(filename)]
                    ?.icon ??
                AppColors.fileCategories['default']!.icon,
        color: ink.onAccent,
        size: 22,
      ),
    );

    if (isCollection || !thumbable) {
      return Opacity(opacity: expired ? 0.45 : 1, child: fallback);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.tile),
      child: SizedBox(
        width: 48,
        height: 48,
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          fadeInDuration: const Duration(milliseconds: 150),
          placeholder: (_, __) => fallback,
          errorWidget: (_, __, ___) => fallback,
        ),
      ),
    );
  }
}

enum _ChipTone { neutral, danger }

/// Small uppercase status chip ("EXPIRES IN 3 D", "PASSWORD", "EXPIRED").
class _Chip extends StatelessWidget {
  final String label;
  final _ChipTone tone;
  const _Chip(this.label, {this.tone = _ChipTone.neutral});

  @override
  Widget build(BuildContext context) {
    final ink = InkPalette.of(context);
    final color = tone == _ChipTone.danger ? ink.danger : ink.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: tone == _ChipTone.danger
            ? ink.danger.withValues(alpha: 0.10)
            : ink.raised,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
            color: tone == _ChipTone.danger ? ink.danger : ink.line),
      ),
      child: Text(label,
          style: AppText.microLabel.copyWith(fontSize: 9.5, color: color)),
    );
  }
}

/// Compact icon + label action along the bottom of a [ShareCard].
class _CardAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;
  const _CardAction(
      {required this.icon,
      required this.label,
      required this.onTap,
      this.danger = false});

  @override
  Widget build(BuildContext context) {
    final ink = InkPalette.of(context);
    final color = danger ? ink.danger : ink.ink;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.field),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(height: 3),
              Text(label.toUpperCase(),
                  style: AppText.microLabel.copyWith(
                      fontSize: 9, color: color, letterSpacing: 0.8)),
            ],
          ),
        ),
      ),
    );
  }
}

