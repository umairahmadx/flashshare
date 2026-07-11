import 'package:flutter/material.dart';
import 'package:flashshare/ui/settings_store.dart';

class SettingsTab extends StatelessWidget {
  final SettingsStore store;
  final void Function(ThemeMode mode) onChanged;
  const SettingsTab({super.key, required this.store, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final current = switch (store.themeMode) {
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
      padding: const EdgeInsets.all(16),
      children: [
        const _SectionTitle('Appearance'),
        ...options.map((o) => RadioListTile<ThemeMode>(
              title: Text(o.label),
              value: o.mode,
              groupValue: current,
              onChanged: (m) {
                if (m == null) return;
                onChanged(m);
                store.setThemeMode(switch (m) {
                  ThemeMode.light => 'light',
                  ThemeMode.dark => 'dark',
                  _ => 'system',
                });
              },
            )),
        const Divider(),
        const _SectionTitle('Background uploads'),
        const ListTile(
          leading: Icon(Icons.cloud_upload_outlined),
          title: Text('Keep uploading when app is minimized'),
          subtitle: Text('Uses an Android foreground service. Best-effort on web/iOS.'),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(text.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).hintColor,
                )),
      );
}
