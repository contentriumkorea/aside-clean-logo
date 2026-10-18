<p align="center">
  <img src="assets/cover.png" alt="Aside Clean Logo — Windows용 원클릭 로고 변경·복원" width="100%">
</p>

<h1 align="center">Aside Clean Logo</h1>

<p align="center">
  <strong>어사이드 아이콘을 더 깔끔하게. 변경도, 원복도 한 번 실행으로.</strong><br>
  Windows 바탕화면과 작업표시줄에 깔끔한 로고를 적용하고, 언제든 원래 로고로 돌아가세요.
</p>

<p align="center">
  <a href="https://github.com/contentriumkorea/aside-clean-logo/releases/latest"><img src="https://img.shields.io/github/v/release/contentriumkorea/aside-clean-logo?style=flat-square&amp;label=Release&amp;color=1768bd" alt="Latest release"></a>
  <a href="#적용-범위와-제한"><img src="https://img.shields.io/badge/Windows-x64-1768bd?style=flat-square" alt="Windows 64비트 지원"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/Code-MIT-536877?style=flat-square" alt="소스 코드 MIT 라이선스"></a>
</p>

<p align="center">
  <a href="#빠르게-시작하기">적용하기</a> ·
  <a href="https://github.com/contentriumkorea/aside-clean-logo/releases/latest">다운로드</a> ·
  <a href="#사용-모습">사용 모습</a> ·
  <a href="docs/usage.md">상세 안내</a>
</p>

---

## 빠르게 시작하기

**Windows 64비트 · Aside 설치 필요 · .NET Framework 4.8 · 관리자 승인 필요**

<p align="center">
  <a href="https://github.com/contentriumkorea/aside-clean-logo/releases/latest/download/Aside-Logo-Apply.exe"><img src="assets/download-apply.png" alt="로고 변경 다운로드 — Aside-Logo-Apply.exe" width="270"></a>
  <a href="https://github.com/contentriumkorea/aside-clean-logo/releases/latest/download/Aside-Logo-Restore.exe"><img src="assets/download-restore.png" alt="원래 로고로 복원 — Aside-Logo-Restore.exe" width="270"></a>
</p>

두 파일을 받아 두고 **로고 변경** 파일을 실행하세요. Windows 관리자 승인 후 설치 마법사와 완료 확인창 없이 적용됩니다. 되돌릴 때는 **원래 로고로 복원** 파일을 실행하면 됩니다.

[상세 적용 및 복원 안내 →](docs/usage.md)

## 바꾸기부터 원복까지, 간단하게

| 01 · 원클릭 변경 | 02 · 테마 자동 전환 | 03 · 원래 로고 복원 |
| :--- | :--- | :--- |
| **바탕화면과 작업표시줄을 깔끔하게** | **어두울 땐 화이트, 밝을 땐 블랙** | **필요할 때 처음 모습으로** |
| 바탕화면·시작 메뉴·고정 작업표시줄·실행 중인 Aside 창의 아이콘을 변경합니다. | Windows 모드에 맞춰 로고 색상을 전환하고, Aside 재실행 후에도 유지합니다. | 최초 원본 백업으로 복원하고 이 도구의 도우미와 자동 실행을 제거합니다. |

## 사용 모습

<p align="center">
  <img src="assets/taskbar-preview.png" alt="어두운 작업표시줄에 적용한 화이트 Aside 로고의 디자인 미리보기" width="880">
</p>

**익숙한 Aside 심벌을 유지하면서 흰 테두리와 여백을 정리했습니다.**

고해상도로 재구성한 디자인 미리보기입니다. 실제 화면 캡처가 아니며, 크기와 배경은 Windows 설정에 따라 달라집니다.

<details>
<summary><strong>추가 예시 보기</strong></summary>

<p align="center">
  <img src="assets/preview.png" alt="밝은 배경의 블랙 로고와 어두운 배경의 화이트 로고 비교" width="880">
</p>

밝은 Windows 모드에는 블랙, 다크 모드에는 화이트 로고를 사용합니다. 시스템의 사용자 지정 모드에서는 작업표시줄에 적용되는 Windows 모드를 따릅니다.

</details>

## 다운로드와 적용 방식

| 파일 | 사용 방법 |
| :--- | :--- |
| [로고 변경 EXE](https://github.com/contentriumkorea/aside-clean-logo/releases/latest/download/Aside-Logo-Apply.exe) | 실행하고 관리자 승인하면 새 로고를 적용합니다. 기존 Setup 사용자의 최초 원본 백업도 유지합니다. |
| [원래 로고 복원 EXE](https://github.com/contentriumkorea/aside-clean-logo/releases/latest/download/Aside-Logo-Restore.exe) | 원래 아이콘으로 복원하고 도우미·로그인 작업·아이콘 파일을 제거합니다. |
| [파일 무결성 정보](https://github.com/contentriumkorea/aside-clean-logo/releases/latest/download/SHA256SUMS.txt) | 다운로드 파일의 SHA-256을 비교할 때 사용합니다. |

설치 마법사를 사용하는 대신 변경·복원 파일 두 개로 제공합니다. GitHub의 Source code ZIP은 실행 파일 묶음이 아닙니다.

## 이렇게 사용하세요

```text
변경: Aside-Logo-Apply.exe
실행 → 관리자 승인 → 새 로고 적용

원복: Aside-Logo-Restore.exe
실행 → 관리자 승인 → 원본 복원
```

## 적용 범위와 제한

- **Windows 전용입니다.** 바탕화면·시작 메뉴·고정 작업표시줄과 실행 중인 Aside 창에 적용합니다.
- **작은 도우미가 백그라운드와 로그인 시 동작합니다.** 테마 전환과 Aside 재실행 후 로고를 유지하며, 원복하면 함께 제거됩니다. 앱 목록에는 별도 프로그램을 등록하지 않습니다.
- **평소 Aside를 사용하는 동일한 관리자 계정으로 실행하세요.** 다른 관리자 계정의 자격 증명을 입력하면 그 계정에 적용됩니다.
- **Windows 아이콘 캐시에 따라 표시가 잠시 늦어질 수 있습니다.** 도구는 Explorer나 Aside를 강제로 종료하지 않습니다.
- Aside의 원래 심벌 형태를 유지하며, 브라우저 본체와 로그인·북마크·방문 기록은 변경하지 않습니다.

<details>
<summary><strong>상세 안내와 검증 범위</strong></summary>

- [사용법·기존 Setup 전환·문제 해결](docs/usage.md)
- [로고 제작 기준](docs/artwork.md)
- [개발·검증 문서](windows/README.md)
- [Windows 적용·복원 검증 기록](https://github.com/contentriumkorea/aside-clean-logo/actions/runs/39117637813)

Windows 시험 환경에서 기존 Setup 전환, 새 적용, 다크·라이트 전환, 반복 적용, 최초 원본 바로가기 복원, 반복 복원과 도우미 제거를 확인했습니다. 이는 모든 사용자 설정에서 같은 화면 표시를 보장한다는 의미는 아닙니다.

</details>

<details>
<summary><strong>English overview</strong></summary>

Aside Clean Logo is an unofficial Windows tool for applying clean black and white Aside icons. Run Apply to change the desktop, Start menu and taskbar icons; run Restore to return to the original icons and remove the helper.

A small background helper keeps the icons consistent after browser relaunch and Windows theme changes. Windows x64, an existing Aside installation, .NET Framework 4.8 and administrator approval are required. The browser executable and profile data are preserved.

</details>

---

<p align="center">
  <strong>콘텐츠리움 · Contentrium</strong><br>
  <a href="LICENSE">Code: MIT</a> ·
  <a href="https://github.com/contentriumkorea/aside-clean-logo/releases/latest">Latest release</a>
</p>

<sub>콘텐츠리움이 제작한 비공식 사용자화 도구이며 Aside와 제휴한 제품이 아닙니다. 표시된 브랜드의 이름과 로고는 각 권리자에게 있습니다. MIT 라이선스는 소스 코드에만 적용됩니다.</sub>

<p align="center">
  <a href="https://contentrium.com/"><img src="assets/contentrium-home.svg" alt="콘텐츠리움 홈페이지 바로가기" width="260" height="52"></a>
</p>
