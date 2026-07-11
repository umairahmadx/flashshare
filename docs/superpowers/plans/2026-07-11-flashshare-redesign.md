# FlashShare Redesign (Blue / AMOLED / Background Uploads) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle FlashShare to a blue / AMOLED-black identity with all colors centralized in one theme file, a 3-tab bottom-nav layout, OS-level toasts instead of snackbars, and OS-level background uploads via a foreground service.

**Architecture:** `theme.dart` becomes the single source of color truth (`AppColors` + blue-seeded `ColorScheme`, pure `#000000` dark surfaces). `home_page.dart` becomes a `StatefulShell` with a `NavigationBar` (Share / History / Settings). `fluttertoast` replaces `SnackBar`. `UploadEngine` becomes an app-lifetime singleton whose progress drives a `flutter_background_service` foreground notification so uploads survive app minimize/lock.

**Tech Stack:** Flutter 3.10+, Dart 3.10; `fluttertoast` (toast), `flutter_background_service` (Android foreground service), `shared_preferences` (already present, for theme-mode persistence).

## Global Constraints

- Every `Colors.x` / `Color(0x…)` / `0xFF…` color literal in the app MUST live ONLY in `lib/ui/theme.dart` after the change. (Spec §1b color rule.)
- Dark surfaces (scaffold / card / sheet / app bar) MUST be pure `#000000` in dark mode. (Spec §1a, §2.)
- Seed color MUST be blue, defined once as `AppColors.brand` and injected into `ColorScheme.fromSeed`. (Spec §1a, §2.)
- App bar background MUST be white in light mode, pure black in dark mode. (Spec §2.)
- No new color literals may be introduced in widgets. (Spec §1b.)
- Background uploads survive app minimize / screen lock via a foreground service; full process-kill resume is out of scope. (Spec §5.)
- Added dependencies: `fluttertoast`, `flutter_background_service`. (Spec §4, §5.)

---

## Task 1: Add dependencies

**Files:**
- Modify: `pubspec.yaml`

**Interfaces:**
- Consumes: nothing (baseline).
- Produces: resolvable `fluttertoast` and `flutter_background_service` packages for later tasks.

- [ ] **Step 1: Add the two dependencies under `dependencies:`**

Open `pubspec.yaml`. In the `dependencies:` block (after `receive_sharing_intent: ^1.9.0`), add:

```yaml
  fluttertoast: ^8.2.12
  flutter_background_service: ^5.0.10
```

The block should read:

```yaml
dependencies:
  flutter:
    sdk: flutter

  # The following adds the Cupertino Icons font to your application.
  cupertino_icons: ^1.0.8
  dio: ^5.10.0
  file_picker: ^11.0.2
  archive: ^4.0.9
  shared_preferences: ^2.5.5
  receive_sharing_intent: ^1.9.0
  fluttertoast: ^8.2.12
  flutter_background_service: ^5.0.10
```

- [ ] **Step 2: Resolve dependencies**

Run: `flutter pub get`
Expected: resolves with no resolver errors; `pubspec.lock` updates for the two new packages.

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "build: add fluttertoast and flutter_background_service deps"
```

---

## Task 2: Centralize colors — rewrite `theme.dart` (blue / AMOLED)

**Files:**
- Modify: `lib/ui/theme.dart` (full rewrite)

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `Color AppColors.brand` — the single blue seed (used by `buildTheme`).
  - `Map<String, ({IconData icon, Color color})> AppColors.fileCategories` — file-type semantics (consumed by `upload_tile.dart`).
  - `Color AppColors.collection` — collection tint (consumed by `upload_tile.dart`).
  - `ThemeData buildTheme(Brightness brightness)` — consumes `AppColors.brand`.

- [ ] **Step 1: Rewrite `lib/ui/theme.dart`**

Replace the entire file with:

```dart
import 'package:flutter/material.dart';

/// Single source of color truth for the app. No widget outside this file may
/// contain a raw color literal (Colors.x / Color(0x…) / 0xFF…). See spec §1b.
class AppColors {
  // Brand accent. Injected into ColorScheme.fromSeed so light+dark derive from it.
  static const Color brand = Color(0xFF1565FF); // blue

  // File-type semantics. Named so widgets never hard-code a Color literal.
  static const Map<String, ({IconData icon, Color color})> fileCategories = {
    'image': (icon: Icons.image, color: Color(0xFF9C27B0)), // purple
    'video': (icon: Icons.movie, color: Color(0xFFE53935)), // red
    'audio': (icon: Icons.music_note, color: Color(0xFFEC407A)), // pink
    'pdf': (icon: Icons.picture_as_pdf, color: Color(0xFFEF5350)), // redAccent
    'doc': (icon: Icons.description, color: Color(0xFF1E88E5)), // blue
    'sheet': (icon: Icons.table_chart, color: Color(0xFF43A047)), // green
    'slide': (icon: Icons.slideshow, color: Color(0xFFF4511E)), // deepOrange
    'archive': (icon: Icons.archive, color: Color(0xFF6D4C41)), // brown
    'text': (icon: Icons.article, color: Color(0xFF26A69A)), // teal
    'app': (icon: Icons.apps, color: Color(0xFF3949AB)), // indigo
    'default': (icon: Icons.insert_drive_file, color: Color(0xFF607D8B)), // blueGrey
  };

  static const Color collection = Color(0xFFFFB300); // amber
}

/// Blue primary seed; white surfaces in light, pure AMOLED black in dark.
ThemeData buildTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.brand,
    brightness: brightness,
    // Pure white in light; pure AMOLED black in dark.
    surface: isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
    onSurface: isDark ? const Color(0xFFFFFFFF) : const Color(0xFF101010),
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor:
        isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
    appBarTheme: AppBarTheme(
      // White in light, pure black in dark. Icon/text use onSurface.
      backgroundColor: isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      elevation: isDark ? 0 : 2,
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: isDark
            ? BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4))
            : BorderSide.none,
      ),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      clipBehavior: Clip.antiAlias,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 20),
      ),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 6,
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    ),
  );
}
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/ui/theme.dart`
Expected: no errors (warnings OK). Note: other files still import `heroGradient` and `SnackBarThemeData` from this file, so a repo-wide analyze will error until Tasks 4–5 land; that is expected.

- [ ] **Step 3: Commit**

```bash
git add lib/ui/theme.dart
git commit -m "style: centralize colors; blue seed + AMOLED dark in theme.dart"
```

---

## Task 3: Enforce centralization — test proves no hard-coded colors elsewhere

**Files:**
- Create: `test/colors_centralized_test.dart`

**Interfaces:**
- Consumes: `AppColors.brand` from `lib/ui/theme.dart` (Task 2).
- Produces: a regression guard that fails if any widget file outside `theme.dart` introduces a color literal.

- [ ] **Step 1: Write the test**

Create `test/colors_centralized_test.dart`:

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flashshare/ui/theme.dart';

void main() {
  test('AppColors.brand is blue', () {
    expect(AppColors.brand.value, 0xFF1565FF);
  });

  test('no hard-coded color literals outside lib/ui/theme.dart', () {
    final libDir = Directory('lib');
    final offenders = <String>[];
    final pattern = RegExp(r'(Colors\.\w+|Color\(0x[0-9A-Fa-f]{6,8}\)|0x[0-9A-Fa-f]{6,8})');
    for (final f in libDir.listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (f.path.replaceAll('\\', '/').endsWith('lib/ui/theme.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (pattern.hasMatch(lines[i])) {
          offenders.add('${f.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'Color literals must live only in lib/ui/theme.dart.\n'
            'Offenders:\n${offenders.join('\n')}');
  });
}
```

- [ ] **Step 2: Run the test (expect it to FAIL — other files still hard-code colors)**

Run: `flutter test test/colors_centralized_test.dart`
Expected: FAIL. The second test reports offenders in `lib/ui/home_page.dart`, `lib/ui/upload_tile.dart`, `lib/ui/multi_file_dialog.dart`. (First test passes.)

Note the failing offenders — they are the exact sites Tasks 4, 5, and 6 fix.

- [ ] **Step 3: Commit the failing guard (it will pass once Tasks 4–6 land)**

```bash
git add test/colors_centralized_test.dart
git commit -m "test: guard that color literals live only in theme.dart"
```

---

## Task 4: Toast wrapper (`fluttertoast`)

**Files:**
- Create: `lib/ui/toast.dart`

**Interfaces:**
- Consumes: `fluttertoast` package (Task 1).
- Produces: `void showToast(BuildContext context, String message)` — used by `home_page.dart` in Task 6.

- [ ] **Step 1: Create `lib/ui/toast.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

/// OS-level toast (real notification on Android, overlay elsewhere). Replaces
/// SnackBar per spec §4. Uses OS defaults so it reads on both themes.
void showToast(BuildContext context, String message) {
  Fluttertoast.showToast(
    msg: message,
    toastLength: Toast.LENGTH_SHORT,
    gravity: ToastGravity.BOTTOM,
    timeInSecForIosWeb: 2,
  );
}
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/ui/toast.dart`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/ui/toast.dart
git commit -m "feat: add showToast wrapper around fluttertoast"
```

---

## Task 5: Point `upload_tile.dart` and `multi_file_dialog.dart` at `AppColors`

**Files:**
- Modify: `lib/ui/upload_tile.dart`
- Modify: `lib/ui/multi_file_dialog.dart`

**Interfaces:**
- Consumes: `AppColors.fileCategories`, `AppColors.collection` from `lib/ui/theme.dart` (Task 2).
- Produces: widget files with zero color literals (so the Task 3 guard passes after Tasks 5 + 6).

- [ ] **Step 1: Rewrite `fileVisuals` in `lib/ui/upload_tile.dart`**

Replace the entire `fileVisuals` top-level function (currently lines 5–42) with:

```dart
/// Pick an icon + accent color for a filename. Colors come from the central
/// AppColors map (spec §1b) — never a hard-coded Color literal here.
({IconData icon, Color color}) fileVisuals(String filename) {
  final ext = filename.contains('.')
      ? filename.split('.').last.toLowerCase()
      : '';
  switch (ext) {
    case 'png' ||
          'jpg' ||
          'jpeg' ||
          'gif' ||
          'webp' ||
          'bmp' ||
          'heic' ||
          'svg':
      return AppColors.fileCategories['image']!;
    case 'mp4' || 'mov' || 'webm' || 'avi' || 'mkv' || 'm4v':
      return AppColors.fileCategories['video']!;
    case 'mp3' || 'wav' || 'ogg' || 'm4a' || 'flac':
      return AppColors.fileCategories['audio']!;
    case 'pdf':
      return AppColors.fileCategories['pdf']!;
    case 'doc' || 'docx' || 'rtf' || 'odt':
      return AppColors.fileCategories['doc']!;
    case 'xls' || 'xlsx' || 'csv':
      return AppColors.fileCategories['sheet']!;
    case 'ppt' || 'pptx' || 'key':
      return AppColors.fileCategories['slide']!;
    case 'zip' || 'rar' || '7z' || 'tar' || 'gz':
      return AppColors.fileCategories['archive']!;
    case 'txt' || 'md' || 'json' || 'xml' || 'yaml' || 'yml':
      return AppColors.fileCategories['text']!;
    case 'apk' || 'exe' || 'dmg' || 'deb':
      return AppColors.fileCategories['app']!;
    default:
      return AppColors.fileCategories['default']!;
  }
}
```

- [ ] **Step 2: Fix `HistoryTile` collection color in `lib/ui/upload_tile.dart`**

Replace line 80 (the `fileVisuals` call site in `HistoryTile.build`):

```dart
    final visuals = e.kind == 'collection'
        ? (icon: Icons.folder_special, color: Colors.amber)
        : fileVisuals(e.filename);
```

with:

```dart
    final visuals = e.kind == 'collection'
        ? (icon: Icons.folder_special, color: AppColors.collection)
        : fileVisuals(e.filename);
```

- [ ] **Step 3: Fix `ActiveTile` cancelled color in `lib/ui/upload_tile.dart`**

Replace line 161:

```dart
      UploadState.cancelled => Colors.orange,
```

with:

```dart
      UploadState.cancelled => AppColors.brand,
```

- [ ] **Step 4: Fix `multi_file_dialog.dart` option colors**

In `lib/ui/multi_file_dialog.dart`, replace the three `color: Colors.x` entries inside the `options` list (lines 10, 17, 24):

```dart
      (mode: UploadMode.separate, icon: Icons.file_copy_outlined,
        color: AppColors.brand, title: 'Upload separately',
        desc: 'Each file gets its own share link.'),
      (mode: UploadMode.zip, icon: Icons.archive_outlined,
        color: AppColors.fileCategories['archive']!.color, title: 'Zip into one file',
        desc: 'Bundle everything into a single .zip.'),
      (mode: UploadMode.collection, icon: Icons.folder_special_outlined,
        color: AppColors.collection, title: 'As a collection',
        desc: 'One link opens all files together.'),
```

- [ ] **Step 5: Fix the `chevron_right` literal in `multi_file_dialog.dart`**

Replace line 111:

```dart
                  const Icon(Icons.chevron_right, color: Colors.grey),
```

with:

```dart
                  Icon(Icons.chevron_right,
                      color: Theme.of(context).colorScheme.outline),
```

- [ ] **Step 6: Add the `theme.dart` import to `multi_file_dialog.dart`**

Add to the top imports of `lib/ui/multi_file_dialog.dart`:

```dart
import 'package:flashshare/ui/theme.dart';
```

(`upload_tile.dart` already imports `package:flashshare/models.dart` and `upload_engine.dart`; add the theme import there too if not present. Confirm `AppColors` resolves — if `upload_tile.dart` lacks the import, add `import 'package:flashshare/ui/theme.dart';`.)

- [ ] **Step 7: Verify both files compile**

Run: `flutter analyze lib/ui/upload_tile.dart lib/ui/multi_file_dialog.dart`
Expected: no errors.

- [ ] **Step 8: Commit**

```bash
git add lib/ui/upload_tile.dart lib/ui/multi_file_dialog.dart
git commit -m "style: route file/dialog colors through AppColors (no literals)"
```

---

## Task 6: Restyle `home_page.dart` — bottom nav + tabs + toast + no hard-coded colors

**Files:**
- Modify: `lib/ui/home_page.dart` (full rewrite into a shell + 3 tabs)
- Create: `lib/ui/settings_store.dart`
- Create: `lib/ui/settings_tab.dart`

**Interfaces:**
- Consumes:
  - `AppColors` from `lib/ui/theme.dart` (Task 2)
  - `showToast` from `lib/ui/toast.dart` (Task 4)
  - `HistoryStore`, `UploadEngine`, `ShareHandler`, `MultiFileDialog`, `ActiveTile`, `HistoryTile`, `fileVisuals` (existing)
  - `flutter_background_service` `startUploadService` / `stopUploadService` (defined in Task 8)
- Produces: the 3-tab app shell; the Settings tab reads/writes theme mode.

- [ ] **Step 1: Create `lib/ui/settings_store.dart`**

```dart
import 'package:shared_preferences/shared_preferences.dart';

const _kThemeMode = 'theme_mode'; // 'system' | 'light' | 'dark'

class SettingsStore {
  final SharedPreferences _prefs;
  SettingsStore(this._prefs);

  static Future<SettingsStore> create() async =>
      SettingsStore(await SharedPreferences.getInstance());

  String get themeMode => _prefs.getString(_kThemeMode) ?? 'system';

  Future<void> setThemeMode(String mode) async =>
      _prefs.setString(_kThemeMode, mode);
}
```

- [ ] **Step 2: Create `lib/ui/settings_tab.dart`**

```dart
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
```

- [ ] **Step 3: Rewrite `lib/ui/home_page.dart`**

Replace the entire file with:

```dart
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
import 'package:flashshare/ui/theme.dart';
import 'package:flashshare/ui/toast.dart';
import 'package:flashshare/ui/upload_tile.dart';
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
        onReceive: _receive,
        onCopy: _copy,
        onDelete: _delete,
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
  final Future<void> Function(List<AppFile>) onReceive;
  final void Function(HistoryEntry) onCopy;
  final void Function(HistoryEntry) onDelete;
  const _ShareTab(
      {required this.active,
      required this.history,
      required this.onPick,
      required this.onReceive,
      required this.onCopy,
      required this.onDelete});

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
                        p: p, onCancel: () => onReceive, onCancelKey: p.key))
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
                  size: 48, color: Theme.of(context).colorScheme.onPrimaryContainer),
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
```

> Note: `ActiveTile` in `upload_tile.dart` takes `p` and `onCancel` (a `VoidCallback`). In the `_ShareTab` list we pass `onCancel: () => onReceive` is wrong — instead pass the engine cancel. **Fix before commit:** change `ActiveTile` usage to take the engine cancel callback. See Step 4.

- [ ] **Step 4: Wire `ActiveTile` cancel correctly**

In `home_page.dart` `_ShareTab`, the `ActiveTile` must cancel via the engine. The engine isn't passed into `_ShareTab`. Simplest fix: pass an `onCancel` `void Function(String key)` into `_ShareTab` and into `ActiveTile`.

Replace the `_ShareTab` `ActiveTile` mapping with:

```dart
              SliverList(
                delegate: SliverChildListDelegate(active
                    .map((p) => ActiveTile(
                        p: p, onCancel: () => onCancel(p.key)))
                    .toList()),
              ),
```

And add `final void Function(String key) onCancel;` to `_ShareTab`'s fields, and pass `onCancel: widget.engine.cancel` from `HomePage.build`:

```dart
      _ShareTab(
        active: _active,
        history: _history,
        onPick: _pick,
        onReceive: _receive,
        onCopy: _copy,
        onDelete: _delete,
        onCancel: widget.engine.cancel,
      ),
```

- [ ] **Step 5: Verify it compiles**

Run: `flutter analyze lib/ui/home_page.dart lib/ui/settings_tab.dart lib/ui/settings_store.dart`
Expected: no errors. (Repo-wide analyze still errors until `main.dart` wires the new `HomePage` ctor and `heroGradient` is removed — fixed in Task 7.)

- [ ] **Step 6: Commit**

```bash
git add lib/ui/home_page.dart lib/ui/settings_tab.dart lib/ui/settings_store.dart
git commit -m "feat: 3-tab bottom nav; toast feedback; AMOLED restyle of home"
```

---

## Task 7: Wire `main.dart` to the new shell + theme-mode persistence

**Files:**
- Modify: `lib/main.dart`

**Interfaces:**
- Consumes: `SettingsStore` (Task 6), `HomePage` new ctor (Task 6), `buildTheme` (Task 2).
- Produces: app entry that builds the settings store, applies persisted `ThemeMode`, and passes `onThemeMode` to `HomePage`.

- [ ] **Step 1: Rewrite `lib/main.dart`**

Replace the entire file with:

```dart
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flashshare/api/storage_client.dart';
import 'package:flashshare/storage/history_store.dart';
import 'package:flashshare/ui/home_page.dart';
import 'package:flashshare/ui/settings_store.dart';
import 'package:flashshare/ui/theme.dart';
import 'package:flashshare/upload/upload_engine.dart';

ThemeMode _modeFrom(String s) =>
    switch (s) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await HistoryStore.create();
  final settings = await SettingsStore.create();
  final token = await store.getVisitorToken();
  final apiDio = Dio(BaseOptions(
    baseUrl: 'https://storage.to/api',
    validateStatus: (_) => true,
  ));
  final client = HttpStorageClient(apiDio, token);
  final r2Dio = Dio(BaseOptions(validateStatus: (_) => true));
  final engine = UploadEngine(client, store, r2Dio);
  final initialMode = _modeFrom(settings.themeMode);
  runApp(FlashShareApp(
    store: store,
    settings: settings,
    engine: engine,
    initialMode: initialMode,
  ));
}

class FlashShareApp extends StatefulWidget {
  final HistoryStore store;
  final SettingsStore settings;
  final UploadEngine engine;
  final ThemeMode initialMode;
  const FlashShareApp(
      {super.key,
      required this.store,
      required this.settings,
      required this.engine,
      required this.initialMode});

  @override
  State<FlashShareApp> createState() => _FlashShareAppState();
}

class _FlashShareAppState extends State<FlashShareApp> {
  late ThemeMode _mode;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
  }

  void _setMode(ThemeMode mode) => setState(() => _mode = mode);

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Flash Share',
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: _mode,
        home: HomePage(
          store: widget.store,
          settings: widget.settings,
          engine: widget.engine,
          onThemeMode: _setMode,
        ),
      );
}
```

- [ ] **Step 2: Verify the whole app compiles**

Run: `flutter analyze`
Expected: no errors (the `heroGradient` import was removed from `home_page.dart`; ensure nothing else still imports `heroGradient` — grep confirms it is now unreferenced and can be deleted from `theme.dart` if desired, but leaving it is harmless; prefer deleting it to keep the file clean).

- [ ] **Step 3: Run the centralization guard — it must now PASS**

Run: `flutter test test/colors_centralized_test.dart`
Expected: both tests PASS (no offenders outside `theme.dart`).

- [ ] **Step 4: Run the existing upload-engine tests**

Run: `flutter test test/upload_engine_test.dart`
Expected: all 3 existing tests PASS (engine behavior unchanged).

- [ ] **Step 5: Commit**

```bash
git add lib/main.dart
git commit -m "feat: wire settings store + theme mode into app shell"
```

---

## Task 8: OS-level background uploads (foreground service)

**Files:**
- Modify: `lib/upload/upload_engine.dart` (add `active` count + `onIdle` hook; no plugin import)
- Modify: `lib/main.dart` (configure service, wire `onIdle`)
- Modify: `lib/ui/home_page.dart` (start service on enqueue)
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `android/app/build.gradle.kts` (verify plugin resolves)
- Modify: `android/app/src/main/kotlin/.../MainActivity.kt` (verify plugin auto-handles; add receiver if needed)

**Interfaces:**
- Consumes: `flutter_background_service` (Task 1), `UploadEngine` singleton (Tasks 6/7).
- Produces:
  - `void startUploadService()` and `void stopUploadService()` (called from `main.dart`/engine).
  - Engine stops the service when no uploads are active.

- [ ] **Step 1: Add `activeCount` + `onIdle` hook to `lib/upload/upload_engine.dart`**

In `upload_engine.dart`, inside `class UploadEngine`, add state and a setter:

```dart
  int _active = 0;
  void Function()? onIdle;
```

In `enqueue`, guard the count. Replace the top of `enqueue` (currently):

```dart
  Future<void> enqueue(List<AppFile> files, UploadMode mode) async {
    if (files.isEmpty) return;
```

with:

```dart
  Future<void> enqueue(List<AppFile> files, UploadMode mode) async {
    if (files.isEmpty) return;
    _active++;
```

> Note: the engine does NOT call `startUploadService()` itself (that would pull
> the foreground-service plugin into pure-Dart unit tests). The service is
> started from the UI in `home_page.dart` `_receive` and stopped via `onIdle`.

In `_uploadOne`, wrap the try/finally so the count decrements and `onIdle` fires when it hits zero. The existing `finally` is:

```dart
    } finally {
      _cancellers.remove(key);
    }
```

Replace it with:

```dart
    } finally {
      _cancellers.remove(key);
      _active--;
      if (_active <= 0) {
        _active = 0;
        onIdle?.call();
      }
    }
```

- [ ] **Step 2: Create `lib/upload/background_service.dart`**

```dart
import 'package:flutter_background_service/flutter_background_service.dart';

const _notificationChannelId = 'flashshare_uploads';
const _notificationChannelName = 'Uploads';

/// Configure the Android foreground service. Call once at startup (main).
Future<void> configureBackgroundService() async {
  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: _onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: _notificationChannelId,
      notificationChannelName: _notificationChannelName,
      notificationTitle: 'Flash Share',
      notificationContent: 'Uploading files…',
    ),
    iosConfiguration: IosConfiguration(autoStart: false),
  );
}

void _onStart(ServiceInstance service) {
  // Engine runs in the same isolate (started from main); this keeps the
  // isolate alive while the persistent notification is shown.
  if (service is AndroidServiceInstance) {
    service.on('stop').listen((_) => service.stopSelf());
  }
}

Future<void> startUploadService() => FlutterBackgroundService().startService();

Future<void> stopUploadService() =>
    FlutterBackgroundService().invoke('stop');
```

- [ ] **Step 3: Wire service start/stop in `lib/main.dart`**

In `main()`, after `final engine = UploadEngine(...)` and before `runApp`, add:

```dart
  await configureBackgroundService();
  engine.onIdle = stopUploadService;
```

In `_receive` (in `home_page.dart`), start the service right after enqueue so the
engine stays plugin-free (and the existing pure-Dart `upload_engine_test` keeps
passing). Add the import and the call:

At the top of `lib/ui/home_page.dart`, add:

```dart
import 'package:flashshare/upload/background_service.dart';
```

In `HomePage._receive`, after `await widget.engine.enqueue(files, mode);`, add:

```dart
    await startUploadService();
```

The engine stays free of the plugin; it only stops the service via `onIdle` (wired in `main.dart`).

- [ ] **Step 4: Android manifest — declare the service + permission**

In `android/app/src/main/AndroidManifest.xml`, inside `<application>`, add the service declaration; inside `<manifest>` add the foreground-service permission. Result (merge into existing file):

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <application
        ... >
        <service
            android:name="id.flutter.background_service.BackgroundService"
            android:exported="false"
            android:foregroundServiceType="dataSync" />
    </application>
</manifest>
```

(Keep the existing `<application>` attributes and other children; only add the `<service>` block and the three `<uses-permission>` lines.)

- [ ] **Step 5: Android Kotlin build — ensure plugin dependency resolves**

`flutter_background_service` is applied automatically by the Flutter Gradle plugin; no manual `build.gradle.kts` change is required for the Android module in current plugin versions. Confirm by building (Step 6). If the build complains about a missing Kotlin/AGP version, pin the plugin in `android/settings.gradle.kts` per the plugin's current README (leave as-is unless the build fails).

- [ ] **Step 6: Verify it builds (Android)**

Run: `flutter build apk --debug` (or `flutter analyze` plus a connected-device `flutter run` for a real check).
Expected: build succeeds; no missing-symbol / manifest-merger errors.

- [ ] **Step 7: Verify the centralization guard still passes**

Run: `flutter test test/colors_centralized_test.dart`
Expected: PASS (no color literals were added).

- [ ] **Step 8: Commit**

```bash
git add lib/upload/upload_engine.dart lib/upload/background_service.dart lib/main.dart android/
git commit -m "feat: OS-level background uploads via Android foreground service"
```

---

## Task 9: Final verification + cleanup

**Files:**
- No new files; verification only.

**Interfaces:**
- Consumes: all prior tasks.

- [ ] **Step 1: Full static analysis**

Run: `flutter analyze`
Expected: no errors.

- [ ] **Step 2: Full test suite**

Run: `flutter test`
Expected: all tests PASS (colors guard, upload-engine tests).

- [ ] **Step 3: Repo-wide color-literal grep sanity check**

Run: `grep -rEn "Colors\.|Color\(0x|0x[0-9A-Fa-f]{6,8}" lib | grep -v "lib/ui/theme.dart"`
Expected: no output (only `theme.dart` contains literals).

- [ ] **Step 4: Manual runtime checklist (run on a device/emulator)**

Run: `flutter run`
Verify:
1. Light mode: app bar white, surfaces white, primary blue.
2. Dark mode (toggle in Settings): app bar + surfaces pure `#000000`, text white, primary blue.
3. Share tab: pick files → active tile shows progress; copy → toast "Link copied" (not snackbar); delete failure → toast.
4. History tab: lists recent; copy/delete work.
5. Settings tab: System/Light/Dark switch changes theme immediately and persists across restart.
6. Background: start an upload, press home / lock screen → upload continues and a persistent "Uploading…" notification is shown; on completion the notification clears.

- [ ] **Step 5: Commit any stray fixes (only if Steps 1–4 surfaced issues)**

```bash
git add -A
git commit -m "fix: address issues found in final verification"
```

If no issues, skip this commit.

---

## Self-Review (against spec)

- **Spec §1 (central color):** Task 2 builds `AppColors` + scheme; Task 3 guards it; Tasks 5–6 remove all widget literals; Task 9 greps. ✅
- **Spec §2 (blue/AMOLED):** Task 2 sets blue seed + pure `#000000` dark surfaces + white/black app bar; Task 6 replaces hard-coded `Colors.white` bolt with scheme colors. ✅
- **Spec §3 (bottom nav 3 tabs):** Task 6 builds `HomePage` shell with Share/History/Settings `NavigationBar`. ✅
- **Spec §4 (toast):** Task 4 `showToast`; Task 6 replaces both SnackBars; Task 2 drops `snackBarTheme`. ✅
- **Spec §5 (background uploads):** Task 8 adds `flutter_background_service`, singleton engine, start/stop on enqueue/idle, Android manifest + permission. ✅
- **Placeholder scan:** No "TBD/TODO/similar to Task N". Every code step has full code. ✅
- **Type consistency:** `showToast(BuildContext, String)` used consistently; `AppColors.fileCategories['x']!` returns `({IconData icon, Color color})` matching `fileVisuals` return type; `UploadEngine.onIdle` / `active` added and used in Task 8; `startUploadService`/`stopUploadService` defined in Task 8 and called from engine. ✅
