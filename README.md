# Google Notes for Omarchy

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

A lightweight, keyboard-friendly **Google Keep checklist** bar widget and panel for the Omarchy Quattro shell — the Google Notes counterpart to [omarchy-google-tasks](https://github.com/CJKaufman/omarchy-google-tasks).

View a Google Keep checklist note, toggle checkboxes in real-time, and quick-add new items directly from the Omarchy top bar.

---

## ⚠️ Read this before installing

**Google Keep has no official API for personal Google accounts.** Google Tasks and Google Calendar have real, supported OAuth APIs; Keep does not. The only way for a third-party tool like this to talk to Keep is the same way [Home Assistant's `google_keep_sync` integration](https://github.com/watkins-matt/home-assistant-google-keep-sync) does it: through [`gkeepapi`](https://github.com/kiwiz/gkeepapi) and [`gpsoauth`](https://github.com/simon-weber/gpsoauth), which impersonate the Google Keep Android app using an internal, unofficial, reverse-engineered protocol.

That means:

- This is **not** endorsed, supported, or sanctioned by Google in any way, and could break at any time if Google changes its internal API.
- Authentication uses a Google **master token** (or an OAuth token that gets exchanged for one), obtained via a small external helper tool — **never your real Google account password**.
- A Keep master token's access **cannot be scoped**. It grants the same read/write access to Keep that your account itself has, to every note, and every list shared with it.
- **Strongly recommended:** use a dedicated, secondary Google account for this plugin, and share only the specific Keep notes you want to sync with it from your main account (Keep's collaborator/share feature). That way, if the token is ever exposed, the blast radius is limited to what you explicitly shared.

If that trade-off doesn't work for you, consider [omarchy-google-tasks](https://github.com/CJKaufman/omarchy-google-tasks) instead, which uses Google's real, officially supported Tasks API.

---

## ✨ Features

- **📋 Live Sync with a Google Keep checklist note:** pick any note with "Show checkboxes" enabled and sync its items.
- **☑️ Interactive checkboxes:** tick items off (or back on) directly from the bar.
- **➕ Quick Add:** type any item and press `Enter` to add it instantly.
- **🗒️ Multi-note switching:** seamlessly switch between different checklist notes.
- **🔒 Local-only credentials:** your token stays on your machine with restricted (`0600`) permissions — nothing is sent anywhere except Google's own servers.
- **📦 Self-contained dependency install:** the two required Python packages install into a private virtual environment scoped to this plugin, not your system Python.

---

## 🚀 Setup

### Step 1: Install the plugin's dependencies

Google Keep sync needs [`gkeepapi`](https://pypi.org/project/gkeepapi/) (which pulls in `gpsoauth`), neither of which is in the Python standard library. Rather than touching your system Python (fragile on Arch, whose Python is "externally managed"), the plugin bootstraps its own private virtual environment the first time you use it:

1. Open the **Google Notes** panel from the Omarchy top bar.
2. Click **Install Dependencies**. This creates a venv under the plugin's state directory and `pip install`s `gkeepapi` into it (needs a working internet connection; takes ~10–30 seconds).

### Step 2: Getting a Token

You have two options. A **master token** is the more reliable of the two.

#### Option A: Master Token via Docker (recommended)

Uses a small open-source helper container (not affiliated with this plugin) to perform the Android login handshake for you:

```bash
docker run -it --rm breph/ha-google-home_get-token:latest python3 get_tokens.py
```

- When prompted for a password, use a Google [App Password](https://myaccount.google.com/apppasswords) for the account (App Passwords require 2-Step Verification to be enabled).
- Copy the full **master token**, including the `aas_et/` prefix — it will be exactly 223 characters long.

#### Option B: OAuth Token

If the Docker approach doesn't work for you, follow [gpsoauth-java's instructions](https://github.com/rukins/gpsoauth-java/blob/master/README.md#receiving-an-authentication-token) to obtain a token starting with `oauth2_4/`. The plugin automatically exchanges this for a master token on first sign-in.

### Step 3: Connect the Plugin

1. Open the **Google Notes** panel (or click the settings ⚙️ gear icon).
2. Paste your **Google account email** and the **token** from Step 2.
3. Click **Sign In**.
4. In Google Keep (web, Android, or iOS), create — or pick an existing — note and turn on **"Show checkboxes"**. This becomes a syncable checklist.
5. Back in the panel, hit the refresh icon; your checklist note should appear.

---

## 📦 Installation

### Option 1: Via Omarchy CLI

```bash
omarchy plugin add https://github.com/M0ebiu5/omarchy-google-notes
```

### Option 2: Manual Clone

```bash
git clone https://github.com/M0ebiu5/omarchy-google-notes ~/.config/omarchy/plugins/waltermonschein.google-notes
omarchy-shell shell rescanPlugins
```

### Add to the Top Bar

```bash
omarchy bar put waltermonschein.google-notes --section right
```

### Removal

```bash
omarchy plugin remove waltermonschein.google-notes
```

This removes the plugin from the bar and its manifest/QML files. Your Keep master token and cached state are stored separately (not inside the plugin folder) — sign out from the panel first if you want those deleted too, or remove them manually:

```bash
rm -rf ~/.local/state/omarchy/waltermonschein.google-notes ~/.config/omarchy/waltermonschein.google-notes
```

---

## ⚙️ Configuration Options

Adjust these in `~/.config/omarchy/shell.json` or via `omarchy bar set`:

| Setting | Default | Description |
| :--- | :--- | :--- |
| `targetListTitle` | `"My Notes"` | Title of the Google Keep checklist note to sync by default. |
| `refreshIntervalSec` | `120` | Interval in seconds between background syncs. |
| `showCompleted` | `false` | Default state of the "Show finished items" toggle when the panel opens. |
| `countMode` | `"all"` | Bar badge count mode: `"all"` (all unchecked items) or `"none"` (hide badge). |

There's also a **"Show finished items"** toggle in the panel's Settings (gear icon) section, so you can flip it on or off per-session without touching config. It resets back to the `showCompleted` default the next time the panel loads.

---

## ⌨️ Keybindings in Panel

- `a`: Focus the quick-add input field.
- `r`: Force sync from Google Keep.
- `Esc`: Close the panel.

---

## 🛡️ Privacy & Security

- **No plugin-run servers:** communicates directly and exclusively with Google's own (unofficial, internal) Keep endpoints.
- **Local credential storage:** the master token and account email are saved in `~/.local/state/omarchy/waltermonschein.google-notes/` (falling back to `~/.config/omarchy/waltermonschein.google-notes/`) with `0600` permissions.
- **Unscoped access:** as noted above, the token grants full Keep read/write access. Use a dedicated Google account if you're at all concerned about blast radius.
- **Sign out anytime** from the panel's settings to delete the locally stored token and cached state.

---

## Limitations

- Google Keep list items don't have Google Tasks-style due dates or reminders, so there's no overdue/today badge here — just checkboxes.
- Only notes with **"Show checkboxes"** enabled in Keep show up as syncable lists.
- Each panel action is a fresh, one-shot sync against Keep — there's no realtime push, so very rapid back-to-back edits from multiple devices can occasionally race.
- This relies on an unofficial protocol. If Google changes something server-side, sync can break until `gkeepapi`/`gpsoauth` are updated upstream — at which point re-running "Install Dependencies" pulls the latest release.

---

## Credits

This plugin is a Google Notes counterpart to [omarchy-google-tasks](https://github.com/CJKaufman/omarchy-google-tasks) by Carl Kaufman, and its Keep authentication flow follows the approach pioneered by [home-assistant-google-keep-sync](https://github.com/watkins-matt/home-assistant-google-keep-sync) by Matt Watkins, built on [`gkeepapi`](https://github.com/kiwiz/gkeepapi) and [`gpsoauth`](https://github.com/simon-weber/gpsoauth).

## 📄 License

MIT License © 2026 Walter Monschein
