import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flashshare/files/app_file.dart';
import 'package:flashshare/models.dart';
import 'package:flashshare/share/share_handler.dart';
import 'package:flashshare/storage/history_store.dart';
import 'package:flashshare/ui/multi_file_dialog.dart';
import 'package:flashshare/ui/settings_store.dart';
import 'package:flashshare/ui/settings_tab.dart';
import 'package:flashshare/ui/toast.dart';
import 'package:flashshare/ui/upload_tile.dart';
import 'package:flashshare/upload/background_service.dart';
import 'package:flashshare/upload/upload_engine.dart';

class HomePage extends StatefulWidget {
  final HistoryStore store;
  final SettingsStore settings;
  final UploadEngine engine;
  final void Function(ThemeMode mode) onThemeMode;
  const HomePage(
      {super.key,
      required this.store,
      required this.settings,
      required this.engine,
      required this.onThemeMode});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<UploadProgress> _active = [];
  List<HistoryEntry> _history = [];
  late final ShareHandler _share;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _history = widget.store.getAll();
    widget.engine.progress.listen((p) {
      if (!mounted) return;
      setState(() {
        _active.removeWhere((a) => a.key == p.key);
        if (p.state != UploadState.done) {
          _active.add(p);
        } else {
          _history = widget.store.getAll();
        }
      });
    });
    _share = ShareHandler((files) => _receive(files));
    _share.init();
  }

  Future<void> _pick() async {
    final res = await FilePicker.pickFiles(allowMultiple: true, withData: kIsWeb);
    if (res == null) return;
    final files = res.files.map((pf) {
      if (pf.bytes != null) return BytesFile(pf.name, pf.bytes!);
      return fileFromPath(pf.path!);
    }).toList();
    if (files.isNotEmpty) await _receive(files);
  }

  Future<void> _receive(List<AppFile> files) async {
    try {
      final mode = files.length > 1
          ? await MultiFileDialog.show(context, files.length)
          : UploadMode.separate;
      if (mode == null) return;
      await startUploadService();
      await widget.engine.enqueue(files, mode);
    } catch (e) {
      if (mounted) showToast(context, 'Upload failed: $e');
    }
  }

  Future<void> _delete(HistoryEntry e) async {
    try {
      if (e.kind == 'collection') {
        await widget.engine.client.deleteCollection(e.id, e.ownerToken);
      } else {
        await widget.engine.client.deleteFile(e.id, e.ownerToken);
      }
      await widget.store.remove(e.id);
      if (mounted) setState(() => _history = widget.store.getAll());
    } catch (err) {
      if (mounted) showToast(context, 'Delete failed: $err');
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      _ShareTab(
        active: _active,
        history: _history,
        onPick: _pick,
        onCopy: _copy,
        onDelete: _delete,
        onCancel: widget.engine.cancel,
        onViewAll: () => setState(() => _tab = 1),
      ),
      _HistoryTab(
        history: _history,
        onCopy: _copy,
        onDelete: _delete,
      ),
      SettingsTab(
        store: widget.settings,
        onChanged: widget.onThemeMode,
      ),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              Theme.of(context).brightness == Brightness.dark
                  ? 'assets/logo_dark.png'
                  : 'assets/logo_light.png',
              height: 28,
              width: 28,
            ),
            const SizedBox(width: 12),
            Text(
              'Flash Share',
              style: Theme.of(context).appBarTheme.titleTextStyle,
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              showAboutDialog(
                context: context,
                applicationName: 'Flash Share',
                applicationVersion: '1.0.0',
                applicationIcon: const Icon(Icons.bolt, size: 48),
                children: [
                  const Text('Simple, secure, and ephemeral file sharing.'),
                ],
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: IndexedStack(index: _tab, children: tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.share_outlined), 
              selectedIcon: Icon(Icons.share),
              label: 'Share'),
          NavigationDestination(
              icon: Icon(Icons.history_outlined), 
              selectedIcon: Icon(Icons.history),
              label: 'History'),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined), 
              selectedIcon: Icon(Icons.settings),
              label: 'Settings'),
        ],
      ),
    );
  }

  void _copy(HistoryEntry e) {
    Clipboard.setData(ClipboardData(text: e.url));
    showToast(context, 'Link copied');
  }
}

class _ShareTab extends StatelessWidget {
  final List<UploadProgress> active;
  final List<HistoryEntry> history;
  final VoidCallback onPick;
  final void Function(HistoryEntry) onCopy;
  final void Function(HistoryEntry) onDelete;
  final void Function(String key) onCancel;
  final VoidCallback onViewAll;
  const _ShareTab(
      {required this.active,
      required this.history,
      required this.onPick,
      required this.onCopy,
      required this.onDelete,
      required this.onCancel,
      required this.onViewAll});

  @override
  Widget build(BuildContext context) {
    final hasActive = active.isNotEmpty;
    final recent = history.take(5).toList();
    final hasHistory = recent.isNotEmpty;
    final hasMore = history.length > 5;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _UploadSection(onPick: onPick)),
        if (hasActive)
          const SliverToBoxAdapter(
              child: _SectionHeader(
                  icon: Icons.cloud_upload_outlined, label: 'Active uploads')),
        if (hasActive)
          SliverPadding(
            padding: const EdgeInsets.only(bottom: 8),
            sliver: SliverList(
              delegate: SliverChildListDelegate(active
                  .map((p) => ActiveTile(
                      p: p, onCancel: () => onCancel(p.key)))
                  .toList()),
            ),
          ),
        if (hasHistory)
          const SliverToBoxAdapter(
              child: _SectionHeader(
                  icon: Icons.history_outlined, label: 'Recent')),
        if (hasHistory)
          SliverList(
            delegate: SliverChildListDelegate(recent
                .map((e) => HistoryTile(
                      e: e,
                      onCopy: () => onCopy(e),
                      onDelete: () => onDelete(e),
                    ))
                .toList()),
          ),
        if (hasMore)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: TextButton.icon(
                  onPressed: onViewAll,
                  icon: const Icon(Icons.arrow_forward, size: 16),
                  label: const Text('View Full History'),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
          ),
        if (!hasActive && !hasHistory)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history_toggle_off, size: 64, color: Theme.of(context).hintColor.withValues(alpha: 0.2)),
                  const SizedBox(height: 16),
                  Text(
                    'No recent activity',
                    style: TextStyle(color: Theme.of(context).hintColor),
                  ),
                ],
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    );
  }
}

class _UploadSection extends StatelessWidget {
  final VoidCallback onPick;
  const _UploadSection({required this.onPick});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Container(
        height: 220,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              scheme.primary,
              scheme.primary.withValues(alpha: 0.8),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: scheme.primary.withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Material(
          color: scheme.surface.withValues(alpha: 0),
          child: InkWell(
            onTap: onPick,
            borderRadius: BorderRadius.circular(32),
            child: Stack(
              children: [
                Positioned(
                  right: -20,
                  bottom: -20,
                  child: Icon(
                    Icons.bolt,
                    size: 160,
                    color: scheme.onPrimary.withValues(alpha: 0.1),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: scheme.onPrimary.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(Icons.add_rounded, color: scheme.onPrimary, size: 28),
                      ),
                      const Spacer(),
                      Text(
                        'Share New Files',
                        style: TextStyle(
                          color: scheme.onPrimary,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Instant, secure, and ephemeral.',
                        style: TextStyle(
                          color: scheme.onPrimary.withValues(alpha: 0.8),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HistoryTab extends StatelessWidget {
  final List<HistoryEntry> history;
  final void Function(HistoryEntry) onCopy;
  final void Function(HistoryEntry) onDelete;
  const _HistoryTab(
      {required this.history, required this.onCopy, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history_outlined, size: 64, color: Theme.of(context).hintColor.withValues(alpha: 0.2)),
            const SizedBox(height: 16),
            const Text('No files shared yet.'),
          ],
        ),
      );
    }
    return CustomScrollView(
      slivers: [
        const SliverToBoxAdapter(
            child: _SectionHeader(icon: Icons.history_outlined, label: 'Full History')),
        SliverList(
          delegate: SliverChildListDelegate(history
              .map((e) => HistoryTile(
                    e: e,
                    onCopy: () => onCopy(e),
                    onDelete: () => onDelete(e),
                  ))
              .toList()),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectionHeader({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
        child: Row(
          children: [
            Text(label.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).hintColor,
                    )),
          ],
        ),
      );
}
