import 'package:flutter/material.dart';
import 'package:flashshare/logs/log_store.dart';
import 'package:flashshare/ui/theme.dart';

/// Confirmation popup for destructive actions (delete share, clear logs).
class ConfirmDialog {
  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'Confirm',
    bool destructive = false,
  }) async {
    AppLog.debug('Confirm dialog opened: "$title"', source: 'ui.confirm');
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final ink = InkPalette.of(ctx);
        return AlertDialog(
          title: Text(title),
          content: Text(message,
              style: TextStyle(fontSize: 13.5, color: ink.muted)),
          actions: [
            TextButton(
              onPressed: () {
                AppLog.debug('"$title" cancelled', source: 'ui.confirm');
                Navigator.pop(ctx, false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: destructive
                  ? FilledButton.styleFrom(
                      backgroundColor: ink.danger,
                      foregroundColor: ink.onAccent,
                    )
                  : null,
              onPressed: () {
                AppLog.info('"$title" confirmed', source: 'ui.confirm');
                Navigator.pop(ctx, true);
              },
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );
    return res ?? false;
  }
}

