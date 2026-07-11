# ClaudeUsage

A native macOS menu bar app for Claude Code usage monitoring — real-time plan limits, weekly stats, and token tracking, without leaving your workflow.

## Features

- **Menu bar at a glance** — Rolling 5-hour usage percent and countdown timer, right in the menu bar. Configurable label: percent + time, percent only, or icon only.
- **Color-coded urgency** — Label shifts from neutral to warning to critical as you approach plan limits.
- **Weekly stats & history** — Sparkline and trend chart of usage over time, computed from your local session history.
- **No re-auth prompts** — Reads Claude Code's own Keychain credential once, then caches its own token copy so cold starts don't re-trigger a macOS keychain "Always Allow" prompt.
- **Settings window** — `⌘,` for menu bar format and preferences.

## Install

### Build from Source

Requires: Swift 6.0 toolchain, macOS 14+

```bash
git clone https://github.com/josh-stoner/ClaudeUsage.git
cd ClaudeUsage
./build.sh
```

`build.sh` builds a release binary, assembles the `.app` bundle, code-signs it with your local signing identity, installs it to `/Applications`, and registers a LaunchAgent so it starts automatically.

Optional: `./build.sh --notarize` submits the build to Apple notarization (requires a one-time `xcrun notarytool store-credentials` setup).

### First Launch (Gatekeeper)

If you build with an Apple Development (not Developer ID) certificate, macOS will block the app on first launch — open **System Settings > Privacy & Security**, find "ClaudeUsage was blocked," and click **Open Anyway**. One-time step.

## Requirements

- macOS 14.0 (Sonoma) or later
- A local Claude Code installation with an active session (the app reads Claude Code's Keychain credential to compute usage)

## Tech

- Swift Package Manager (`swift-tools-version: 6.0`)
- SwiftUI `MenuBarExtra`
- Keychain Services for credential caching
- `os.log` for diagnostics
- Deterministic codesign + notarize + LaunchAgent install pipeline (`build.sh`)

## License

Copyright 2026 Josh Stoner. All rights reserved.
