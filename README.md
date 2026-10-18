# Aside Clean Logo

Windows용 Aside 로고 원클릭 변경·복원 도구입니다. 설치 화면 없이 실행하면 적용됩니다.

![Black and white icon previews](assets/preview.png)

**[로고 변경 — Aside-Logo-Apply.exe](https://github.com/contentriumkorea/aside-clean-logo/releases/latest/download/Aside-Logo-Apply.exe)**

**[원래 로고 복원 — Aside-Logo-Restore.exe](https://github.com/contentriumkorea/aside-clean-logo/releases/latest/download/Aside-Logo-Restore.exe)**

1. Aside가 설치된 Windows PC에서 **로고 변경** 파일을 실행하고 관리자 승인을 합니다.
2. 바탕화면·시작 메뉴·고정 작업표시줄·실행 중인 Aside 창의 아이콘을 변경합니다. 다크 모드에는 화이트, 밝은 모드에는 블랙을 사용합니다.
3. 되돌리려면 **원래 로고 복원** 파일을 실행합니다. 원래 아이콘을 복원하고 도우미·자동 실행·아이콘 파일을 제거합니다.

설치 마법사, 설치 버튼, 완료 확인창, 앱 목록 등록은 없습니다. 로고가 Aside 재실행과 Windows 로그인 후에도 유지되고 테마에 맞게 전환되도록 작은 백그라운드 도우미와 로그인 작업은 사용합니다. 아이콘 파일과 원본 백업은 `%ProgramFiles%\Aside Clean Logo`에 보관하므로 다운로드한 EXE를 옮겨도 아이콘 경로가 깨지지 않습니다. 기존 Setup 버전을 사용 중이어도 변경 파일을 바로 실행할 수 있으며 최초 원본 백업을 유지합니다.

Aside 실행 파일과 로그인·북마크·방문 기록은 변경하지 않습니다. 평소 Aside를 사용하는 동일한 관리자 계정으로 실행하세요. 다른 관리자 계정의 자격 증명을 입력하면 그 계정에 적용됩니다.

맥 버전은 사용자 요청에 따라 배포를 취소했습니다. 현재 배포는 Windows 전용입니다.

The two Windows executables apply and restore the approved logo without a setup wizard or an Installed Apps entry. A protected background helper keeps running taskbar icons and light/dark switching consistent; Restore removes it. The original browser binary and profile are untouched. `SHA256SUMS.txt` verifies both downloads.

The artwork preserves the original vector paths from [Aside's official website](https://aside.com/). The circular and curved lines use the approved 0.28-unit inset; the central sparkle remains unchanged. No AI redrawing is used. The black and white assets have identical geometry and less than 2% transparent margin per side.

## Build and verification

- Windows: `powershell -NoProfile -File windows/build.ps1`
- Asset checks: `python -m unittest discover -s tests -v`
- Rebuild artwork: `npm ci --ignore-scripts` then `python tools/build-assets.py`
- CI checks fresh apply, migration from the former Setup, theme switching, repeat apply, original shortcut restoration and complete removal on a disposable Windows runner.

See [Windows technical details](windows/README.md). Earlier macOS investigations are retained as research and are not distributed.

Unofficial customization tool. Aside's name and logo belong to their respective owners. Source code is MIT licensed; brand assets are excluded from that license.
