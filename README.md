# OnePass Quick

[![Build](https://github.com/awernick/onepass-quick/actions/workflows/build.yml/badge.svg)](https://github.com/awernick/onepass-quick/actions/workflows/build.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A lightweight macOS menu bar app that replaces 1Password's Quick Access popup. Uses the `op` CLI to search and retrieve credentials, rendered in a floating panel that tiling window managers ignore.

<p align="center">
  <img src="assets/demo.gif" alt="OnePass Quick demo" width="680">
</p>

## Why This Exists

1Password's native Quick Access creates a standard macOS window that tiling window managers (like [AeroSpace](https://github.com/nikitabobko/AeroSpace)) try to manage, causing workspace switching, popup disappearing, and focus issues. Alfred and Raycast integrations exist but have limitations (non-customizable shortcuts, automation bugs).

OnePass Quick uses an `NSPanel` at a floating window level that tiling WMs ignore -- the same technique Alfred and Raycast use for their own popups.

## Features

- Floating panel compatible with AeroSpace and other tiling WMs
- Fuzzy search across all 1Password items
- Keyboard-first workflow with customizable selection styles
- Concealed clipboard with automatic 30-second clear
- Global hotkey (Cmd+\\) with non-US keyboard layout support
- Deep linking into the 1Password desktop app

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Cmd+\` | Show/hide panel (global) |
| `Up/Down` | Navigate results |
| `Enter` | Open URL in browser |
| `Cmd+C` | Copy username |
| `Cmd+Shift+C` | Copy password |
| `Cmd+Option+C` | Copy one-time password |
| `Cmd+O` | Open in 1Password |
| `Esc` | Dismiss panel |

## Installation

### Prerequisites

- macOS 14 (Sonoma) or later
- [1Password desktop app](https://1password.com/downloads/mac/) with "Connect with 1Password CLI" enabled (Settings > Developer)
- [1Password CLI](https://developer.1password.com/docs/cli/get-started/): `brew install 1password-cli`

### Build from Source

```sh
brew install xcodegen fastlane
git clone https://github.com/awernick/onepass-quick.git
cd onepass-quick
fastlane mac install
```

This builds the app, installs it to `/Applications`, and launches it. Grant Accessibility permission when prompted (required for the global hotkey).

### Permissions

On first launch, macOS will prompt for:

- **Accessibility** -- required for the global Cmd+\\ hotkey (CGEvent tap)

Grant access in System Settings > Privacy & Security > Accessibility.

## Architecture

- **UI**: SwiftUI views embedded in an AppKit `NSPanel` (floating window level)
- **Backend**: `op` CLI for all 1Password data access (no direct vault access)
- **Hotkey**: CGEvent tap for global Cmd+\\ with `UCKeyTranslate` for keyboard layout support
- **Dependencies**: None -- system frameworks only

```
Cmd+\ pressed
  -> Toggle NSPanel visibility
  -> Load cached item list, focus search field
  -> User types -> fuzzy filter client-side (debounced, background thread)
  -> User selects item + action shortcut
  -> Fetch credentials via op CLI (on demand, not pre-fetched)
  -> Copy to clipboard (concealed, auto-clear 30s)
  -> Dismiss panel, restore focus to previous app
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, code style, and commit conventions.

## License

[MIT](LICENSE)
