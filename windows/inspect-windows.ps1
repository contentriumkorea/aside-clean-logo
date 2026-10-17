param([Parameter(Mandatory=$true)][string]$AsideExecutable)
$ErrorActionPreference = 'Stop'
Add-Type -Path (Join-Path $PSScriptRoot 'Native.cs')
Add-Type -Path (Join-Path $PSScriptRoot 'WindowProperties.cs')
@([AsideCleanLogo.Native]::Windows($AsideExecutable) | ForEach-Object {
    [pscustomobject]@{
        Window = $_.ToInt64()
        AppId = [AsideCleanLogo.WindowProperties]::Get($_, 5)
        RelaunchCommand = [AsideCleanLogo.WindowProperties]::Get($_, 2)
        RelaunchIconResource = [AsideCleanLogo.WindowProperties]::Get($_, 3)
        RelaunchDisplayName = [AsideCleanLogo.WindowProperties]::Get($_, 4)
    }
}) | ConvertTo-Json -Depth 5
