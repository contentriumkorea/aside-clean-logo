# Aside Clean Logo

Clean, transparent black/white icons for the Aside desktop browser. **Dark appearance → white. Light appearance → black.** The central sparkle stays bold while the circular and curved lines are thinner.

The artwork uses the original vector paths from [Aside's official website](https://aside.com/), with no AI redrawing. The original Bezier coordinates and outer silhouette are retained. Internal boundaries are inset by 0.28 vector units, and the central sparkle's protected pixels are copied exactly from the original rendering. These invariants are tested. The icon fills its frame with less than 2% transparent margin on each side while preserving its original proportions.

![Black and white icon previews](assets/preview.png)

[![Install for Windows](https://img.shields.io/badge/Windows-Download_Setup-0078D4?style=for-the-badge&logo=windows)](https://github.com/contentriumkorea/aside-clean-logo/releases/latest/download/Aside-Clean-Logo-Windows-Setup.exe)

**macOS distribution is on hold.** A working installer for the real running Dock icon is not available yet.

## Windows

1. Install Aside first. Download and open **Aside-Clean-Logo-Windows-Setup.exe**.
2. Approve Windows administrator access, then press **Install**.

The helper follows the **Windows system appearance**, including custom mode's taskbar setting. It updates desktop, Start menu, pinned taskbar shortcuts and running Aside window icons. It starts at sign-in, backs up original shortcuts, and leaves the browser executable and profile untouched. Use the same administrator account that you normally use for Aside; entering credentials for a different account installs for that account.

Remove through **Settings → Apps → Aside Clean Logo** to restore the original icons. See [Windows details](windows/README.md) for diagnostics and build commands.

## macOS

The real running Aside Dock tile is required. Finder aliases and app metadata alone do not reliably update that tile, so the macOS installer is not included in releases. Source and CI artifacts under `macos/` are development experiments, not a supported installation.

An isolated test proved that Chromium's `Browser.setDockTile` can change the running tile without replacing signed browser resources. The production route through Aside's existing authenticated bridge is blocked by macOS Keychain entitlement error `-34018` when its signer runs outside Aside. Administrator approval does not resolve that entitlement boundary. A supported first-party integration is needed before macOS installation can be offered.

## 한국어

- **윈도우:** 설치 파일 실행 → 관리자 승인 → **Install**. 다크 모드는 흰색, 밝은 모드는 검정 로고로 자동 전환합니다. 삭제하면 원래 아이콘을 복원합니다.
- **맥:** 실행 중인 Dock 아이콘 변경에 필요한 Aside 인증 권한 문제로 배포를 보류했습니다. 현재 Mac 개발 빌드는 설치용으로 제공하지 않습니다.
- 브라우저 본체·로그인·북마크 등 사용자 데이터는 변경하지 않습니다.

## Build and verification

- Windows: `powershell -NoProfile -File windows/build.ps1`
- macOS development only: `bash macos/build.sh` (universal Apple Silicon + Intel, macOS 12+)
- Shared assets: `python -m pip install Pillow==10.4.0` then `python -m unittest discover -s tests -v`
- Rebuild vector assets: `npm ci --ignore-scripts` then `python tools/build-assets.py`. The editable masters are `assets/black.svg` and `assets/white.svg`.

GitHub Actions builds Windows installers and macOS development artifacts and runs disposable fixtures on both platforms. Published releases contain the verified Windows installer and `SHA256SUMS.txt`. Native macOS fixture tests do not establish support for the running Aside Dock tile.

Unofficial customization tool. Aside's name and logo belong to their respective owners; this project is not affiliated with Aside. Source code is MIT licensed; brand assets are excluded from that license.
