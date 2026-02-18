# Contributing to OnePass Quick

## Development Setup

### Prerequisites

- **Xcode 15+** with command line tools
- **1Password desktop app** with "Connect with 1Password CLI" enabled (Settings > Developer)
- **1Password CLI**: `brew install 1password-cli`
- **XcodeGen**: `brew install xcodegen`
- **Fastlane**: `brew install fastlane`

### Build from Source

```sh
git clone https://github.com/awernick/onepass-quick.git
cd onepass-quick
fastlane mac install    # build, install to /Applications, launch
```

Other build commands:

```sh
fastlane mac build      # build only
fastlane mac launch     # build and launch from DerivedData
fastlane mac clean      # clean build artifacts
fastlane mac generate   # regenerate .xcodeproj only
```

### Code Signing

By default, builds use ad-hoc signing ("Sign to Run Locally"). This works
for development but requires re-granting Accessibility permission after
each rebuild.

For stable TCC permissions, copy the example signing config and fill in
your Apple Developer Team ID:

```sh
cp project.local.example.yml project.local.yml
# Edit project.local.yml and replace YOUR_TEAM_ID_HERE
```

This file is gitignored and won't affect the repository.

## Code Style

- **Swift 5.9+**, macOS 14+ deployment target
- **4 spaces** indentation, **100 columns** line width
- **Naming**: Swift API Design Guidelines (`PascalCase` for types, `camelCase` for everything else)
- **Access control**: `private` by default, only expose what's needed
- **No force unwrapping** (`!`) except in tests
- **No third-party dependencies** -- system frameworks and `op` CLI only

### SwiftUI

- Keep views small and composable
- Extract reusable components into separate files
- Use `@State` for local state, `@ObservedObject`/`@StateObject` for shared state

### AppKit

- Keep AppKit code (NSPanel, NSEvent monitors) in dedicated files
- Use `NSHostingView` to embed SwiftUI in AppKit containers
- This is a macOS-only app -- no UIKit patterns

## Commit Conventions

All commits follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <description>
```

**Types:** `feat`, `fix`, `perf`, `refactor`, `docs`, `test`, `chore`, `ci`

**Scopes:** `panel`, `hotkey`, `search`, `clipboard`, `ui`

**Examples:**

```
feat(search): add fuzzy match highlighting
fix(clipboard): auto-clear after 30s not firing
refactor(panel): extract action handling
```

## Testing Changes

This project has no automated test suite yet. Before submitting a PR,
manually verify:

1. `fastlane mac build` succeeds
2. Panel shows/hides with Cmd+\
3. Search filters results as you type
4. All keyboard shortcuts work (see README for the full list)
5. Your specific change works as intended

## Security

- **Never** store or cache credentials on disk
- **Never** log sensitive data (passwords, usernames, OTP codes)
- All credential access goes through the `op` CLI
- Clipboard uses the concealed type and auto-clears after 30 seconds

## Pull Requests

- Keep PRs focused on a single change
- Reference the GitHub issue in the PR description
- Ensure the build passes (CI runs automatically)
- Be prepared for manual QA feedback before merge
