# AGENTS.md - OnePass Quick

## Overview

A lightweight macOS menu bar app that replaces 1Password's Quick Access popup.
Uses the `op` CLI to search and retrieve credentials, rendered in a floating
`NSPanel` that tiling window managers (AeroSpace) ignore.

**Why this exists:** 1Password's native Quick Access creates a standard macOS
window that AeroSpace tries to manage, causing workspace switching, popup
disappearing, and focus issues. Alfred and Raycast integrations exist but have
limitations (non-customizable shortcuts, automation task bugs). This app gives
full control over the UX.

## Repository Structure

```
OnePassQuick/
  OnePassQuick.xcodeproj/     # Xcode project
  OnePassQuick/
    App/
      AppDelegate.swift       # App lifecycle, menu bar setup, no dock icon
      main.swift              # Entry point
    Panel/
      QuickAccessPanel.swift  # NSPanel subclass (floating window level)
      PanelController.swift   # Show/hide logic, positioning
    Hotkey/
      HotkeyManager.swift    # Global Cmd+\ registration via CGEvent tap
    Search/
      OPClient.swift          # op CLI wrapper (item list, item get)
      ItemCache.swift         # In-memory cache with background refresh
      Item.swift              # Model for 1Password items
    Views/
      SearchView.swift        # SwiftUI: search field + results list
      ItemRow.swift           # SwiftUI: single result row
    Actions/
      ClipboardManager.swift  # NSPasteboard with concealed type, auto-clear
      ActionHandler.swift     # Route keyboard shortcuts to actions
    Resources/
      Assets.xcassets/        # App icon, menu bar icon
      Info.plist              # LSUIElement=true (no dock icon)
AGENTS.md                     # This file
LICENSE
.gitignore
```

## Tech Stack

- **Language**: Swift 5.9+
- **UI**: SwiftUI views embedded in AppKit `NSPanel`
- **Minimum target**: macOS 14 (Sonoma)
- **Dependencies**: None (uses only system frameworks + `op` CLI)
- **Backend**: `op` CLI (1Password CLI, installed via `brew install 1password-cli`)

## Build / Run / Test

```sh
# Build
xcodebuild -project OnePassQuick.xcodeproj -scheme OnePassQuick -configuration Debug build

# Run (after build)
open build/Debug/OnePassQuick.app

# Or open in Xcode
open OnePassQuick.xcodeproj
```

No third-party dependencies. No CocoaPods, SPM packages, or Carthage.

### Prerequisites

- 1Password desktop app installed
- 1Password CLI: `brew install 1password-cli`
- "Connect with 1Password CLI" enabled in 1Password > Settings > Developer
- Accessibility permissions granted (for global hotkey)

## Architecture

### Window Layer

The app uses `NSPanel` (not `NSWindow`) with a high window level:

```swift
panel.level = .floating  // or .popUpMenu
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
panel.isFloatingPanel = true
panel.hidesOnDeactivate = true
```

This is critical -- AeroSpace and other tiling WMs ignore windows at these
levels. This is how Alfred and Raycast avoid tiling conflicts.

### Global Hotkey

Register `Cmd+\` globally using `CGEvent.tapCreate` or
`NSEvent.addGlobalMonitorForEvents`. The hotkey toggles panel visibility.
When shown, the search field receives first responder focus immediately.

### op CLI Integration

All 1Password data access goes through the `op` CLI:

```sh
# List all items (cached)
op item list --format json --cache

# Get specific fields for an item
op item get <item-id> --fields username,password --format json --cache

# Get item URL
op item get <item-id> --fields url --format json --cache
```

Authentication is handled by the 1Password desktop app via biometric unlock.
The `op` CLI connects to it when "Connect with 1Password CLI" is enabled.

### Clipboard

Use `NSPasteboard` with the concealed type so password managers and clipboard
history tools know the content is sensitive:

```swift
let pasteboard = NSPasteboard.general
pasteboard.clearContents()
pasteboard.setString(text, forType: .init("org.nspasteboard.ConcealedType"))
pasteboard.setString(text, forType: .string)
```

Auto-clear clipboard after 30 seconds.

### Data Flow

```
Cmd+\ pressed
  → Toggle NSPanel visibility
  → If showing: load cached item list, focus search field
  → User types → filter results client-side (no CLI call per keystroke)
  → User selects item + presses action shortcut
  → Fetch credentials via `op item get` (on demand, not pre-fetched)
  → Copy to clipboard (concealed, auto-clear 30s)
  → Dismiss panel, restore focus to previous app
```

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Cmd+\` | Show/hide panel (global hotkey) |
| `↑/↓` | Navigate results |
| `Enter` | Open URL in default browser |
| `Cmd+C` | Copy username to clipboard |
| `Cmd+Shift+C` | Copy password to clipboard |
| `Cmd+O` | Open item in 1Password app |
| `Esc` | Dismiss panel |

These shortcuts are the primary reason this app exists. They must be
customizable in a future version, but for the MVP they are hardcoded.

## Development Tooling

| Tool | Purpose |
|------|---------|
| XcodeBuildMCP | Build Xcode projects, parse errors |

## Milestones

Development is tracked in GitHub issue #1. The milestones are:

1. **M1: Window + Hotkey** -- NSPanel, global Cmd+\, AeroSpace compatibility
2. **M2: Search + Results** -- op CLI integration, search field, results list
3. **M3: Actions + Clipboard** -- copy username/password, open URL, concealed clipboard
4. **M4: Polish** -- caching, start at login, icon, distribution

Implement milestones sequentially. Each milestone should produce a working
(if incomplete) app.

### Milestone to Version Mapping

| Milestone | Version | Description |
|-----------|---------|-------------|
| M1: Window + Hotkey | v0.1.0 | NSPanel, global hotkey, AeroSpace compat |
| M2: Search + Results | v0.2.0 | op CLI integration, search, results list |
| M3: Actions + Clipboard | v0.3.0 | Copy credentials, open URL, concealed clipboard |
| M4: Polish | v1.0.0 | Caching, start at login, distribution |

### QA Before Commit

After completing a milestone, **do not commit immediately**. Human QA is
non-negotiable for UI work:

1. Build and run the app
2. Output a list of **test scenarios** the user should manually verify
3. Wait for the user to confirm everything works or report issues
4. Fix any issues found during QA
5. Only then commit, push, and close issues

The user must always get a chance to interact with the result before it's
committed. Never skip this step.

## Git Workflow

> General git workflow (issue-first, conventional commits, semver, releasing)
> is defined in the global `~/.config/opencode/AGENTS.md`.

### Conventional Commit Scopes

**Scopes:** `panel`, `hotkey`, `search`, `clipboard`, `ui`

**Examples:**
```
feat(panel): add NSPanel with floating window level
feat(hotkey): register global Cmd+\ via CGEvent tap
feat(search): integrate op CLI item list
fix(clipboard): auto-clear after 30s not firing
chore: scaffold Xcode project
```

## Code Style

### Swift

- **Swift version**: 5.9+
- **Indentation**: 4 spaces
- **Line width**: 100 columns
- **Naming**: Swift API Design Guidelines
  - Types: `PascalCase` (`QuickAccessPanel`, `ItemCache`)
  - Functions/properties: `camelCase` (`fetchItems()`, `isVisible`)
  - Constants: `camelCase` (`let maxResults = 50`)
- **Access control**: Mark everything `private` by default, only expose what's
  needed. Use `internal` (implicit) for same-module access.
- **Error handling**: Use `Result` or `async throws`. No force unwrapping
  (`!`) except in tests or `IBOutlet`.
- **Comments**: Use `///` for documentation comments, `//` for inline.
  Don't over-comment obvious code.

### SwiftUI Views

- Keep views small and composable
- Extract reusable components into separate files
- Use `@State` for local state, `@ObservedObject` / `@StateObject` for
  shared state
- Preview providers for all views

### AppKit Integration

- Keep AppKit code (NSPanel, NSEvent monitors) in dedicated files
- Use `NSHostingView` to embed SwiftUI views in AppKit containers
- Don't mix UIKit patterns -- this is a macOS-only app

## Design Conventions

- **No dock icon**: Set `LSUIElement = true` in Info.plist
- **Menu bar presence**: Small icon in menu bar for quit/preferences
- **Panel appearance**: Dark, translucent, similar to Spotlight/Alfred
- **Keyboard-first**: Every action must be reachable via keyboard.
  Mouse support is secondary.
- **Fast dismiss**: Esc or clicking outside the panel dismisses it
- **Focus restoration**: After dismissing, focus returns to the
  previously active window

## Security

- **NEVER** store or cache passwords/credentials on disk
- **NEVER** log sensitive data (passwords, usernames, secret keys)
- Credentials exist only in memory, briefly, during clipboard operations
- Clipboard auto-clears after 30 seconds
- All credential access goes through the `op` CLI -- this app never
  accesses 1Password vaults directly
- The `op` CLI handles authentication via the 1Password desktop app
