import 'package:flutter/material.dart';
import 'package:flashshare/ui/theme.dart';
import 'package:flashshare/upload/upload_engine.dart';

class MultiFileDialog {
  static Future<UploadMode?> show(BuildContext context, int count) {
    final options = [
      (
        mode: UploadMode.separate,
        icon: Icons.file_copy_outlined,
        color: AppColors.brand,
        title: 'Upload separately',
        desc: 'Each file gets its own share link.',
      ),
      (
        mode: UploadMode.zip,
        icon: Icons.archive_outlined,
        color: AppColors.fileCategories['archive']!.color,
        title: 'Zip into one file',
        desc: 'Bundle everything into a single .zip.',
      ),
      (
        mode: UploadMode.collection,
        icon: Icons.folder_special_outlined,
        color: AppColors.collection,
        title: 'As a collection',
        desc: 'One link opens all files together.',
      ),
    ];

    return showDialog<UploadMode>(
      context: context,
      builder: (ctx) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Share $count files',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 6),
              Text('Choose how to send these files.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).hintColor)),
              const SizedBox(height: 20),
              ...options.map((o) => _Option(
                    icon: o.icon,
                    color: o.color,
                    title: o.title,
                    desc: o.desc,
                    onTap: () => Navigator.pop(ctx, o.mode),
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String desc;
  final VoidCallback onTap;
  const _Option({
    required this.icon,
    required this.color,
    required this.title,
    required this.desc,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: color.withValues(alpha: 0.15),
                    foregroundColor: color,
                    child: Icon(icon, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 2),
                        Text(desc,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                    color: Theme.of(context).hintColor)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right,
                      color: Theme.of(context).colorScheme.outline),
                ],
              ),
            ),
          ),
        ),
      );
}
