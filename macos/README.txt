ASIDE CLEAN LOGO — macOS 12 or later, Apple Silicon and Intel

Open Aside Clean Logo.app in this disk image. Click Install. If Aside was not
found in /Applications or ~/Applications, choose your installed Aside.app.
The helper and icon backup live in your account's Library/Application Support/
Aside Clean Logo. A per-user launch agent starts the appearance watcher at login.
After installation you may eject this disk image and quit the installer.

System dark appearance uses white.png; light appearance uses black.png.
Finder/app custom icons switch automatically. A pinned or running Dock tile
can retain its cached icon. Relaunching Aside may help; live Dock switching is
not guaranteed and has not been verified with the real Aside app on hardware.
The helper never restarts Aside or the Dock and does not modify Aside's signed
Contents, profile, cookies, or sessions. It checks Aside's code signature before
and after customization and retains the original icon backup for restoration.
Existing desktop aliases use macOS icon caching; refreshing them is not guaranteed.

Your account needs write permission for Aside.app. A read-only, managed, or
administrator-owned installation can refuse custom icons. The installer reports
the failure; it does not elevate privileges or change permission settings.
Account-owned Aside installations in ~/Applications are supported.

UNINSTALL: Open this installer again (or open the helper application inside
~/Library/Application Support/Aside Clean Logo) and click Uninstall / Restore.
This stops the watcher, restores original icon metadata, and removes the helper,
login agent, and backup. If Aside was moved, put it back at the configured path
before uninstalling. Do not manually delete the backup before restoring.

SECURITY: This build has only an ad-hoc code signature. It is not signed with an
Apple Developer ID and is not notarized. Gatekeeper can block it. Review the
source and release checksum before deciding whether to allow it through macOS
System Settings > Privacy & Security > Open Anyway. This is Apple's normal
per-app approval flow. No quarantine removal or Gatekeeper bypass is included.
Managed Macs may disallow unnotarized software entirely.

Runner tests verify a disposable signed fixture, theme mapping, watcher state,
backup preservation, restore, and signature integrity. They do not establish
real Aside Dock behavior or permission compatibility on every Mac.
