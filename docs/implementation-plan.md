# Aside Clean Logo Implementation Plan

> **For agentic workers:** implement the independent platform tasks, then integrate and review the release as a whole.

**Goal:** Install the approved logo variants and switch them with system appearance on Windows/macOS, with backups and reversible uninstall.

**Architecture:** Two native helpers, shared icon assets, public GitHub releases. Windows installation is elevated and protected; macOS uses supported AppKit APIs and launchd.

**Tech Stack:** C#/.NET Framework 4.8, Swift/AppKit, GitHub Actions, Python/Pillow only for asset packaging and independent validation.

**Spec:** docs/design.md

## Global Constraints

- Dark theme = white, light theme = black.
- Preserve original Aside binaries, user data, and signatures.
- Reuse assets/black.png and assets/white.png without regenerating artwork.
- Back up originals before first change; restore during uninstall.
- Installation and release must contain usable native artifacts, not only source ZIPs.

## Review Focus

- Elevated Windows helpers must execute only from protected installation locations.
- Updates/reinstallation must preserve the first original shortcut/icon backup.
- Missing Aside and denied permission must produce clear errors without false success.
- Theme transitions, new browser windows and logon startup must be exercised.
- macOS Finder/Dock differences and unsigned/notarized status must be accurately documented.

### Task 1: Windows installer and helper

- [ ] Add behavior tests for light/dark mapping, first-backup preservation and install/restore.
- [ ] Implement windows/ installer, protected scheduled watcher, discovery and reversible uninstall.
- [ ] Build a real Windows Setup executable with embedded shared assets and run tests.
- [ ] Install locally with UAC and verify desktop, taskbar and running-window state; retire prototype only after success.

### Task 2: macOS installer and helper

- [ ] Verify the supported customization API and Dock behavior constraints using primary documentation.
- [ ] Implement macos/ native installer/helper and launch agent with permission handling.
- [ ] Add macOS app-fixture tests for icon apply/restore and code-signature preservation.
- [ ] Build usable installation artifact on a macOS runner and report testing limits precisely.

### Task 3: Integrate, review and publish

- [ ] Validate approved assets and publish portable shared asset names.
- [ ] Add GitHub Actions platform build/test/package jobs, release uploads and checksums.
- [ ] Review implementation, repair material issues and run platform checks.
- [ ] Publish README download buttons, source and versioned GitHub release.
- [ ] Download published installers and verify hashes and expected artifact contents.
