param([switch]$OneClick)
$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true') { throw 'Run this disposable install/uninstall test only on a clean GitHub Actions Windows runner.' }
if (!(New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'The runner must be elevated.' }
$installHome = Join-Path $env:ProgramFiles 'Aside Clean Logo'
if (Test-Path -LiteralPath $installHome) { throw 'An existing installation is present; refusing to change it.' }
$setup = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\dist\Aside-Clean-Logo-Windows-Setup.exe'))
$tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
$fixture = Join-Path $tempBase ('AsideCleanLogo-fixture-' + [Guid]::NewGuid().ToString('N'))
$desktop = [Environment]::GetFolderPath('DesktopDirectory')
$shortcut = Join-Path $desktop ('Aside Clean Logo fixture ' + [Guid]::NewGuid().ToString('N') + '.lnk')
$themeKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
$oldTheme = Get-ItemProperty -LiteralPath $themeKey -Name SystemUsesLightTheme -ErrorAction SilentlyContinue
$taskName = 'AsideCleanLogo-' + [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
function Invoke-Setup([string]$mode) {
    $executable = $setup
    $arguments = $mode
    if ($OneClick) {
        $action = if ($mode -eq '--uninstall') { 'Restore' } else { 'Apply' }
        $executable = Join-Path (Split-Path -Parent $setup) "Aside-Logo-$action.exe"
        $arguments = '--quiet'
    }
    $process = Start-Process -FilePath $executable -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        if (Test-Path -LiteralPath "$installHome\last-error.txt") { Get-Content -LiteralPath "$installHome\last-error.txt" }
        throw "Setup $mode failed with exit $($process.ExitCode)"
    }
}
function Assert-Color([string]$color) {
    $deadline = [DateTime]::UtcNow.AddSeconds(12)
    do {
        Start-Sleep -Milliseconds 500
        $state = Get-Content -LiteralPath "$installHome\status.json" -Raw | ConvertFrom-Json
        $linkIcon = (New-Object -ComObject WScript.Shell).CreateShortcut($shortcut).IconLocation
        if ($state.Ready -and $state.Color -eq $color -and $linkIcon -eq "$installHome\$color.ico,0") { return }
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "System theme did not apply $color to the actual shortcut"
}
try {
    New-Item -ItemType Directory -Path $fixture -Force | Out-Null
    New-Item -ItemType Directory -Path $desktop -Force | Out-Null
    $fakeAside = Join-Path $fixture 'Aside.exe'
    Copy-Item -LiteralPath "$env:WINDIR\System32\cmd.exe" -Destination $fakeAside
    $browserHash = (Get-FileHash -LiteralPath $fakeAside -Algorithm SHA256).Hash
    $shell = New-Object -ComObject WScript.Shell
    $link = $shell.CreateShortcut($shortcut)
    $link.TargetPath = $fakeAside
    $link.IconLocation = "$fakeAside,0"
    $link.Save()
    $original = (Get-FileHash -LiteralPath $shortcut -Algorithm SHA256).Hash
    if ($OneClick) {
        $legacy = Start-Process -FilePath $setup -ArgumentList '--install' -WindowStyle Hidden -Wait -PassThru
        if ($legacy.ExitCode -ne 0) { throw 'Could not prepare existing installer migration fixture' }
        if (!(Test-Path -LiteralPath 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\AsideCleanLogo')) { throw 'Migration fixture was not registered' }
    }
    Invoke-Setup '--install'
    if (!(Get-ScheduledTask -TaskName $taskName -ErrorAction Stop)) { throw 'Login task missing' }
    if ($OneClick -and (Test-Path -LiteralPath 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\AsideCleanLogo')) { throw 'One-click action unexpectedly registered an installed program' }
    New-Item -Path $themeKey -Force | Out-Null
    Set-ItemProperty -LiteralPath $themeKey -Name SystemUsesLightTheme -Value 0
    Assert-Color 'white'
    Set-ItemProperty -LiteralPath $themeKey -Name SystemUsesLightTheme -Value 1
    Assert-Color 'black'
    $backupHashes = @(Get-ChildItem -LiteralPath "$installHome\backup" -Filter '*.lnk' | Get-FileHash -Algorithm SHA256 | Select-Object -ExpandProperty Hash)
    Invoke-Setup '--install'
    $afterHashes = @(Get-ChildItem -LiteralPath "$installHome\backup" -Filter '*.lnk' | Get-FileHash -Algorithm SHA256 | Select-Object -ExpandProperty Hash)
    if (@(Compare-Object $backupHashes $afterHashes).Count -gt 0) { throw 'Reinstall changed first backups' }
    Invoke-Setup '--uninstall'
    if ((Get-FileHash -LiteralPath $shortcut -Algorithm SHA256).Hash -ne $original) { throw 'Uninstall did not restore the exact original shortcut' }
    if ((Get-FileHash -LiteralPath $fakeAside -Algorithm SHA256).Hash -ne $browserHash) { throw 'Browser binary was modified' }
    if (Test-Path -LiteralPath $installHome) { throw 'Product files remain after external uninstall' }
    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) { throw 'Login task remains after uninstall' }
    if ($OneClick) {
        Invoke-Setup '--install'
        if (Test-Path -LiteralPath 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\AsideCleanLogo') { throw 'Fresh one-click apply registered a program' }
        Invoke-Setup '--uninstall'
        Invoke-Setup '--uninstall'
        if ((Get-FileHash -LiteralPath $shortcut -Algorithm SHA256).Hash -ne $original -or (Test-Path -LiteralPath $installHome) -or (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue)) { throw 'Repeat apply/restore did not finish cleanly' }
        Write-Output 'PASS: one-click migration and fresh apply, no installed-program entry, theme/window helper, repeat apply, byte-exact restore, repeat restore and complete helper removal'
    } else { Write-Output 'PASS: real elevated install, scheduled startup, light/dark transitions, reinstall, byte-exact restore and clean uninstall' }
} finally {
    if ($oldTheme -and $oldTheme.PSObject.Properties['SystemUsesLightTheme']) { Set-ItemProperty -LiteralPath $themeKey -Name SystemUsesLightTheme -Value $oldTheme.SystemUsesLightTheme }
    elseif (Test-Path -LiteralPath $themeKey) { Remove-ItemProperty -LiteralPath $themeKey -Name SystemUsesLightTheme -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath "$installHome\install.json") { Start-Process -FilePath $setup -ArgumentList '--uninstall' -Wait | Out-Null }
    if (Test-Path -LiteralPath $shortcut) { Remove-Item -LiteralPath $shortcut }
    $resolvedFixture = [IO.Path]::GetFullPath($fixture)
    if (!$resolvedFixture.StartsWith($tempBase,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolvedFixture) -notlike 'AsideCleanLogo-fixture-*') { throw 'Refusing unsafe fixture cleanup' }
    if (Test-Path -LiteralPath $resolvedFixture) { Remove-Item -LiteralPath $resolvedFixture -Recurse -Force }
}
