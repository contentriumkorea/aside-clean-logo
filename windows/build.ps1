param([string]$OutputDirectory = (Join-Path $PSScriptRoot '..\dist'))
$ErrorActionPreference = 'Stop'
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (!(Test-Path -LiteralPath $compiler)) { throw '.NET Framework 4.8 C# compiler is required.' }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$output = [IO.Path]::GetFullPath($OutputDirectory)
Push-Location $PSScriptRoot
try {
    $references = @('/r:Microsoft.CSharp.dll', '/r:System.Xml.Linq.dll', '/r:System.Web.Extensions.dll', '/r:System.Drawing.dll', '/r:System.Windows.Forms.dll')
    $resources = @('/resource:..\assets\black.ico,black.ico', '/resource:..\assets\white.ico,white.ico')
    & $compiler /nologo /target:exe /platform:x64 @references @resources /main:TestMain /out:Tests.exe Core.cs CoreTests.cs Native.cs WindowProperties.cs WindowStore.cs Program.cs TestMain.cs
    if ($LASTEXITCODE -ne 0) { throw 'Test build failed.' }
    & .\Tests.exe
    if ($LASTEXITCODE -ne 0) { throw 'Disposable shortcut tests failed.' }
    $artifact = Join-Path $output 'Aside-Clean-Logo-Windows-Setup.exe'
    & $compiler /nologo /target:winexe /platform:x64 /optimize+ @references @resources /win32manifest:app.manifest /win32icon:..\assets\black.ico "/out:$artifact" Core.cs CoreTests.cs Native.cs WindowProperties.cs WindowStore.cs Program.cs
    if ($LASTEXITCODE -ne 0) { throw 'Installer build failed.' }
    Write-Output "Built $artifact"
    foreach ($action in @('Apply', 'Restore')) {
        $oneClick = Join-Path $output "Aside-Logo-$action.exe"
        $defines = @()
        if ($action -eq 'Restore') { $defines = @('/define:RESTORE_LOGO') }
        & $compiler /nologo /codepage:65001 /target:winexe /platform:x64 /optimize+ @references @resources @defines /main:AsideCleanLogo.OneClickMain /win32manifest:app.manifest /win32icon:..\assets\black.ico "/out:$oneClick" Core.cs Native.cs WindowProperties.cs WindowStore.cs Program.cs CoreTests.cs OneClickMain.cs
        if ($LASTEXITCODE -ne 0) { throw "One-click $action build failed." }
        Write-Output "Built $oneClick"
    }
} finally {
    if (Test-Path -LiteralPath .\Tests.exe) { Remove-Item -LiteralPath .\Tests.exe }
    Pop-Location
}
