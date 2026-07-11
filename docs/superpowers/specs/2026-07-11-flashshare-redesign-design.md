# FlashShare Redesign — Design Spec

**Date:** 2026-07-11
**Status:** Approved (design), pending implementation plan

## Goal

Restyle the FlashShare Flutter app to a blue / AMOLED-black identity, centralize
all color decisions into one theme file (zero hard-coded color literals in
widgets), replace `SnackBar` feedback with OS-level toasts, and add true
OS-level background uploads that survive the app being minimized or the screen
locked.

## Scope

In scope:
1. Central color system (single source of truth).
2. Blue / AMOLED-black restyle (light + dark).
3. Bottom navigation with 3 tabs (Share / History / Settings).
4. SnackBar → toast replacement (via `fluttertoast`).
5. OS-level background uploads (via `flutter_background_service`).

Out of scope (YAGNI): iOS native background upload, account/auth UI, file
preview, multi-language, persistence of an interrupted upload queue across a
full process kill (see "Background uploads" for the chosen boundary).

## 1. Central color system

**File:** `lib/ui/theme.dart` (rewritten) is the ONLY place color literals live.

Two layers:

### 1a. Theme colors (light / dark)
Built with `ColorScheme.fromSeed(seedColor: <blue>, brightness: …)`:
- **Light mode:**
  - scaffold / surface: white (`#FFFFFF`) and a near-white card (`#F7F8FA`)
  - primary: blue
  - on-surface / text: near-black
  - app bar background: white
- **Dark mode (AMOLED):**
  - scaffold / surface / card / sheet / app bar: **pure `#000000`**
  - primary: blue
  - on-surface / text: white
  - subtle dividers/outlines only (no grey fills that defeat AMOLED)

Blue value is defined ONCE as `AppColors.brand` and fed to `fromSeed`. All
surface/background literals live here and nowhere else.

### 1b. Semantic tokens
A single named map/class `AppColors` holds named, non-theme-accent colors so no
widget ever writes a raw `Color(0xFF…)` or `Colors.x`:
- `brand`, `onBrand` (text/icon on brand)
- `surface`, `surfaceVariant`, `divider`, `error`
- **File-category tints** (semantic, not theme accent) as one named map:
  image→purple, video→red, audio→pink, pdf→redAccent, doc→blue, sheet→green,
  slide→deepOrange, archive→brown, text→teal, app→indigo, default→blueGrey,
  collection→amber. These are defined here once; `fileVisuals` references the
  map by key, never a `Colors.x` literal.

**Rule enforced by this spec:** after the change, grepping the `lib/**` widget
tree for `Colors.`, `Color(0x`, `0xFF` returns matches ONLY inside
`lib/ui/theme.dart`.

## 2. Blue / AMOLED restyle

- Seed color → blue (orange branding removed everywhere: app bar, FAB, hero
  tint, progress accents).
- App bar: white background in light, pure black in dark. No colored gradient
  hero strip.
- Bolt icon (`Icons.bolt`) color → `Theme.of(context).colorScheme.onSurface`
  (auto-flips white in dark / blue-ish in light). Removes the hard-coded
  `Colors.white` in `home_page.dart` (3 sites) and the empty-state circle.
- Cards, dialogs, FAB, progress indicators ride the color scheme.
- Hero gradient (`heroGradient`): replaced with a subtle blue→transparent tint,
  or dropped. Kept only as a faint blue tint on the empty-state avatar circle;
  the orange `0xFFFF8A00 / 0xFFFFC400` literals are removed.

## 3. Bottom navigation + 3 tabs

`HomePage` (currently a single `Scaffold`) becomes a shell with a
`BottomNavigationBar` (or `NavigationBar`, Material 3) and an `IndexedStack` /
`StatefulShellRoute`-style body holding 3 tabs:

- **Share** — pick FAB + Active uploads list + empty state (today's home body).
- **History** — Recent list (copy / delete).
- **Settings** — theme mode control (System / Light / Dark) + background-upload
  status line.

`ThemeMode` is driven by a persisted user choice (default `ThemeMode.system`),
read/written through the existing `shared_preferences`-backed `HistoryStore`
(or a small `SettingsStore` on top of it). App bar title reflects the active tab.

## 4. SnackBar → Toast

- Add dependency: `fluttertoast` (small, cross-platform: real OS toast on
  Android, overlay toast on web/iOS).
- New `lib/ui/toast.dart`:
  ```dart
  void showToast(BuildContext context, String message) =>
      Fluttertoast.showToast(msg: message, …);
  ```
  (styling kept minimal; uses OS defaults so it reads on both themes.)
- Replace both `SnackBar` call sites in `home_page.dart`:
  - "Link copied"
  - "Delete failed: $err"
- Remove `snackBarTheme` from `buildTheme`.
- Remove `ScaffoldMessenger` usage.

## 5. OS-level background uploads

**Chosen boundary:** uploads survive app minimize / screen lock via an Android
foreground service that keeps the Dart isolate (and therefore the in-memory
`UploadEngine`) alive. Full process-kill resume is OUT of scope.

### Approach
- Dependency: `flutter_background_service`.
- `UploadEngine` becomes an **app-lifetime singleton**, constructed once in
  `main()` (as today) and shared with the UI — no longer recreated per route.
- On `enqueue`, call `service.startService()` → foreground service shows a
  persistent "Uploading… (n files)" notification. The OS will not reclaim the
  isolate while the notification is shown.
- When the last upload reaches `done`/`error`/`cancelled`, call
  `service.stopService()` → notification cleared, isolate may be reclaimed.
- Progress still flows through the existing `StreamController<UploadProgress>`
  broadcast stream; UI tabs subscribe as today.
- **Web:** no OS service; keep the tab open (best-effort, same in-app session
  continuity as today). **iOS:** best-effort (foreground service is Android).
- ponytail: single isolate, no isolate↔UI IPC beyond the existing progress
  stream bridged through the service handle.

### Files touched
- `lib/main.dart` — construct engine once; wire background service start/stop
  around `enqueue`/completion.
- `lib/upload/upload_engine.dart` — expose a completion hook / count so the
  service can stop when idle; keep engine as singleton.
- `android/` — foreground service config from the plugin (minimal generated
  boilerplate).

## Files changed (summary)

| File | Change |
|------|--------|
| `lib/ui/theme.dart` | Rewrite: central `AppColors`, blue seed, AMOLED dark, remove snackbar theme, remove orange literals |
| `lib/ui/home_page.dart` | Bottom-nav shell (3 tabs); remove `Colors.white` (→scheme), SnackBar→toast |
| `lib/ui/upload_tile.dart` | `fileVisuals` → references `AppColors` category map, not `Colors.x` |
| `lib/ui/multi_file_dialog.dart` | Option colors → `AppColors` tokens |
| `lib/ui/toast.dart` | NEW: `showToast` wrapper |
| `lib/upload/upload_engine.dart` | Singleton-friendly; completion hook for service stop |
| `lib/main.dart` | Singleton engine; start/stop background service |
| `pubspec.yaml` | + `fluttertoast`, + `flutter_background_service` |
| `android/**` | Foreground service plugin boilerplate |

## Testing / verification

- `flutter analyze` clean.
- Grep assert: no `Colors.` / `Color(0x` / `0xFF` outside `theme.dart`.
- Light + dark preview: app bar white-in-light / black-in-dark; AMOLED pure
  `#000000` surfaces in dark.
- Background: start an upload, minimize app, confirm progress continues and
  notification persists; on completion notification clears.
- Toast: copy-link and delete-fail show toast, not snackbar.

## Open decisions (resolved)

- Category file-type tints are KEPT as named semantic tokens (not deleted) —
  they are semantic, not theme accent.
- Foreground service = `flutter_background_service` (minimal platform code).
