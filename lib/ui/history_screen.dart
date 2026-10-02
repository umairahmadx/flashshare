import 'package:flutter/material.dart';
import 'package:flashshare/logs/log_store.dart';
import 'package:flashshare/models.dart';
import 'package:flashshare/ui/history_filter.dart';
import 'package:flashshare/ui/share_card.dart';
import 'package:flashshare/ui/theme.dart';

/// The History tab: search, filters, honest stats and the share cards.
///
/// The rules live in [HistoryFilter] (pure Dart, unit-tested); this is the view
/// plus the log line each interaction produces.
class HistoryScreen extends StatefulWidget {
  final List<HistoryEntry> entries;
  final void Function(HistoryEntry e) onCopy;
  final void Function(HistoryEntry e) onShare;
  final void Function(HistoryEntry e) onQr;
  final void Function(HistoryEntry e) onEditOptions;
  final void Function(HistoryEntry e) onDelete;
  final VoidCallback onPick;

  const HistoryScreen({
    super.key,
    required this.entries,
    required this.onCopy,
    required this.onShare,
    required this.onQr,
    required this.onEditOptions,
    required this.onDelete,
    required this.onPick,
  });

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _search = TextEditingController();
  HistoryKindFilter _kind = HistoryKindFilter.all;
  String? _category;
  HistorySort _sort = HistorySort.newest;
  bool _hideExpired = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<HistoryEntry> get _visible => HistoryFilter.apply(
        widget.entries,
        query: _search.text,
        kind: _kind,
        category: _category,
        sort: _sort,
        hideExpired: _hideExpired,
      );

  void _log(String what) => AppLog.debug(what, source: 'ui.history');

  void _resetFilters() {
    _log('Filters reset');
    setState(() {
      _search.clear();
      _kind = HistoryKindFilter.all;
      _category = null;
      _hideExpired = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ink = InkPalette.of(context);
    final visible = _visible;
    // Stats always describe the whole library — a search must not silently
    // rewrite "3 expired" into "0 expired".
    final stats = HistoryFilter.summarize(widget.entries);
    final filtering = _search.text.isNotEmpty ||
        _kind != HistoryKindFilter.all ||
        _category != null ||
        _hideExpired;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter, 0, AppSpacing.gutter, AppSpacing.md),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            onSubmitted: (v) => _log('Search submitted: "$v"'),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded, size: 20),
              hintText: 'Search shares',
            ),
          ),
        ),
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
            children: [
              for (final k in HistoryKindFilter.values)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: _Pill(
                    label: switch (k) {
                      HistoryKindFilter.all => 'All',
                      HistoryKindFilter.files => 'Files',
                      HistoryKindFilter.collections => 'Collections',
                    },
                    selected: _kind == k,
                    onTap: () {
                      _log('Kind filter → ${k.name}');
                      setState(() => _kind = k);
                    },
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: _Pill(
                  label: _hideExpired ? 'Hiding expired' : 'Showing expired',
                  selected: _hideExpired,
                  onTap: () {
                    _log('Hide expired → ${!_hideExpired}');
                    setState(() => _hideExpired = !_hideExpired);
                  },
                ),
              ),
              _SortPill(
                sort: _sort,
                onPicked: (s) {
                  _log('Sort → ${s.name}');
                  setState(() => _sort = s);
                },
              ),
            ],
          ),
        ),
        // The kind/expiry/sort row and the file-type row are two distinct
        // filter groups — give them breathing room so the category chips
        // don't read as a continuation of the first row.
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.gutter, vertical: 4),
            children: [
              _Pill(
                label: 'Any type',
                selected: _category == null,
                onTap: () {
                  _log('Category filter cleared');
                  setState(() => _category = null);
                },
              ),
              for (final c in HistoryFilter.categoryOrder)
                Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.sm),
                  child: _Pill(
                    icon: AppColors.fileCategories[c]!.icon,
                    label: c,
                    selected: _category == c,
                    onTap: () {
                      _log('Category filter → $c');
                      setState(() => _category = c);
                    },
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.sm,
              AppSpacing.gutter, AppSpacing.md),
          child: Text(
            filtering
                ? '${visible.length} of ${widget.entries.length} shares'
                : '${stats.all.count} shares · ${formatBytes(stats.all.bytes)} · '
                    '${stats.active} live · ${stats.expired} expired',
            style: TextStyle(fontSize: 12, color: ink.faint),
          ),
        ),
        Expanded(
          child: widget.entries.isEmpty
              ? _EmptyLibrary(onPick: widget.onPick)
              : visible.isEmpty
                  ? _NoMatches(onReset: _resetFilters)
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 0,
                          AppSpacing.gutter, AppSpacing.lg),
                      itemCount: visible.length,
                      itemBuilder: (_, i) {
                        final e = visible[i];
                        return ShareCard(
                          entry: e,
                          onCopy: () => widget.onCopy(e),
                          onShare: () => widget.onShare(e),
                          onQr: () => widget.onQr(e),
                          onEditOptions: () => widget.onEditOptions(e),
                          onDelete: () => widget.onDelete(e),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}


/// Filter pill. Selected = filled ink, unselected = outlined.
class _Pill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;
  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final ink = InkPalette.of(context);
    final fg = selected ? ink.onAccent : ink.ink;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? ink.accent : ink.card,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: selected ? ink.accent : ink.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 5),
            ],
            Text(
              label.toUpperCase(),
              style: AppText.microLabel.copyWith(
                  fontSize: 10, color: fg, letterSpacing: 0.9),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sort control — a pill that opens a menu, so the pill row stays one line.
class _SortPill extends StatelessWidget {
  final HistorySort sort;
  final ValueChanged<HistorySort> onPicked;
  const _SortPill({required this.sort, required this.onPicked});

  static const _labels = {
    HistorySort.newest: 'Newest',
    HistorySort.oldest: 'Oldest',
    HistorySort.largest: 'Largest',
    HistorySort.expiringSoon: 'Expiring',
  };

  @override
  Widget build(BuildContext context) {
    final ink = InkPalette.of(context);
    return PopupMenuButton<HistorySort>(
      tooltip: 'Sort shares',
      initialValue: sort,
      color: ink.card,
      onSelected: onPicked,
      itemBuilder: (_) => [
        for (final s in HistorySort.values)
          PopupMenuItem(value: s, child: Text(_labels[s]!)),
      ],
      // `child` replaces `icon` — PopupMenuButton asserts they are exclusive.
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: ink.card,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: ink.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.swap_vert_rounded, size: 14, color: ink.muted),
            const SizedBox(width: 5),
            Text(_labels[sort]!,
                style: AppText.microLabel
                    .copyWith(fontSize: 10, color: ink.ink, letterSpacing: 0.9)),
          ],
        ),
      ),
    );
  }
}

/// Nothing shared yet.
class _EmptyLibrary extends StatelessWidget {
  final VoidCallback onPick;
  const _EmptyLibrary({required this.onPick});

  @override
  Widget build(BuildContext context) {
    final ink = InkPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history_rounded, size: 44, color: ink.faint),
            const SizedBox(height: AppSpacing.md),
            Text('No shares yet',
                style: AppText.cardTitle.copyWith(color: ink.ink)),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Files you share appear here with their link, expiry and '
              'download settings.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: ink.muted),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Share a file'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Filters hid everything — offer exactly one way out.
class _NoMatches extends StatelessWidget {
  final VoidCallback onReset;
  const _NoMatches({required this.onReset});

  @override
  Widget build(BuildContext context) {
    final ink = InkPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.filter_alt_off_outlined, size: 40, color: ink.faint),
            const SizedBox(height: AppSpacing.md),
            Text('No shares match these filters',
                style: AppText.cardTitle.copyWith(color: ink.ink)),
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton(onPressed: onReset, child: const Text('Clear filters')),
          ],
        ),
      ),
    );
  }
}

