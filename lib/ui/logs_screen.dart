import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flashshare/logs/log_store.dart';
import 'package:flashshare/ui/confirm_dialog.dart';
import 'package:flashshare/ui/theme.dart';
import 'package:flashshare/ui/toast.dart';

/// The in-app event log: every action, network call, warning and crash the app
/// recorded — including the ones that would otherwise vanish (uncaught errors,
/// framework build failures, cancelled uploads).
///
/// Reached from the header button, Settings ▸ Diagnostics, or a long-press on
/// the "Flash Share" wordmark.
class LogsScreen extends StatefulWidget {
  final LogStore store;
  const LogsScreen({super.key, required this.store});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  LogLevel? _filter; // null = all
  final _expanded = <int>{};

  List<LogEntry> get _visible {
    // Newest first: what just happened is what you want to read, and
    // auto-scrolling on every line made the screen unreadable during uploads.
    final all = widget.store.entries.reversed;
    return _filter == null
        ? all.toList()
        : all.where((e) => e.level == _filter).toList();
  }

  int _countOf(LogLevel level) =>
      widget.store.entries.where((e) => e.level == level).length;

  Future<void> _confirmClear() async {
    final errors = _countOf(LogLevel.error);
    final total = widget.store.entries.length;
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Clear the event log?',
      message: '$total entries will be deleted'
          '${errors > 0 ? ', including $errors error(s) you may still want to copy' : ''}.',
      confirmLabel: 'Clear',
      destructive: true,
    );
    if (!confirmed) return;
    // The clear is itself recorded: a log that silently wipes itself hides
    // that anything was ever in it.
    widget.store.clear();
    AppLog.info('Event log cleared by user ($total entries dropped)',
        source: 'logs');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Event log'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_all_outlined),
            tooltip: 'Copy all',
            onPressed: widget.store.entries.isEmpty
                ? null
                : () {
                    Clipboard.setData(ClipboardData(
                        text: _allEntries
                            .map((e) => e.copyText())
                            .join('\n\n')));
                    AppLog.info('All logs copied to the clipboard',
                        source: 'logs');
                    showToast(context, 'All logs copied');
                  },
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Clear logs',
            onPressed: widget.store.entries.isEmpty ? null : _confirmClear,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) {
          final entries = _visible;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final (level, label) in [
                        (null, 'All'),
                        (LogLevel.info, 'General'),
                        (LogLevel.warning, 'Warnings'),
                        (LogLevel.error, 'Errors'),
                        (LogLevel.debug, 'Verbose'),
                      ])
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: FilterChip(
                            label: Text(level == null
                                ? label
                                : '$label ${_countOf(level)}'),
                            selected: _filter == level,
                            onSelected: (_) => setState(
                                () => _filter = (_filter == level ? null : level)),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${widget.store.entries.length} entries recorded — newest first',
                    style: TextStyle(
                        fontSize: 12, color: InkPalette.of(context).faint),
                  ),
                ),
              ),
              Expanded(
                child: entries.isEmpty
                    ? Center(
                        child: Text(
                          'No logs yet.',
                          style: TextStyle(color: Theme.of(context).hintColor),
                        ),
                      )
                    : ListView.builder(
                        itemCount: entries.length,
                        itemBuilder: (context, i) {
                          final e = entries[i];
                          return _LogTile(
                            entry: e,
                            expanded: _expanded.contains(e.timestamp),
                            onTap: e.stack != null
                                ? () => setState(() {
                                      _expanded.toggle(e.timestamp);
                                    })
                                : null,
                            onCopy: () {
                              Clipboard.setData(
                                  ClipboardData(text: e.copyText()));
                              showToast(context, 'Copied');
                            },
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// All entries regardless of filter — used by copy-all.
  List<LogEntry> get _allEntries => widget.store.entries;
}

extension _ToggleOnSet on Set<int> {
  void toggle(int v) => contains(v) ? remove(v) : add(v);
}

class _LogTile extends StatelessWidget {
  final LogEntry entry;
  final bool expanded;
  final VoidCallback? onTap; // null when there's no stack to expand
  final VoidCallback onCopy;

  const _LogTile(
      {required this.entry,
      required this.expanded,
      this.onTap,
      required this.onCopy});

  @override
  Widget build(BuildContext context) {
    final ink = InkPalette.of(context);
    final (label, color) = switch (entry.level) {
      LogLevel.error => ('ERROR', ink.danger),
      LogLevel.warning => ('WARN', ink.warn),
      LogLevel.info => ('INFO', ink.ink),
      LogLevel.debug => ('TRACE', ink.faint),
    };
    final ts = DateTime.fromMillisecondsSinceEpoch(entry.timestamp);
    final tsText =
        '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}:${ts.second.toString().padLeft(2, '0')}';

    return Column(
      children: [
        ListTile(
          onTap: onTap,
          dense: true,
          leading: Text(tsText,
              style: TextStyle(
                  fontFamily: 'monospace', fontSize: 11, color: ink.faint)),
          title: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(label,
                    style: AppText.microLabel
                        .copyWith(fontSize: 9, color: color, letterSpacing: 0.6)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.message,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12.5,
                          color: entry.level == LogLevel.debug
                              ? ink.muted
                              : ink.ink),
                    ),
                    if (entry.source != null)
                      Text(entry.source!,
                          style: AppText.microLabel
                              .copyWith(fontSize: 8.5, color: ink.faint)),
                  ],
                ),
              ),
            ],
          ),
          trailing: IconButton(
            icon: const Icon(Icons.copy_outlined, size: 18),
            tooltip: 'Copy',
            onPressed: onCopy,
          ),
        ),
        if (expanded && entry.stack != null)
          Container(
            width: double.infinity,
            color: ink.raised,
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Stack trace',
                    style: AppText.microLabel.copyWith(color: ink.faint)),
                const SizedBox(height: 4),
                SelectableText(
                  entry.stack!,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
