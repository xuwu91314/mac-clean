# Privacy Policy — MacClean

Last updated: October 27, 2026

## Summary

**MacClean does not collect, transmit, or share any personal data.**
Everything the app does happens locally on your Mac.

## What the app accesses

| Data | Why | Where it goes |
|---|---|---|
| Folder contents you explicitly grant via the system folder picker | To calculate size and clean caches/logs you selected | Nowhere — processed in memory only |
| Disk capacity and free space | To display the storage overview | Nowhere |
| Memory and swap statistics | To display the memory overview | Nowhere |
| Your granted-folder bookmarks | So you don't have to re-authorize the same folder | Stored locally in macOS UserDefaults |

## What the app does NOT do

- No network requests of any kind. The app does not contain networking code.
- No accounts, no sign-in, no cloud sync.
- No analytics, telemetry, crash reporting, or advertising SDKs.
- No access to contacts, photos, calendar, location, microphone, camera, or clipboard.
- No data is sent to the developer or any third party.

## Permissions

MacClean runs inside the macOS App Sandbox with exactly two file-related entitlements:

- `com.apple.security.files.user-selected.read-write` — read/write only for folders **you** pick in the system dialog
- `com.apple.security.files.bookmarks.app-scope` — remember those picks across launches

Because of the sandbox, the app is technically incapable of reading anything you have not explicitly granted.

## Deletion behavior

- Cache and log cleanup permanently removes items **inside the folders you authorized**, after an explicit confirmation dialog.
- Large-file removal uses the system Trash (`FileManager.trashItem`) and is recoverable.
- The App Store edition never touches system-level paths (`/Library/*`) and never runs privileged commands.

## Children

The app is a general-purpose utility and is not directed at children. It collects no data from anyone.

## Changes

If this policy changes, the updated version will be published at this URL with a new "last updated" date.

## Contact

Open an issue at https://github.com/xuwu91314/mac-clean/issues
