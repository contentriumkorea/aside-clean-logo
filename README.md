# Aside Clean Logo

Clean, transparent black/white icons for the Aside desktop browser. **Dark appearance → white. Light appearance → black.** The central sparkle stays bold while the circular and curved lines are thinner.

The artwork uses the original vector paths from [Aside's official website](https://aside.com/), with no AI redrawing. The original Bezier coordinates and outer silhouette are retained. Internal boundaries are inset by 0.18 vector units, and the central sparkle's protected pixels are copied exactly from the original rendering. These invariants are tested.

![Black and white icon previews](assets/preview.png)

[![Install for Windows](https://img.shields.io/badge/Windows-Download_Setup-0078D4?style=for-the-badge&logo=windows)](https://github.com/contentriumkorea/aside-clean-logo/releases/latest/download/Aside-Clean-Logo-Windows-Setup.exe)
[![Install for macOS](https://img.shields.io/badge/macOS-Download_Installer-222222?style=for-the-badge&logo=apple)](https://github.com/contentriumkorea/aside-clean-logo/releases/latest/download/Aside-Clean-Logo-macOS.dmg)

## Windows

1. Install Aside first. Download and open **Aside-Clean-Logo-Windows-Setup.exe**.
2. Approve Windows administrator access, then press **Install**.

The helper follows the **Windows system appearance**, including custom mode's taskbar setting. It updates desktop, Start menu, pinned taskbar shortcuts and running Aside window icons. It starts at sign-in, backs up original shortcuts, and leaves the browser executable and profile untouched. Use the same administrator account that you normally use for Aside; entering credentials for a different account installs for that account.

Remove through **Settings → Apps → Aside Clean Logo** to restore the original icons. See [Windows details](windows/README.md) for diagnostics and build commands.

## macOS

1. Install Aside first. Download and open **Aside-Clean-Logo-macOS.dmg**.
2. Open **Aside Clean Logo**, select Aside.app if needed, and press **Install**.

The helper creates an **Aside Clean Logo Finder alias on your Desktop**, pointing to your installed Aside browser. This shortcut's icon switches with system appearance and the helper starts at sign-in. The original Aside.app and its code signature remain untouched. Open the utility again to uninstall and remove the shortcut.

**Dock limitation:** the original Aside application's Dock icon is not changed. The utility cannot change another running app's Dock tile through a supported API. It does not restart Aside or the Dock. This release is ad-hoc signed, not Apple-notarized; macOS may require approval through its normal security interface. See [macOS details](macos/README.txt).

## 한국어

- **윈도우:** 설치 파일 실행 → 관리자 승인 → **Install**. 다크 모드는 흰색, 밝은 모드는 검정 로고로 자동 전환합니다. 삭제하면 원래 아이콘을 복원합니다.
- **맥:** DMG 열기 → 앱 실행 → **Install**. 바탕화면에 Aside 실행 바로가기를 만들고 아이콘을 자동 전환합니다. 원본 앱과 Dock 아이콘은 변경하지 않습니다.
- 브라우저 본체·로그인·북마크 등 사용자 데이터는 변경하지 않습니다.

## Build and verification

- Windows: `powershell -NoProfile -File windows/build.ps1`
- macOS: `bash macos/build.sh` (universal Apple Silicon + Intel, macOS 12+)
- Shared assets: `python -m pip install Pillow==10.4.0` then `python -m unittest discover -s tests -v`
- Rebuild vector assets: `npm ci --ignore-scripts` then `python tools/build-assets.py`. The editable masters are `assets/black.svg` and `assets/white.svg`.

GitHub Actions builds native installers and runs disposable fixtures on both platforms. Release checksums are supplied as `SHA256SUMS.txt`. Native macOS fixture tests do not replace real Aside testing on a Mac.

Unofficial customization tool. Aside's name and logo belong to their respective owners; this project is not affiliated with Aside. Source code is MIT licensed; brand assets are excluded from that license.
