# Flash Share

A no-login Flutter app for sharing temporary files. Pick files (or receive them
from the OS share sheet), and Flash Share uploads them to a backend and returns
a copyable, shareable link — no account, no sign-up, no friction.

- **Platforms:** Android + Web (PWA). iOS / desktop are not wired up.
- **Backend:** [`storage.to`](https://storage.to) REST API (`https://storage.to/api`).
- **Stance:** Anonymous uploads only. Files can be deleted later using a
  per-file ownership token; there is no user account.

---

## Features

- **Pick & share** — single or multiple files via `file_picker`.
- **Share-into-app** — Android share sheet (`SEND` / `SEND_MULTIPLE`) and the
  Web Share Target (PWA service worker) hand shared files straight into the
  upload pipeline. See [Sharing](#sharing).
- **Three upload modes** for multiple files (see [Upload modes](#upload-modes)):
  - **Separate** — each file gets its own link.
  - **Zip** — bundle everything into one `.zip` (built with `archive`).
  - **Collection** — one link opens all files together (server-side
    `/collection`).
- **Resumable-friendly progress** — real upload progress via `dio`
  `onSendProgress`; per-file state machine with cancel support.
- **Single-upload & multipart** — the client branches on the server's
  `init` response: small files go straight to a single `PUT`; large files are
  chunked and uploaded as multipart parts, then completed server-side.
- **Local history** — every uploaded file/collection is saved locally
  (`shared_preferences`) with its owner token, so you can **copy the link**,
  **share it**, **scan a QR code**, or **delete** it later.
- **Thumbnails** — images, videos, and PDFs get a local thumbnail cached
  immediately after upload so the history list renders previews instantly.
- **Background uploads (Android)** — a foreground service keeps uploads alive
  when the app is minimized. Best-effort, never fatal if unavailable.
- **Theming** — Material 3, system / light / dark, single source of color truth.
- **Crash-resilient** — uncaught errors are caught app-wide and reported via a
  toast instead of terminating the process.

---

## Architecture

### Data flow

```
UI (pick / share-in)
  │
  ▼
UploadEngine.enqueue(files, mode)
  │
  ├─ mode == zip       → build .zip (in memory) → upload as one file
  ├─ mode == collection→ POST /collection → upload each file with collection_id
  └─ mode == separate  → upload each file individually
  │
  ▼  for each unit to upload:
  StorageClient.uploadInit(...)                 POST /upload/init
  │
  ├─ type == "single"    → PUT bytes to upload_url                (progress)
  └─ type == "multipart" → chunk → PUT each part to R2          (progress)
                           → POST /upload/complete-multipart
  │
  ▼
  StorageClient.uploadConfirm(...)              POST /upload/confirm
  │   → FileRecord { id, url, owner_token, ... }
  │
  ▼
  HistoryStore.add(entry)                        shared_preferences
  │
  ▼
  UI renders: active uploads (progress, cancel)
              + history (link, QR, share, copy, delete)
```

### Ownership & identity

- **Visitor token** — a random id generated once, persisted in
  `shared_preferences`, and sent as `X-Visitor-Token` on every request. If it's
  lost, the anonymous quota resets, but existing uploads stay deletable via
  their `owner_token`. It is **not** cryptographically random — it's an
  anonymous quota identifier, not a secret.
- **Owner token** — returned by the server on `init`/`confirm` and persisted
  alongside each file. Deletes use `Authorization: Owner <token>`, so they
  survive network/cookie changes and work even if the visitor token is gone.

### Upload modes

| Mode        | What happens                                                            | Links              |
|-------------|-------------------------------------------------------------------------|--------------------|
| `separate`  | Each file uploaded individually.                                        | One per file       |
| `zip`       | Files zipped in memory (`archive`) and uploaded as one `.zip`.          | One (the zip)      |
| `collection`| `POST /collection` first, then each file confirmed with `collection_id`.| One (collection)   |

A single file is always uploaded directly (no mode dialog). With ≥2 files, the
mode dialog (`multi_file_dialog.dart`) is shown.

---

## Project structure

```
lib/
  main.dart                      # Entry point, error handlers, DI wiring, MaterialApp
  models.dart                   # UploadInit, PartEtag, FileRecord, Collection,
                                #   HistoryEntry, guessContentType()
  api/
    storage_client.dart         # HttpStorageClient — wraps storage.to endpoints
  files/
    app_file.dart               # AppFile abstraction (platform-neutral handle)
    native_file_io.dart         # dart:io-backed AppFile (mobile)
    native_file_stub.dart       # web stub for fileFromPath()
  share/
    share_handler.dart          # receive_sharing_intent → enqueue
  storage/
    history_store.dart          # visitor token + history (shared_preferences)
  upload/
    upload_engine.dart          # orchestrates init → PUT → confirm, progress/state
    background_service.dart     # Android foreground service lifecycle
  ui/
    home_page.dart              # Share / History / Settings tabs
    upload_tile.dart            # history + active-upload rows, thumbnails, actions
    multi_file_dialog.dart      # separate vs zip vs collection choice
    qr_dialog.dart              # QR code dialog for a share link
    settings_store.dart         # theme mode persistence
    settings_tab.dart           # appearance + background-upload info
    theme.dart                  # AppColors + Material 3 buildTheme()
    toast.dart                  # OS-level toast helper
test/
  upload_engine_test.dart       # engine flow with faked R2 + storage client
  history_store_test.dart       # token persistence + add/remove round-trip
  models_test.dart              # content-type guessing
  colors_centralized_test.dart  # enforces: no color literals outside theme.dart
docs/superpowers/               # design specs & plans (reference)
web/                            # PWA shell, icons, share-target service worker
android/                        # Android app, manifest, build config
.github/workflows/android-apk.yml  # CI: build split APKs on push/PR
```

---

## Dependencies

| Package                   | Purpose                                                        |
|---------------------------|----------------------------------------------------------------|
| `dio`                     | HTTP + `onSendProgress` for upload progress.                   |
| `file_picker`             | Pick single / multiple files.                                  |
| `archive`                 | Build a `.zip` when the user chooses "combine into one".       |
| `shared_preferences`      | Visitor token + upload history persistence.                    |
| `receive_sharing_intent`  | Android share sheet (mobile); web uses the share-target SW.    |
| `flutter_background_service` | Android foreground service for background uploads.          |
| `permission_handler`      | Request `POST_NOTIFICATIONS` for the foreground service.       |
| `qr_flutter`              | QR code in the share dialog.                                   |
| `share_plus`              | OS share sheet for a finished link.                            |
| `fluttertoast`            | OS-level toast feedback.                                       |
| `cached_network_image`    | Render cached thumbnails in the history list.                  |
| `video_thumbnail`         | Generate video frame thumbnails.                               |
| `pdf_render`              | Render the first PDF page as a thumbnail.                      |
| `path_provider`           | Temp dir (used for zip / thumbnail work).                      |
| `flutter_cache_manager`   | Local thumbnail cache keyed by file URL.                       |
| `cupertino_icons`         | iOS-style icons.                                               |

---

## Sharing

### Android
The manifest registers `SEND` and `SEND_MULTIPLE` intent filters
(`*/*`), so any app's share sheet can target Flash Share. Incoming media is
received via `receive_sharing_intent` and enqueued like a normal pick.

### Web (PWA)
`web/manifest.json` declares a `share_target` POSTing to `/share-target`.
`web/share_target_sw.js` intercepts that POST, pulls the files out of the form
data, forwards metadata to the running app over a `BroadcastChannel`, and
redirects to `/`. Note: the current service worker forwards file **metadata**
(name/size) rather than the bytes, so the web share-target flow is
best-effort and may need further polish to fully pipe shared files into the
upload pipeline.

---

## Background uploads (Android)

`background_service.dart` configures a `dataSync` foreground service. Before an
upload starts, `startUploadService()` requests the `POST_NOTIFICATIONS`
permission and starts the service (best-effort — it never throws). When the
engine drains its queue (`onIdle`), `stopUploadService()` stops it. Every
call is wrapped so a failure can't escape a `finally` and crash the app. On
web/iOS this is a no-op; uploads still run on the UI isolate.

---

## Getting started

### Prerequisites
- [Flutter](https://docs.flutter.dev/get-started/install) (stable, Dart SDK
  `^3.10.7` per `pubspec.yaml`).
- For Android: Android SDK + a device/emulator.
- For Web: any modern browser.

### Run

```bash
flutter pub get
flutter run            # Android device/emulator, or:
flutter run -d chrome  # Web
```

### Build

```bash
# Android split-per-ABI release APKs (also produced by CI)
flutter build apk --release --split-per-abi

# Web PWA
flutter build web
```

---

## Testing

```bash
flutter test
```

What's covered (lightweight, `flutter test` only — no framework):

- `upload_engine_test.dart` — full upload flow with a faked R2 `PUT`
  (always 200 + fake etag) and a fake `StorageClient`; verifies confirm /
  collection calls and history writes.
- `history_store_test.dart` — visitor token persists across store reloads;
  add → remove round-trips.
- `models_test.dart` — `guessContentType` maps common extensions.
- `colors_centralized_test.dart` — static check enforcing that **no color
  literals** (`Colors.x`, `Color(0x…)`, `0x…`) exist outside
  `lib/ui/theme.dart` (`AppColors` is the single source of color truth).

---

## CI

`.github/workflows/android-apk.yml` runs on push to `master`, on PRs, and
manually. It checks out, sets up Java 17 + Flutter stable, runs `flutter test`,
builds split release APKs (`armeabi-v7a`, `arm64-v8a`, `x86_64`), and uploads
them as a 30-day artifact.

---

## Known limitations (intentional ceilings)

These are deliberate simplifications, not bugs:

- **No account / auth UI.** Anonymous uploads only.
- **No expiry / password / max-downloads UI.** The API supports them; the UI
  defers them.
- **No `429` auto-retry.** Rate limits surface as a manual retry message.
- **Web share-target is best-effort.** The service worker forwards file
  metadata, not bytes; Android works fully.
- **Visitor token is non-crypto random.** Fine as an anonymous quota id, not a
  secret.
- **No upload concurrency limit.** A single `Dio` client uploads sequentially;
  add a semaphore if uploading hundreds of files at once becomes a need.
- **Zip is built in memory.** Large multi-file zips are buffered before
  upload rather than streamed.

---

## License

Private project — not published to pub.dev (`publish_to: 'none'`).

---

## Useful links

- [Flutter docs](https://docs.flutter.dev/)
- [storage.to API](https://storage.to/api)
- Design specs: `docs/superpowers/specs/`
