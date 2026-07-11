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
    final mode = files.length > 1
        ? await MultiFileDialog.show(context, files.length)
        : UploadMode.separate;
    if (mode == null) return;
    await widget.engine.enqueue(files, mode);
    await startUploadService();
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
      appBar: AppBar(title: const Text('Flash Share')),
      body: IndexedStack(index: _tab, children: tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.share_outlined), label: 'Share'),
          NavigationDestination(
              icon: Icon(Icons.history_outlined), label: 'History'),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined), label: 'Settings'),
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
  const _ShareTab(
      {required this.active,
      required this.history,
      required this.onPick,
      required this.onCopy,
      required this.onDelete,
      required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final hasActive = active.isNotEmpty;
    final hasHistory = history.isNotEmpty;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: CustomScrollView(
          slivers: [
            if (hasActive)
              const SliverToBoxAdapter(
                  child: _SectionHeader(
                      icon: Icons.cloud_upload_outlined, label: 'Active uploads')),
            if (hasActive)
              SliverList(
                delegate: SliverChildListDelegate(active
                    .map((p) => ActiveTile(
                        p: p, onCancel: () => onCancel(p.key)))
                    .toList()),
              ),
            if (hasHistory)
              const SliverToBoxAdapter(
                  child: _SectionHeader(
                      icon: Icons.history_outlined, label: 'Recent')),
            if (hasHistory)
              SliverList(
                delegate: SliverChildListDelegate(history
                    .map((e) => HistoryTile(
                          e: e,
                          onCopy: () => onCopy(e),
                          onDelete: () => onDelete(e),
                        ))
                    .toList()),
              ),
            if (!hasActive && !hasHistory)
              SliverToBoxAdapter(child: _EmptyState(onPick: onPick)),
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
          ],
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
      return const Center(child: Text('No files shared yet.'));
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(
                child:
                    _SectionHeader(icon: Icons.history_outlined, label: 'Recent')),
            SliverList(
              delegate: SliverChildListDelegate(history
                  .map((e) => HistoryTile(
                        e: e,
                        onCopy: () => onCopy(e),
                        onDelete: () => onDelete(e),
                      ))
                  .toList()),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectionHeader({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text(label.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).hintColor,
                    )),
          ],
        ),
      );
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onPick;
  const _EmptyState({required this.onPick});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(32, 48, 32, 32),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.bolt,
                  size: 48,
                  color: Theme.of(context).colorScheme.onPrimaryContainer),
            ),
            const SizedBox(height: 24),
            Text('Nothing shared yet',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Pick files from your device or share them in from another app to get started.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Theme.of(context).hintColor),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.share),
              label: const Text('Share files'),
            ),
          ],
        ),
      );
}
