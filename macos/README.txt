ASIDE CLEAN LOGO — macOS 12 or later, Apple Silicon and Intel

Open Aside Clean Logo.app in this disk image. Click Install. If Aside was not
found in /Applications or ~/Applications, choose your installed Aside.app.
The installer creates an Aside Clean Logo alias on your Desktop. Double-click
that alias to open the real Aside. Its icon follows your Mac's system appearance:
dark uses white.png; light uses black.png. An existing file at the alias location
is never overwritten. Desktop access may need approval in Privacy & Security.

IMPORTANT SCOPE: Only the new desktop alias changes. The original Aside.app,
existing shortcuts, and running/pinned Dock icon remain unchanged. A signed app
cannot safely receive FinderInfo/resource-fork custom-icon metadata under strict
code-signature validation. The helper never changes Aside.app or restarts Aside
or the Dock. Browser profiles, cookies, and sessions are preserved.

The helper and installation backup live in your account's Library/Application
Support/Aside Clean Logo. A per-user launch agent starts the appearance watcher
at login. After installation you may eject this image and quit the installer.
Installation waits for the watcher to confirm a successful initial alias update.
If an update or login-agent start fails, the previous helper and alias are
restored; the installer reports any recovery step that needs attention.

UNINSTALL: Open this installer again (or open the helper application inside
~/Library/Application Support/Aside Clean Logo) and click Uninstall / Restore.
This stops the watcher and removes its managed alias, helper, agent, and backup.
Do not move or repurpose the managed alias while the helper is installed.

SECURITY: This build has only an ad-hoc code signature. It is not signed with an
Apple Developer ID and is not notarized. Gatekeeper can block it. Review the
source and release checksum before deciding whether to allow it through macOS
System Settings > Privacy & Security > Open Anyway. This is Apple's normal
per-app approval flow. No quarantine removal or Gatekeeper bypass is included.
Managed Macs may disallow unnotarized software entirely.

Native runner tests use a disposable signed app to verify alias resolution,
light/dark icon application, rollback, uninstall, and unchanged strict signature.
Actual Aside launching and desktop permission behavior require hardware testing.
