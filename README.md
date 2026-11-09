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

1. Reads your Claude Code OAuth token from the macOS Keychain (`Claude Code-credentials`) — usage data from claude.ai/Desktop/CLI is all aggregated server-side, so any Claude Code session counts
2. Fetches usage data from the Anthropic API on-demand when you open the popover, with a background refresh every 30 minutes
3. **Auto-refreshes the OAuth token** when it expires using the stored refresh token, so you don't need to keep `claude` running in a terminal — the Keychain entry is updated atomically (`security add-generic-password -U`) so the CLI stays logged in
4. Caches usage data locally so the app stays responsive even when the API is unavailable

**No API keys or manual configuration required!** — it uses the same credentials that Claude Code CLI stores automatically.

## Features

- Weekly plan usage in the menu bar with color-coded icon (green / orange / red) — Claude now meters usage per week rather than per 5-hour window
- Pace tracking: a marker on the weekly bar shows how much of the week has passed, so you can tell at a glance whether you're burning faster than the week allows, plus a per-day budget for the remaining days
- Per-model weekly caps (e.g. Fable) read from the API's `limits` list, so new model caps show up without an app update
- "This week by app" breakdown (Claude Code / Chats / Cowork)
- Extra usage spend when enabled, and the 5-hour window if your plan still has one
- On-demand refresh when opening the popover (30s cooldown)
- Background polling every 30 minutes to stay up-to-date
- Automatic OAuth token refresh — works even if you only use Claude Desktop and never open a terminal
- Local disk cache for persistent data across app restarts
- Launch at login support
- Automatic update notifications via GitHub Releases (checks every 24h)

## Prerequisites

- macOS 14.0 (Sonoma) or later
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) — run `claude` at least once to store OAuth credentials in your macOS Keychain

## License

MIT
