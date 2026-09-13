import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flashshare/logs/log_store.dart';
import 'package:flashshare/ui/theme.dart';
import 'package:flashshare/ui/toast.dart';

/// In-app log viewer: general / warning / error entries, with stack traces
/// and copy buttons. Reached from the AppBar's terminal icon.
class LogsScreen extends StatefulWidget {
  final LogStore store;
  const LogsScreen({super.key, required this.store});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  LogLevel? _filter; // null = all
  final _expanded = <int>{};

  List<LogEntry> get _visible => _filter == null
      ? widget.store.entries
      : widget.store.entries.where((e) => e.level == _filter).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Logs'),
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
                    showToast(context, 'All logs copied');
                  },
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Clear logs',
            onPressed:
                widget.store.entries.isEmpty ? null : widget.store.clear,
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
                      ])
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: FilterChip(
                            label: Text(label),
                            selected: _filter == level,
                            onSelected: (_) => setState(
                                () => _filter = (_filter == level ? null : level)),
                          ),
                        ),
                    ],
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
    final scheme = Theme.of(context).colorScheme;
    final (label, color) = switch (entry.level) {
      LogLevel.error => ('ERROR', scheme.error),
      LogLevel.warning => ('WARN', AppColors.warning),
      LogLevel.info => ('INFO', scheme.primary),
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
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).hintColor)),
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
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: color, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  entry.message,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
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
            color: scheme.surfaceContainerHighest,
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Stack trace',
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: Theme.of(context).hintColor)),
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
