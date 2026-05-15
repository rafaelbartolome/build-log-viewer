# Build Log Viewer

A small native macOS app for reading noisy CI build logs.

Build Log Viewer cleans terminal escape sequences, normalizes line endings, removes empty display rows, and highlights the lines that usually matter most: errors, warnings, build-failure summaries, and Fastlane/Xcode exit status messages.

<img width="1312" height="766" alt="Screenshot 2026-05-15 at 18 16 18" src="https://github.com/user-attachments/assets/8ca26f8a-eb76-480f-bf88-91201d6fcf74" />

## Features

- Open `.log` and plain-text files from disk.
- Drag and drop logs into the window.
- Search with next/previous match navigation.
- Navigate to previous/next detected error.
- Sidebar groups findings by errors, warnings, build failures, and tool output.
- AppKit-backed text view for large logs and long lines.
- Original log line numbers in a left gutter.
- Warning glyph lines are treated as warnings, not errors.

## Build

```bash
swift test
Scripts/build-app.sh
```

The app bundle is written to:

```text
.build/BuildLogViewer.app
```

## Run

```bash
open .build/BuildLogViewer.app --args /path/to/build.log
```

## Notes

The parser is intentionally rule-based and local-only. It does not upload logs or require network access.
