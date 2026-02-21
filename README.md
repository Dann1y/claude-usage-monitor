# Claude Usage Monitor

<img width="376" height="328" alt="image" src="https://github.com/user-attachments/assets/eaa3dc93-b4a1-496d-a7dc-f7e5909d716e" />

A lightweight macOS menu bar app that shows your Claude (claude.ai) usage in real time.

![macOS](https://img.shields.io/badge/macOS-14.0%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange)

## Install

### Step 1. Download

**Homebrew (Recommended)**

```bash
brew tap Dann1y/tap
brew install --cask claude-usage-monitor
```

**Or manually**

```bash
git clone https://github.com/Dann1y/claude-usage-monitor.git
cd claude-usage-monitor
make install
```

### Step 2. Allow app to run

Since this app is not notarized with Apple, macOS will block it on first launch. Run this once:

```bash
xattr -cr "/Applications/Claude Usage Monitor.app"
```

Then open the app. It appears in your menu bar — enable **Launch at login** in Settings to keep it running permanently.

## Update

The app checks for new versions automatically every 24 hours and shows a notification badge when an update is available.

**Homebrew**

```bash
brew upgrade claude-usage-monitor
```

**Or manually**

```bash
cd claude-usage-monitor
git pull
make install
```

## Uninstall

```bash
brew uninstall claude-usage-monitor
# or
make uninstall
```

## How It Works

1. Reads your Claude Code OAuth token from the macOS Keychain (`Claude Code-credentials`)
2. Polls the Anthropic usage API (`https://api.anthropic.com/api/oauth/usage`) at the configured interval
3. Watches `~/.claude/projects` for file changes and triggers an extra refresh when activity is detected

**No API keys or manual configuration required!** — it uses the same credentials that Claude Code CLI stores automatically.

## Features

- Live usage percentage in the menu bar with color-coded icon (green / orange / red)
- 5-hour sliding window utilization
- 7-day weekly utilization with per-model breakdown (Opus, Sonnet)
- Reset countdown timers
- Configurable refresh interval (15s / 30s / 1min)
- Launch at login support
- Auto-refresh on local Claude file changes
- Automatic update notifications via GitHub Releases (checks every 24h)

## Prerequisites

- macOS 14.0 (Sonoma) or later
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) — run `claude` at least once to store OAuth credentials in your macOS Keychain

## License

MIT
