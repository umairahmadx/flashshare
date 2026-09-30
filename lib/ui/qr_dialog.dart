import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flashshare/logs/log_store.dart';
import 'package:flashshare/ui/theme.dart';
import 'package:flashshare/ui/toast.dart';

/// "Scan to download" QR. The code itself stays black-on-white no matter the
/// theme — that is a scanning requirement, not a styling choice.
class QrDialog extends StatelessWidget {
  final String url;
  final String filename;

  const QrDialog({super.key, required this.url, required this.filename});

  static Future<void> show(BuildContext context,
      {required String url, required String filename}) {
    return showDialog(
      context: context,
      builder: (context) => QrDialog(url: url, filename: filename),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ink = InkPalette.of(context);
    return AlertDialog(
      title: Text('Scan to download',
          style: AppText.cardTitle.copyWith(color: ink.ink, fontSize: 17)),
      content: SizedBox(
        width: 250,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              filename,
              style: TextStyle(fontSize: 12.5, color: ink.muted),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.qrBackground,
                borderRadius: BorderRadius.circular(AppRadius.tile),
              ),
              child: QrImageView(
                data: url,
                version: QrVersions.auto,
                size: 200.0,
                gapless: false,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: AppColors.qrForeground,
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: AppColors.qrForeground,
                ),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: url));
                  AppLog.debug('Link copied from the QR dialog',
                      source: 'ui.qr');
                  showToast(context, 'Link copied');
                },
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('Copy link'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

