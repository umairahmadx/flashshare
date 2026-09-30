import 'package:flutter/material.dart';
import 'package:flashshare/logs/log_store.dart';
import 'package:flashshare/ui/theme.dart';
import 'package:flashshare/upload/upload_engine.dart';

/// "How should I send these N files?" — separate / zip / collection.
class MultiFileDialog {
  static Future<UploadMode?> show(BuildContext context, int count) {
    final options = [
      (
        mode: UploadMode.separate,
        icon: Icons.file_copy_outlined,
        title: 'Upload separately',
        desc: 'Each file gets its own share link.',
      ),
      (
        mode: UploadMode.zip,
        icon: Icons.archive_outlined,
        title: 'Zip into one file',
        desc: 'Bundle everything into a single .zip.',
      ),
      (
        mode: UploadMode.collection,
        icon: Icons.folder_special_outlined,
        title: 'As a collection',
        desc: 'One link opens all files together.',
      ),
    ];

    AppLog.debug('Multi-file mode dialog opened for $count files',
        source: 'ui.send');
    return showDialog<UploadMode>(
      context: context,
      builder: (ctx) {
        final localInk = InkPalette.of(ctx);
        return Dialog(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Share $count files',
                    style: AppText.cardTitle
                        .copyWith(color: localInk.ink, fontSize: 18)),
                const SizedBox(height: AppSpacing.xs),
                Text('Choose how to send these files.',
                    style: TextStyle(fontSize: 13, color: localInk.muted)),
                const SizedBox(height: AppSpacing.lg),
                ...options.map((o) => _Option(
                      icon: o.icon,
                      ink: localInk,
                      title: o.title,
                      desc: o.desc,
                      onTap: () {
                        AppLog.info(
                            'Multi-file mode: ${o.mode.name} for $count files',
                            source: 'ui.send');
                        Navigator.pop(ctx, o.mode);
                      },
                    )),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Option extends StatelessWidget {
  final IconData icon;
  final InkPalette ink;
  final String title;
  final String desc;
  final VoidCallback onTap;
  const _Option({
    required this.icon,
    required this.ink,
    required this.title,
    required this.desc,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Material(
          color: ink.raised,
          borderRadius: BorderRadius.circular(AppRadius.field),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.field),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.field),
                border: Border.all(color: ink.line),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: ink.tileBg,
                      borderRadius: BorderRadius.circular(AppRadius.tile),
                    ),
                    child: Icon(icon, size: 20, color: ink.onAccent),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style:
                                AppText.cardTitle.copyWith(color: ink.ink)),
                        const SizedBox(height: 2),
                        Text(desc,
                            style:
                                TextStyle(fontSize: 12.5, color: ink.muted)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      color: ink.faint, size: 20),
                ],
              ),
            ),
          ),
        ),
      );
}
