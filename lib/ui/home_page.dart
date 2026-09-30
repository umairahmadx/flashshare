import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flashshare/files/app_file.dart';
import 'package:flashshare/logs/log_store.dart';
import 'package:flashshare/models.dart';
import 'package:flashshare/share/share_handler.dart';
import 'package:flashshare/storage/history_store.dart';
import 'package:flashshare/ui/confirm_dialog.dart';
import 'package:flashshare/ui/history_screen.dart';
import 'package:flashshare/ui/logs_screen.dart';
import 'package:flashshare/ui/multi_file_dialog.dart';
import 'package:flashshare/ui/qr_dialog.dart';
import 'package:flashshare/ui/settings_store.dart';
import 'package:flashshare/ui/settings_tab.dart';
import 'package:flashshare/ui/share_card.dart';
import 'package:flashshare/ui/share_options_sheet.dart';
import 'package:flashshare/ui/theme.dart';
import 'package:flashshare/ui/toast.dart';
import 'package:flashshare/ui/upload_tile.dart';
import 'package:flashshare/upload/background_service.dart';
import 'package:flashshare/upload/upload_engine.dart';

/// The app shell: one Scaffold, three tabs (Send / History / Settings), a
/// header that follows the tab, and every user action mirrored into the log.
class HomePage extends StatefulWidget {
  final HistoryStore store;
  final SettingsStore settings;
  final UploadEngine engine;
  final LogStore logs;
  final void Function(ThemeMode mode) onThemeMode;
  const HomePage(
      {super.key,
      required this.store,
      required this.settings,
      required this.engine,
      required this.logs,
      required this.onThemeMode});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _send = 0;
  static const _history = 1;
  static const _settings = 2;

  int _tab = _send;
  final List<UploadProgress> _active = [];
  List<HistoryEntry> _historyEntries = [];
  late final ShareHandler _share;
  StreamSubscription<UploadProgress>? _progressSub;

  @override
  void initState() {
    super.initState();
    _historyEntries = widget.store.getAll();
    _progressSub = widget.engine.progress.listen(_onProgress);
    _share = ShareHandler((files) {
      AppLog.info(
          'Incoming share of ${files.length} file(s) from another app',
          source: 'share');
      _receive(files);
    });
    _share.init();
    AppLog.debug('Shell ready with ${_historyEntries.length} history entries',
        source: 'ui.shell');
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    _share.dispose();
    super.dispose();
  }

  /// Every upload state change is mirrored to the log — this is the trail you
  /// read afterwards when "the upload just sat there".
  void _onProgress(UploadProgress p) {
    if (!mounted) return;
    switch (p.state) {
      case UploadState.error:
        AppLog.error('Upload "${p.filename}" errored: ${p.error}',
            source: 'upload');
      case UploadState.done:
        AppLog.info('Upload "${p.filename}" finished', source: 'upload');
      case UploadState.cancelled:
        AppLog.warning('Upload "${p.filename}" cancelled', source: 'upload');
      case UploadState.queued:
      case UploadState.uploading:
      case UploadState.confirming:
        break; // byte-by-byte progress would drown the log.
    }
    setState(() {
      _active.removeWhere((a) => a.key == p.key);
      if (p.state != UploadState.done) {
        _active.add(p);
      } else {
        _historyEntries = widget.store.getAll();
      }
    });
  }

  Future<void> _pick() async {
    AppLog.debug('File picker opened', source: 'ui.send');
    FilePickerResult? res;
    try {
      res = await FilePicker.pickFiles(
          allowMultiple: true, withData: kIsWeb);
    } catch (e, st) {
      AppLog.error('File picker failed: $e', stack: st, source: 'picker');
      if (mounted) showToast(context, 'Could not open the file picker: $e');
      return;
    }
    if (res == null) {
      AppLog.debug('File picker cancelled', source: 'ui.send');
      return;
    }
    final files = res.files
        .where((pf) =>
            pf.bytes != null || (pf.path != null && pf.path!.isNotEmpty))
        .map((pf) {
      if (pf.bytes != null) return BytesFile(pf.name, pf.bytes!);
      return fileFromPath(pf.path!);
    }).toList();
    AppLog.info('Picked ${files.length} of ${res.files.length} entries',
        source: 'picker');
    if (files.length != res.files.length) {
      AppLog.warning(
          '${res.files.length - files.length} picked entr(ies) had neither bytes nor a path and were dropped',
          source: 'picker');
    }
    if (files.isNotEmpty) await _receive(files);
  }

  Future<void> _receive(List<AppFile> files) async {
    UploadMode mode = UploadMode.separate;
    if (files.length > 1) {
      final picked = await MultiFileDialog.show(context, files.length);
      if (picked == null) {
        AppLog.debug('Multi-file mode dialog cancelled — nothing uploaded',
            source: 'ui.send');
        return;
      }
      mode = picked;
      AppLog.debug('Upload mode chosen: ${mode.name}', source: 'ui.send');
    }
    // Options come before uploading: cancelling here cancels the whole share.
    final options =
        await ShareOptionsSheet.show(context, fileCount: files.length);
    if (options == null) {
      AppLog.debug('Share options cancelled — nothing uploaded',
          source: 'ui.send');
      return;
    }
    try {
      await startUploadService();
      await widget.engine.enqueue(files, mode, options: options);
      AppLog.info(
          'Enqueued ${files.length} file(s) as ${mode.name}${options.isEmpty ? '' : ' with options'}',
          source: 'upload');
      if (mounted && _tab != _send) setState(() => _tab = _send);
    } catch (e, st) {
      AppLog.error('Enqueue failed: $e', stack: st, source: 'upload');
      if (mounted) showToast(context, 'Upload failed: $e');
    }
  }

  Future<void> _delete(HistoryEntry e) async {
    AppLog.debug('Delete requested for ${e.id}', source: 'ui.history');
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Delete share?',
      message: e.kind == 'collection'
          ? 'This deletes the collection and ALL its files. Anyone with the link loses access.'
          : '"${e.filename}" will be deleted immediately and its link stops working.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed) {
      AppLog.debug('Delete cancelled for ${e.id}', source: 'ui.history');
      return;
    }
    try {
      if (e.kind == 'collection') {
        await widget.engine.client.deleteCollection(e.id, e.ownerToken);
      } else {
        await widget.engine.client.deleteFile(e.id, e.ownerToken);
      }
      await widget.store.remove(e.id);
      AppLog.info('Deleted ${e.kind} ${e.id} ("${e.filename}")',
          source: 'history');
      if (mounted) setState(() => _historyEntries = widget.store.getAll());
    } catch (err, st) {
      AppLog.error('Delete failed for ${e.id}: $err',
          stack: st, source: 'history');
      if (mounted) showToast(context, 'Delete failed: $err');
    }
  }

  Future<void> _editOptions(HistoryEntry e) async {
    final options =
        await ShareOptionsSheet.show(context, fileCount: 1, editing: e);
    if (options == null) {
      AppLog.debug('Share options edit cancelled for ${e.id}',
          source: 'ui.history');
      return;
    }
    try {
      await widget.engine.applyOptions(e, options);
      AppLog.info('Share options applied to ${e.id}', source: 'history');
      if (mounted) {
        setState(() => _historyEntries = widget.store.getAll());
        showToast(context, 'Options applied');
      }
    } catch (err, st) {
      AppLog.error('Applying options to ${e.id} failed: $err',
          stack: st, source: 'history');
      if (mounted) showToast(context, 'Failed to apply: $err');
    }
  }

  void _copy(HistoryEntry e) {
    Clipboard.setData(ClipboardData(text: e.url));
    AppLog.debug('Link copied for ${e.id}', source: 'ui.history');
    showToast(context, 'Link copied');
  }

  void _shareUrl(HistoryEntry e) async {
    AppLog.debug('Sharing link for ${e.id} through the OS sheet',
        source: 'ui.history');
    try {
      await SharePlus.instance
          .share(ShareParams(text: e.url, subject: e.filename));
      AppLog.debug('OS share sheet returned for ${e.id}', source: 'ui.history');
    } catch (err, st) {
      AppLog.error('OS share failed for ${e.id}: $err',
          stack: st, source: 'share');
      if (mounted) showToast(context, 'Could not open the share sheet');
    }
  }

  void _showQr(HistoryEntry e) {
    AppLog.debug('QR opened for ${e.id}', source: 'ui.history');
    QrDialog.show(context, url: e.url, filename: e.filename);
  }

  void _openLogs() {
    AppLog.debug('Event log opened', source: 'ui.logs');
    Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => LogsScreen(store: widget.logs)));
  }

  void _goTo(int tab) {
    if (tab == _tab) return;
    AppLog.debug('Tab → ${_tabName(tab)}', source: 'ui.shell');
    setState(() => _tab = tab);
  }

  static String _tabName(int tab) => switch (tab) {
        _send => 'send',
        _history => 'history',
        _settings => 'settings',
        _ => 'unknown',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ShellHeader(
              tab: _tab,
              uploading: _active.length,
              onLogs: _openLogs,
              onLongPressWordmark: _openLogs,
            ),
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: [
                  _SendTab(
                    active: _active,
                    recent: _historyEntries.take(3).toList(),
                    totalShares: _historyEntries.length,
                    onPick: _pick,
                    onCancel: widget.engine.cancel,
                    onOpenHistory: () => _goTo(_history),
                    onCopy: _copy,
                    onShare: _shareUrl,
                    onQr: _showQr,
                    onEditOptions: _editOptions,
                    onDelete: _delete,
                  ),
                  HistoryScreen(
                    entries: _historyEntries,
                    onCopy: _copy,
                    onShare: _shareUrl,
                    onQr: _showQr,
                    onEditOptions: _editOptions,
                    onDelete: _delete,
                    onPick: _pick,
                  ),
                  SettingsTab(
                    store: widget.settings,
                    client: widget.engine.client,
                    onChanged: widget.onThemeMode,
                    onOpenLogs: _openLogs,
                    logCount: widget.logs.entries.length,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _BottomNav(index: _tab, onChanged: _goTo),
    );
  }
}

/// Header for the active tab. The Send tab shows the greeting + wordmark (and
/// hides nothing else); History and Settings show a plain title. The logs
/// button is on every tab — a bug can happen anywhere.
class _ShellHeader extends StatelessWidget {
  final int tab;
  final int uploading;
  final VoidCallback onLogs;
  final VoidCallback onLongPressWordmark;
  const _ShellHeader({
    required this.tab,
    required this.uploading,
    required this.onLogs,
    required this.onLongPressWordmark,
  });

  @override
  Widget build(BuildContext context) {
    final ink = InkPalette.of(context);
    final title = switch (tab) {
      1 => 'History',
      2 => 'Settings',
      _ => null,
    };
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 18
            ? 'Good afternoon'
            : 'Good evening';
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter, AppSpacing.md, AppSpacing.gutter, AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: title != null
                ? Text(title,
                    style: Theme.of(context).appBarTheme.titleTextStyle)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(greeting,
                          style: TextStyle(
                              fontSize: 12.5, color: ink.muted)),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.bolt_rounded, color: ink.ink, size: 28),
                          const SizedBox(width: 2),
                          GestureDetector(
                            onLongPress: onLongPressWordmark,
                            child: Text('Flash Share',
                                style: Theme.of(context)
                                    .appBarTheme
                                    .titleTextStyle),
                          ),
                          if (uploading > 0) ...[
                            const SizedBox(width: 8),
                            _LiveDot(count: uploading),
                          ],
                        ],
                      ),
                    ],
                  ),
          ),
          _IconPillButton(
            icon: Icons.terminal_outlined,
            tooltip: 'Event log',
            onPressed: onLogs,
          ),
        ],
      ),
    );
  }
}

/// "2 uploading" indicator beside the wordmark.
class _LiveDot extends StatelessWidget {
  final int count;
  const _LiveDot({required this.count});

  @override
  Widget build(BuildContext context) {
    final ink = InkPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: ink.raised,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: ink.line),
      ),
      child: Text('$count uploading',
          style: AppText.microLabel.copyWith(color: ink.muted)),
    );
  }
}

/// Bottom tab bar: Send / History / Settings. Monochrome — the selected tab is
/// a filled pill, everything else is ink on the card surface.
class _BottomNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;
  const _BottomNav({required this.index, required this.onChanged});

  static const _tabs = [
    (icon: Icons.bolt_rounded, label: 'Send'),
    (icon: Icons.history_rounded, label: 'History'),
    (icon: Icons.settings_outlined, label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final ink = InkPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: ink.card,
        border: Border(top: BorderSide(color: ink.line)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Row(
        children: [
          for (var i = 0; i < _tabs.length; i++)
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: i == index ? ink.accent : AppColors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    border: Border.all(
                        color: i == index ? ink.accent : ink.lineSoft),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        _tabs[i].icon,
                        size: 20,
                        color: i == index ? ink.onAccent : ink.muted,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _tabs[i].label,
                        style: AppText.microLabel.copyWith(
                          fontSize: 10,
                          color: i == index ? ink.onAccent : ink.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The Send tab: drop zone, live uploads, and a short recent-shares list.
class _SendTab extends StatelessWidget {
  final List<UploadProgress> active;
  final List<HistoryEntry> recent;
  final int totalShares;
  final VoidCallback onPick;
  final void Function(String key) onCancel;
  final VoidCallback onOpenHistory;
  final void Function(HistoryEntry e) onCopy;
  final void Function(HistoryEntry e) onShare;
  final void Function(HistoryEntry e) onQr;
  final void Function(HistoryEntry e) onEditOptions;
  final void Function(HistoryEntry e) onDelete;

  const _SendTab({
    required this.active,
    required this.recent,
    required this.totalShares,
    required this.onPick,
    required this.onCancel,
    required this.onOpenHistory,
    required this.onCopy,
    required this.onShare,
    required this.onQr,
    required this.onEditOptions,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter, 0, AppSpacing.gutter, AppSpacing.lg),
      children: [
        _DropZone(onPick: onPick),
        if (active.isNotEmpty) ...[
          const _SectionLabel('Uploading'),
          ...active.map(
              (p) => ActiveTile(p: p, onCancel: () => onCancel(p.key))),
        ],
        if (recent.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(0, AppSpacing.lg, 0, AppSpacing.sm),
            child: Row(
              children: [
                Expanded(
                  child: Text('RECENT SHARES',
                      style: AppText.microLabel
                          .copyWith(color: InkPalette.of(context).faint)),
                ),
                TextButton(
                  onPressed: onOpenHistory,
                  child: Text(totalShares > recent.length
                      ? 'View all $totalShares'
                      : 'View all'),
                ),
              ],
            ),
          ),
          ...recent.map((e) => ShareCard(
                entry: e,
                onCopy: () => onCopy(e),
                onShare: () => onShare(e),
                onQr: () => onQr(e),
                onEditOptions: () => onEditOptions(e),
                onDelete: () => onDelete(e),
              )),
        ] else if (active.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xl),
            child: _EmptyHint(
              icon: Icons.bolt_rounded,
              text: totalShares == 0
                  ? 'No shares yet — pick a file to create your first link.'
                  : 'Nothing on the Send tab. Open History to see your '
                      '$totalShares existing share${totalShares == 1 ? '' : 's'}.',
              actionLabel: totalShares == 0 ? null : 'Open History',
              onAction: totalShares == 0 ? null : onOpenHistory,
            ),
          ),
      ],
    );
  }
}

/// A quiet centered hint with an optional action.
class _EmptyHint extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;
  const _EmptyHint(
      {required this.icon, required this.text, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    final ink = InkPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Column(
        children: [
          Icon(icon, size: 44, color: ink.faint),
          const SizedBox(height: AppSpacing.md),
          Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: ink.muted)),
          if (actionLabel != null) ...[
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

/// The dashed drop-zone card: the one big affordance on the Send tab.
class _DropZone extends StatelessWidget {
  final VoidCallback onPick;
  const _DropZone({required this.onPick});

  @override
  Widget build(BuildContext context) {
    final ink = InkPalette.of(context);
    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(AppRadius.hero),
      child: CustomPaint(
        painter: _DashedRectPainter(color: ink.line, radius: AppRadius.hero),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: AppSpacing.xl),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.hero),
          ),
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: ink.tileBg,
                  borderRadius: BorderRadius.circular(AppRadius.tile),
                ),
                child: Icon(Icons.cloud_upload_outlined,
                    color: ink.onAccent, size: 26),
              ),
              const SizedBox(height: AppSpacing.md),
              Text('Drop files or tap to choose',
                  style: AppText.cardTitle.copyWith(color: ink.ink)),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Links are created instantly. Password, expiry and download\nlimits can be set before you share.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, height: 1.4, color: ink.muted),
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: onPick,
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('Choose files'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dashed rounded rectangle — the drop zone's only decoration.
class _DashedRectPainter extends CustomPainter {
  final Color color;
  final double radius;
  const _DashedRectPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final rect = Rect.fromLTWH(0.7, 0.7, size.width - 1.4, size.height - 1.4);
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
          rect, Radius.circular(radius)));
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      const dash = 7.0;
      const gap = 5.0;
      while (distance < metric.length) {
        final end = (distance + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRectPainter old) =>
      old.color != color || old.radius != radius;
}

/// Section label above a group of cards ("UPLOADING").
class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(0, AppSpacing.lg, 0, AppSpacing.sm),
        child: Text(label.toUpperCase(),
            style: AppText.microLabel.copyWith(color: InkPalette.of(context).faint)),
      );
}

/// Circular outlined button used in the header (event log).
class _IconPillButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  const _IconPillButton(
      {required this.icon, required this.tooltip, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final ink = InkPalette.of(context);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: ink.raised,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, size: 20, color: ink.ink),
          ),
        ),
      ),
    );
  }
}
