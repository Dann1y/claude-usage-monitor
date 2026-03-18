# Claude Usage Monitor

[한국어](README_KO.md)

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
brew upgrade --cask claude-usage-monitor
```

> If `brew upgrade` doesn't detect new versions, run this once to fix it:
> ```bash
> git -C "$(brew --repository dann1y/tap)" config homebrew.forceautoupdate true
> ```

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

1. Reads your Claude Code OAuth token from the macOS Keychain in **read-only mode** (`Claude Code-credentials`) — never writes to the Keychain, so it won't interfere with Claude Code CLI
2. Fetches usage data from the Anthropic API on-demand when you open the popover, with a background refresh every 30 minutes
3. Caches usage data locally so the app stays responsive even when the API is unavailable or the token has expired

**No API keys or manual configuration required!** — it uses the same credentials that Claude Code CLI stores automatically.

## Features

- Live usage percentage in the menu bar with color-coded icon (green / orange / red)
- 5-hour sliding window utilization with reset countdown
- 7-day weekly utilization with per-model breakdown (Opus, Sonnet)
- On-demand refresh when opening the popover (30s cooldown)
- Background polling every 30 minutes to stay up-to-date
- Local disk cache for persistent data across app restarts
- Graceful handling of expired tokens with cached data fallback
- Launch at login support
- Automatic update notifications via GitHub Releases (checks every 24h)

## Prerequisites

- macOS 14.0 (Sonoma) or later
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) — run `claude` at least once to store OAuth credentials in your macOS Keychain

## License

MIT
