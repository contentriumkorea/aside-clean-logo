# Actual Aside Dock investigation — publication held

The desktop-alias implementation does not meet the user's requirement to change
the real running/pinned Aside Dock icon. It must not be presented as fulfilling it.

Run the diagnostic only on an ephemeral GitHub macOS runner with a GUI session:

```sh
bash macos/dock-probe.sh dist/dock-probe
```

Upload `dist/dock-probe` using an `always()` workflow step, even if the command
fails. No installer/release source is modified by the diagnostic. It downloads
the official Aside disk image, copies the app into temporary storage, and runs
it with a new isolated user-data directory. The target's signed Contents and
code-directory hash must remain unchanged. No resource replacement, re-signing,
code injection, quarantine removal, policy bypass, or browser restart is used.
An optional Dock process refresh is recorded separately from the natural update.
Only the probe's launched application is asked to quit afterward.

The runner Dock receives temporary pinned entries for the signed fixture and
the downloaded Aside app. Its full preference domain is backed up and restored.
This is test setup, not a claim that Dock preference editing is a production API.

## Evidence to inspect

For both fixture and real Aside, `phases.json` records four phases: original,
black after a natural repaint opportunity, white after a natural repaint
opportunity, and white after restarting **only the Dock**. Each phase records:

- The original app PID and whether it stayed alive, confirming no browser restart.
- Normal `codesign --verify --deep` and CLI `--strict` results separately.
- Uncached `spctl --assess --type execute --verbose=4 --ignore-cache` results.
- The original signature/CDHash and signed Contents manifest comparison.
- Custom-icon metadata, the file icon, and `NSRunningApplication.icon` samples.
- An actual screen capture plus Dock window metadata for direct visual inspection.

The TIFF samples are supplementary. They do **not** prove what the running Dock
rendered. The PNG screenshots must show the actual Aside tile changing through
both variants; human inspection is required. If screenshots are unavailable,
visual support remains unverified. A successful process exit alone cannot prove
Dock support. The ad-hoc fixture's Gatekeeper rejection is expected and recorded;
the official notarized Aside must be accepted both before and after each change.

Original custom-icon metadata is restored and checked exactly. Strict validation
must pass again afterward. Signed Contents manifests before/after are retained.

## Primary-source correction and current hypothesis

[Apple QA1940](https://developer.apple.com/library/archive/qa/qa1940/_index.html)
describes a *signing/build* restriction on FinderInfo/resource forks. Our original
CLI `--strict` failure by itself was insufficient to conclude that a user-applied
Finder icon invalidates normal signature verification or Gatekeeper acceptance.

Apple's published Security implementation distinguishes these checks:

- [`bundlediskrep.cpp`](https://github.com/apple-oss-distributions/Security/blob/main/OSX/libsecurity_codesigning/lib/bundlediskrep.cpp)
  permits a non-executable root `Icon\r` file and rejects root sideband metadata
  only when `kSecCSRestrictSidebandData` is set.
- [`StaticCode.cpp`](https://github.com/apple-oss-distributions/Security/blob/main/OSX/libsecurity_codesigning/lib/StaticCode.cpp)
  likewise makes resource sideband checks conditional on validation flags.
- [`policyengine.cpp`](https://github.com/apple-oss-distributions/Security/blob/main/OSX/libsecurity_codesigning/lib/policyengine.cpp)
  requests strict structure checks but does not add `kSecCSRestrictSidebandData`
  in the visible execution-assessment path. This suggests the CLI `--strict`
  result can differ from real Gatekeeper. It is a hypothesis until tested on the
  current OS and official app; published source is not a current-system guarantee.

[`NSWorkspace.setIcon`](https://developer.apple.com/documentation/appkit/nsworkspace/seticon(_:forfile:options:))
is a documented file-customization API. Whether its result propagates to a
running Chromium Dock tile automatically is an empirical question, separate
from signature integrity and policy acceptance.

[`NSApplication.applicationIconImage`](https://developer.apple.com/documentation/appkit/nsapplication/applicationiconimage)
supports an app changing its own running Dock tile; another process cannot set
that property through `NSRunningApplication`, whose
[`icon`](https://developer.apple.com/documentation/appkit/nsrunningapplication/icon)
is read-only. A native first-party hook is the clean fallback if file-level
customization does not propagate. A
[`Dock tile plug-in`](https://developer.apple.com/documentation/bundleresources/information-property-list/nsdocktileplugin)
would require modifying the signed Aside bundle and is not a suitable external
helper implementation. Static `.icns` or `Assets.car` swapping also modifies
sealed resources and is excluded from this probe.
