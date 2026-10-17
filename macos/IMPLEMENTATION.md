# macOS behavior and verification

Build and test on a Mac with Xcode Command Line Tools:

```sh
bash macos/build.sh
# The build invokes the native fixture suite. Repeat it separately if needed:
bash macos/test.sh
```

The output is `dist/Aside-Clean-Logo-macOS.dmg`, containing a universal arm64/x86_64
AppKit application with Install, Choose Aside, and Uninstall / Restore buttons.
No Python, Homebrew, shell setup, or network download is needed on the target Mac.
The development build requires Xcode, but the installed application does not.

The launch agent uses the installed helper rather than an executable inside the
mounted DMG. It runs only in the installing account's Aqua login session.
`NSApplication.effectiveAppearance` is observed; a 10-second timer retries failed
updates. The first original icon backup is immutable across reinstallations.
Installation stages the replacement before stopping a previous watcher and keeps
the previous helper, agent definition, loaded state, and current icon until a new
watcher returns a unique-token acknowledgment after its first successful update.
Apply, bootstrap, and readiness failures restore those previous files and restart
the prior watcher. An incomplete rollback reports the retained recovery path.
`NSWorkspace.setIcon` does the customization; original FinderInfo/resource-fork
bytes and the pre-existing `Icon\r` file are saved and restored. Neither the Aside
Contents directory nor browser user data is accessed by the implementation.

The native `--self-test` mode only operates on an explicitly supplied disposable
fixture. It exercises both image variants, metadata changes/restoration, backup
preservation, theme transitions and retry logic. `test.sh` verifies the fixture's
signature and executable hash before and after. The build is universal and
ad-hoc signed, without Developer ID credentials or notarization.
Failure injection also exercises first-install bootstrap denial and upgrade
apply/bootstrap/readiness failures with actual isolated file moves and icon
restoration, plus rejection of absent, stale, and invalid readiness messages.

## Supported APIs and scope

- Apple's [`NSWorkspace.setIcon(_:forFile:options:)`](https://developer.apple.com/documentation/appkit/nsworkspace/seticon(_:forfile:options:))
  customizes the file icon. The return value is checked; permission denial is an error.
- Apple's [`NSApplication.effectiveAppearance`](https://developer.apple.com/documentation/appkit/nsapplication/effectiveappearance)
  is used to match `.darkAqua` and `.aqua` without private distributed notifications.
- Apple's [`NSApplication.applicationIconImage`](https://developer.apple.com/documentation/appkit/nsapplication/applicationiconimage)
  changes the application's own running Dock tile. This utility cannot use it to
  control Aside's tile. Live cross-process Dock changes are not promised.
- Apple documents [changing/restoring custom file icons](https://support.apple.com/guide/mac-help/change-icons-for-files-or-folders-on-mac-mchlp2313/mac)
  in Finder. Existing Finder aliases and Dock tiles may retain cached icons;
  the utility does not delete caches, restart processes, or patch signed resources.
- Apple documents the user decision to [open an app from an unknown developer](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac).
  The installer does not remove quarantine or alter security policy.

Real Aside installation permission behavior, its updater, running/pinned Dock
refresh, and desktop alias refresh require actual-Mac validation. The fixture
suite and successful packaging must not be described as those hardware tests.
