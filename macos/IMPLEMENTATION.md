# macOS behavior and verification

```sh
bash macos/build.sh
# The build invokes native fixture tests. Repeat them with:
bash macos/test.sh
```

Output: `dist/Aside-Clean-Logo-macOS.dmg`, containing a universal arm64/x86_64
macOS 12+ AppKit application with Install, Choose Aside, and Uninstall buttons.
Target Macs do not need a development environment or network download.

## Native evidence and scope

The first native runner successfully compiled both architectures, but applying
`NSWorkspace.setIcon` directly to a signed fixture failed
`codesign --verify --deep --strict` with “resource fork, Finder information, or
similar detritus not allowed.” Apple explains this restriction in
[Technical Q&A QA1940](https://developer.apple.com/library/archive/qa/qa1940/_index.html).
Verification has therefore **not** been weakened. Instead, only an installer-owned
Finder alias on the user's Desktop receives custom-icon metadata. The real
Aside.app is never modified, and strict signature validation remains in place.

The desktop alias opens the original application and switches white in dark
appearance and black in light appearance. The original application icon, other
shortcuts, and running/pinned Dock tile remain unchanged. This is an explicit
desktop-only macOS scope, not a promise of cross-process Dock customization.

## Implementation

The native alias is created with Foundation's
[`suitableForBookmarkFile`](https://developer.apple.com/documentation/corefoundation/cfurlbookmarkcreationoptions/suitableforbookmarkfile)
and [`URL.writeBookmarkData`](https://developer.apple.com/documentation/foundation/url/writebookmarkdata(_:to:)).
It is resolved and checked against the configured Aside target before changing
its icon. An existing file at the chosen desktop path is never overwritten.
Only the managed alias is passed to
[`NSWorkspace.setIcon`](https://developer.apple.com/documentation/appkit/nsworkspace/seticon(_:forfile:options:)).
Desktop permission denial is an error; no app ownership change or elevation is needed.

The helper lives under per-user Application Support and a LaunchAgent runs it
in that user's Aqua session. `NSApplication.effectiveAppearance` is observed,
with a 10-second retry timer. Installation stages a signed replacement and saves
the previous helper, agent definition, loaded state, and alias metadata. A unique
token acknowledgment after the watcher's first successful update is required
before installation succeeds. Apply/bootstrap/readiness failures restore the
previous files and restart the old watcher; rollback failures identify recovery
files. Uninstall stops the watcher and removes only its managed alias and files.

## Tests and distribution

The native suite verifies signed-fixture integrity with unchanged strict checks,
actual Finder alias resolution, different light/dark icon resource forks, exact
alias metadata rollback, first-backup preservation, removal on uninstall, and
collision refusal. Failure tests inject apply/bootstrap/readiness errors and
check helper/plist/loaded-state/alias recovery. Missing/stale readiness is rejected.
`test.sh` also compares the fixture executable hash before and after.

The app is ad-hoc signed, not Developer ID signed or notarized. Follow only
[Apple's per-app approval flow](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac)
if the user decides to trust the release. No quarantine or Gatekeeper bypass is
included. Real Aside launching and Desktop privacy prompts require hardware
validation; runner fixture results do not establish those behaviors.
