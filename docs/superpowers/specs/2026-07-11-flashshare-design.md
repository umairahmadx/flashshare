# Flash Share — Design Spec

**Date:** 2026-07-11
**Status:** Approved (design), pending implementation plan
**App name:** Flash Share (`flashshare`)
**Platforms:** Android + Web (iOS/macOS/Windows/Linux removed)
**Backend:** storage.to REST API (`https://storage.to/api`)

## Goal

A no-login Flutter app to share temporary files. The user picks files (or
receives them via the OS share sheet), the app uploads them to storage.to
using its 3-step flow (init → PUT to R2 → confirm), and returns a copyable
shareable link. Uploaded files are tracked locally so the user can copy links
and delete their own uploads later, without ever signing in.

## Non-goals (v1)

- No authentication / account UI. Anonymous uploads only.
- No password / expiry / max-downloads mutation UI (API supports it; UI deferred).
- No thumbnails, batch-init, bandwidth indicator, or `429` auto-retry.
- No permanent-file / premium features.

## Architecture

### Data flow

```
UI (pick / share-in)
  → UploadEngine.enqueue(files)
      → StorageClient.uploadInit(...)           POST /upload/init
      → branch on response.type:
          single    → PUT bytes to upload_url   (progress)
          multipart → chunk file → PUT each part (progress)
                                → POST /upload/complete-multipart
          → POST /upload/confirm  (collection_id? for collection mode)
      → FileRecord { id, url, owner_token, ... }
  → HistoryStore.add(entry)                     shared_preferences
UI renders active uploads (progress, cancel) + history (link, copy, delete)
```

- **Visitor token:** a random uuid generated once, persisted in
  `shared_preferences`, sent as `X-Visitor-Token` on every request. Lost token
  = anonymous quota resets but existing uploads still deletable via owner_token.
- **Ownership:** every `owner_token` from `init`/`confirm` is persisted with its
  file. Delete uses `Authorization: Owner <token>`. This survives network/cookie
  changes (preferred over visitor+IP fallback).

### Dependencies (pub.dev)

| Package | Purpose |
|---|---|
| `dio` | HTTP + `onSendProgress` for upload progress; clean multipart PUTs |
| `file_picker` | pick single / multiple files |
| `archive` | build a .zip when the user chooses "combine into one" |
| `path_provider` | temp dir for the generated zip |
| `shared_preferences` | visitor token + upload history (id, url, owner_token, meta) |
| `receive_sharing_intent` | Android share sheet + Web share target (PWA) |

Built-in (no dep): `Clipboard` (copy link), `SnackBar` (feedback), `uuid`
generation via `dart:math`/simple random (or `uuid` if already pulled by a
dep — `file_picker` does not; we generate a token without a separate package to
stay lean, see ceiling note).

### File layout (~9 files, fewest possible)

```
lib/
  main.dart                 # MaterialApp, theme, home route
  models.dart               # UploadInit, FileRecord, Collection, HistoryEntry (plain classes)
  api/storage_client.dart   # wraps storage.to endpoints, returns typed models
  upload/upload_engine.dart # orchestrates init→PUT→confirm, emits progress/state
  share/share_handler.dart  # receive_sharing_intent wiring → enqueue
  storage/history_store.dart# shared_preferences read/write of visitor token + history
  ui/home_page.dart         # pick button, active list, history list
  ui/upload_tile.dart       # one row: name, progress, cancel / link, copy, delete
  ui/multi_file_dialog.dart # separate vs zip vs collection choice
test/
  upload_engine_test.dart   # token persistence, history add/delete, zip-vs-separate decision
```

## Feature detail

### 1. Upload engine (`upload_engine.dart`)

`enqueue(List<File> files, {Mode mode})` where `Mode` ∈
`{separate, zip, collection}`.

For each unit to upload:
1. `uploadInit(filename, contentType, size)`.
2. `type == "single"`: `dio.put(uploadUrl, data: file.openRead(),
   options: Options(headers: headers, ...), onSendProgress: emit)`.
3. `type == "multipart"`: compute `totalParts = ceil(size / partSize)`; for each
   part, slice `partSize` bytes, `dio.put(partUrl, data: chunk,
   onSendProgress: ...)`. Capture `etag` from response header. After all parts:
   `uploadCompleteMultipart(uploadId, parts)`.
4. `uploadConfirm(...)` → returns `FileRecord` (url + owner_token).
5. `HistoryStore.add(record)`.

Cancel: abort in-flight dio request, `uploadAbort(uploadId)` for multipart.
State machine per upload: `queued → uploading(progress) → confirming → done |
error | cancelled`.

### 2. Multiple files (`multi_file_dialog.dart`)

When ≥2 files are selected or shared, show a dialog:
- **Upload separately** — each file uploaded individually, own link.
- **Zip into one** — `archive` builds `<commonname>.zip` in temp dir, uploaded as
  one file, one link.
- **As collection** — `POST /collection`, attach every `confirm` with
  `collection_id`, share the single `/c/{id}` link (history stores the
  collection URL).

Single file → upload directly (no dialog).

### 3. Share-into-app (`share_handler.dart`)

`receive_sharing_intent` stream of shared media paths → convert to `File`s →
`enqueue` (treated like a pick). Android: native share sheet target. Web: needs
`share_target` in `web/manifest.json` + a service worker that posts the shared
file to the app. Flagged as the fiddliest part; if web share-target proves
unreliable in Flutter, Android stays fully working and web falls back to manual
pick.

### 4. UI (`home_page.dart`, `upload_tile.dart`)

- App bar: "Flash Share".
- Primary action: "Pick files" (file_picker). Incoming shared files auto-enqueue.
- Active uploads section: each `upload_tile` shows filename, linear progress,
  cancel button.
- History section: each tile shows filename, `file.url`, Copy (Clipboard +
  SnackBar), Delete (`Authorization: Owner <token>` → `DELETE /file/{id}` or
  `/collection/{id}`, then `HistoryStore.remove`).
- Material theme, seed color. No extra UI deps.

### 5. Errors

Map storage.to error shape `{"success": false, "error": "..."}` + status:
- `400/422` validation/quota → show `error`.
- `401/403` not owner → "You don't own this" (shouldn't happen for own tokens).
- `404` expired/gone → remove from history, inform.
- `429` rate limited → show "Slow down, retry after Ns" from `Retry-After`.
  No auto-retry in v1 (`ponytail:` ceiling — add backoff when real throttling
  observed).
- `500` → "Server error, try again".

### 6. Visitor token generation (ceiling)

Generated with `dart:math` random + timestamp, not a uuid package, to avoid a
dep. `ponytail:` ceiling — not cryptographically random; fine for an anonymous
quota identifier, not for secrets. Swap to `uuid`/`crypto` if it ever gates
anything sensitive.

## Testing

`test/upload_engine_test.dart` (lightweight, no framework beyond `flutter test`):
- visitor token persists across store reloads.
- `HistoryStore.add` then `remove` round-trips.
- multi-file decision helper returns correct `Mode` mapping.
No per-function suite; covers the non-trivial branches only.

## Known ceilings (ponytail)

- `429` no backoff (manual retry message only).
- Web share-target may need PWA service-worker polish.
- Visitor token is non-crypto random.
- Single Dio client; no concurrency limit on parallel uploads (add a semaphore
  if the user uploads hundreds at once).
