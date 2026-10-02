import 'package:flutter/material.dart';
import 'package:flashshare/api/storage_client.dart';
import 'package:flashshare/logs/log_store.dart';
import 'package:flashshare/ui/settings_store.dart';
import 'package:flashshare/ui/theme.dart';

/// The Settings tab: appearance, background uploads, quota and the event log.
class SettingsTab extends StatefulWidget {
  final SettingsStore store;
  final StorageClient client;
  final void Function(ThemeMode mode) onChanged;

  /// Opens the event log. Every entry the app records is reachable from here.
  final VoidCallback onOpenLogs;
  final int logCount;

  const SettingsTab({
    super.key,
    required this.store,
    required this.client,
    required this.onChanged,
    required this.onOpenLogs,
    this.logCount = 0,
  });

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  Map<String, dynamic>? _quota;
  bool _loading = false;
  String? _quotaError;

  @override
  void initState() {
    super.initState();
    if (widget.store.showQuota) _refreshQuota();
  }

  @override
  Widget build(BuildContext context) {
    final current = switch (widget.store.themeMode) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    final options = [
      (mode: ThemeMode.system, label: 'System'),
      (mode: ThemeMode.light, label: 'Light'),
      (mode: ThemeMode.dark, label: 'Dark'),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter, 4, AppSpacing.gutter, AppSpacing.xl),
      children: [
        const _SectionLabel('Appearance'),
        Card(
          margin: EdgeInsets.zero,
          child: RadioGroup<ThemeMode>(
            groupValue: current,
            onChanged: (m) {
              if (m == null) return;
              AppLog.info('Theme mode picked: ${m.name}', source: 'ui.settings');
              widget.onChanged(m);
              widget.store.setThemeMode(switch (m) {
                ThemeMode.light => 'light',
                ThemeMode.dark => 'dark',
                _ => 'system',
              });
            },
            child: Column(
              children: options
                  .map((o) => RadioListTile<ThemeMode>(
                        title: Text(o.label),
                        value: o.mode,
                      ))
                  .toList(),
            ),
          ),
        ),
        const _SectionLabel('Background uploads'),
        Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: const Icon(Icons.cloud_upload_outlined),
            title: const Text('Keep uploading when minimized'),
          ),
        ),
        const _SectionLabel('Usage'),
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.data_usage_outlined),
                title: const Text('Show upload quota'),
                subtitle: const Text('Remaining bandwidth: 100 GB / 24 h.'),
                value: widget.store.showQuota,
                onChanged: (v) {
                  AppLog.info('Upload quota display → $v', source: 'ui.settings');
                  setState(() {
                    widget.store.setShowQuota(v);
                    if (v) {
                      _loading = true;
                      _quotaError = null;
                    } else {
                      _quota = null;
                    }
                  });
                  if (v) _refreshQuota();
                },
              ),
              if (widget.store.showQuota) ..._quotaTile(),
            ],
          ),
        ),
        const _SectionLabel('Diagnostics'),
        Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: const Icon(Icons.terminal_outlined),
            title: const Text('Event log'),
            subtitle: Text(
                '${widget.logCount} recorded event${widget.logCount == 1 ? '' : 's'}'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: widget.onOpenLogs,
          ),
        ),
      ],
    );
  }

  List<Widget> _quotaTile() {
    if (_loading) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (_quotaError != null) {
      return [
        ListTile(
          leading: Icon(Icons.error_outline,
              color: Theme.of(context).colorScheme.error),
          title: const Text('Could not load quota'),
          subtitle: Text(_quotaError!),
          trailing: IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshQuota,
          ),
        ),
      ];
    }
    if (_quota == null) return [];
    final q = _quota!;
    if (q['authenticated'] == true) {
      // Authenticated responses carry no GB fields — unlimited, plan only.
      return [
        ListTile(
          leading: const Icon(Icons.workspace_premium_outlined),
          title: const Text('No upload quota'),
          subtitle: Text('Signed in — ${q['plan'] ?? 'unlimited'} plan.'),
        ),
      ];
    }
    final used = (q['used_gb'] as num?)?.toDouble() ?? 0;
    final limit = (q['limit_gb'] as num?)?.toDouble() ?? 100;
    final pct = limit > 0 ? (used / limit).clamp(0.0, 1.0) : 0.0;
    return [
      const Divider(height: 1, indent: 16, endIndent: 16),
      Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Upload bandwidth used (24 h)',
                    style: Theme.of(context).textTheme.bodyMedium),
                Text('${used.toStringAsFixed(2)} / ${limit.toStringAsFixed(0)} GB',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 8,
                color: pct > 0.9
                    ? InkPalette.of(context).danger
                    : InkPalette.of(context).ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Remaining: ${(q['remaining_gb'] as num?)?.toStringAsFixed(2) ?? '—'} GB',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).hintColor),
            ),
          ],
        ),
      ),
    ];
  }

  Future<void> _refreshQuota() async {
    AppLog.debug('Quota refresh requested', source: 'ui.settings');
    setState(() => _loading = true);
    try {
      final q = await widget.client.bandwidthStatus();
      if (mounted) setState(() { _quota = q; _loading = false; _quotaError = null; });
    } catch (e, st) {
      AppLog.error('Quota fetch failed: $e', stack: st, source: 'settings');
      if (mounted) {
        setState(() {
          _loading = false;
          _quotaError = e.toString();
        });
      }
    }
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, AppSpacing.lg, 4, AppSpacing.sm),
        child: Text(text.toUpperCase(),
            style: AppText.microLabel
                .copyWith(color: InkPalette.of(context).faint)),
      );
}
