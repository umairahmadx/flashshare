import 'package:flutter/material.dart';
import 'package:flashshare/logs/log_store.dart';
import 'package:flashshare/models.dart';
import 'package:flashshare/ui/theme.dart';
import 'package:flashshare/ui/toast.dart';

/// Bottom sheet for per-share options: password, expiry, download cap.
///
/// Shown at share time (returns options for the new upload) and from History
/// (applies them live to an existing share). Returns null when dismissed —
/// callers treat that as "cancel the share", which is why the sheet has an
/// explicit Cancel rather than relying on a swipe-away.
class ShareOptionsSheet extends StatefulWidget {
  final int fileCount;
  final HistoryEntry? editing; // non-null => editing an existing share

  const ShareOptionsSheet({super.key, required this.fileCount, this.editing});

  static Future<ShareOptions?> show(BuildContext context,
      {int fileCount = 1, HistoryEntry? editing}) {
    AppLog.debug(
        'Share options sheet opened (${editing == null ? 'new share' : 'editing ${editing.id}'})',
        source: 'ui.options');
    return showModalBottomSheet<ShareOptions>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ShareOptionsSheet(fileCount: fileCount, editing: editing),
    );
  }

  @override
  State<ShareOptionsSheet> createState() => _ShareOptionsSheetState();
}

class _ShareOptionsSheetState extends State<ShareOptionsSheet> {
  final _password = TextEditingController();
  bool _passwordOn = false;
  int? _expiryDays; // null = server default
  bool _capOn = false;
  int _cap = 5;

  /// The expiry endpoint takes whole days only, so the presets are whole days.
  /// Anything finer would be a promise the server cannot keep.
  static const _expiryPresets = <int?>[null, 1, 2, 3, 5, 7];

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    if (e != null) {
      _passwordOn = e.locked;
      final raw = e.expiresAt;
      final expiry = raw == null ? null : DateTime.tryParse(raw);
      if (expiry != null) {
        _expiryDays = expiry
            .difference(DateTime.now())
            .inDays
            .clamp(1, 7); // presets are 1..7; clamp rather than show a lie
      }
    }
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  void _save() {
    final password = _passwordOn ? _password.text : null;
    if (password != null && (password.length < 4 || password.length > 100)) {
      AppLog.warning(
          'Share options rejected: password length ${password.length} is '
          'outside 4-100',
          source: 'ui.options');
      showToast(context, 'Password must be 4-100 characters');
      return;
    }
    if (_capOn && (_cap < 1 || _cap > 1000)) {
      AppLog.warning('Share options rejected: download cap $_cap',
          source: 'ui.options');
      showToast(context, 'Max downloads must be 1-1000');
      return;
    }
    final options = ShareOptions(
      password: password,
      expiryDays: _expiryDays,
      maxDownloads: _capOn ? _cap : null,
    );
    AppLog.info(
        'Share options saved — ${options.isEmpty ? 'all defaults' : 'locked=${password != null}, expiry=${_expiryDays == null ? 'server default' : '$_expiryDays d'}, cap=${_capOn ? '$_cap' : 'none'}'}',
        source: 'ui.options');
    Navigator.pop(context, options);
  }

  void _cancel() {
    AppLog.debug('Share options sheet cancelled', source: 'ui.options');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final ink = InkPalette.of(context);
    final editing = widget.editing != null;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding:
              const EdgeInsets.fromLTRB(AppSpacing.gutter, 0, AppSpacing.gutter, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      editing
                          ? 'Share options'
                          : 'Options for ${widget.fileCount} '
                              'file${widget.fileCount > 1 ? 's' : ''}',
                      style:
                          AppText.cardTitle.copyWith(color: ink.ink, fontSize: 17),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    tooltip: 'Cancel',
                    onPressed: _cancel,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              _OptionTile(
                icon: Icons.lock_outline_rounded,
                title: 'Password protect',
                subtitle: 'The link asks for a password before downloading.',
                value: _passwordOn,
                onChanged: (v) {
                  AppLog.debug('Password option → $v', source: 'ui.options');
                  setState(() => _passwordOn = v);
                },
              ),
              if (_passwordOn)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: TextField(
                    controller: _password,
                    obscureText: true,
                    autofocus: true,
                    decoration:
                        const InputDecoration(hintText: 'Password (4-100 characters)'),
                  ),
                ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Text('EXPIRES AFTER',
                    style: AppText.microLabel.copyWith(color: ink.faint)),
              ),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final d in _expiryPresets)
                    _OptionPill(
                      label: switch (d) {
                        null => 'Server default',
                        1 => '1 day',
                        _ => '$d days',
                      },
                      selected: _expiryDays == d,
                      onTap: () {
                        AppLog.debug(
                            'Expiry preset → ${d == null ? 'server default' : '$d d'}',
                            source: 'ui.options');
                        setState(() => _expiryDays = d);
                      },
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              _OptionTile(
                icon: Icons.download_rounded,
                title: 'Limit downloads',
                subtitle: 'The link stops working after N downloads.',
                value: _capOn,
                onChanged: (v) {
                  AppLog.debug('Download cap option → $v', source: 'ui.options');
                  setState(() => _capOn = v);
                },
              ),
              if (_capOn)
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: _cap.toDouble().clamp(1, 50),
                        min: 1,
                        max: 50,
                        divisions: 49,
                        label: '$_cap',
                        onChanged: (v) => setState(() => _cap = v.round()),
                      ),
                    ),
                    SizedBox(
                      width: 84,
                      child: Text('$_cap download${_cap == 1 ? '' : 's'}',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12.5, color: ink.muted)),
                    ),
                  ],
                ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _cancel,
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: FilledButton(
                      onPressed: _save,
                      child: Text(editing ? 'Apply' : 'Share'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}


/// A toggle row with icon, title and one-line explanation.
class _OptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _OptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final ink = InkPalette.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: ink.raised,
        borderRadius: BorderRadius.circular(AppRadius.field),
        border: Border.all(color: ink.line),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: ink.ink),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: AppText.cardTitle.copyWith(color: ink.ink)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(fontSize: 12, color: ink.muted)),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// Selectable preset pill inside the sheet.
class _OptionPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _OptionPill(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final ink = InkPalette.of(context);
    final fg = selected ? ink.onAccent : ink.ink;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? ink.accent : ink.card,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: selected ? ink.accent : ink.line),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
      ),
    );
  }
}

