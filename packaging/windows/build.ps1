<#
.SYNOPSIS
  Builds Suvi Share for Windows and packages it into an Inno Setup installer.

.DESCRIPTION
  Reads the version from app/pubspec.yaml, builds the release binary, then
  compiles packaging/windows/suvi_share.iss. The finished setup .exe lands in
  packaging/windows/output/.

.PARAMETER SkipBuild
  Package whatever is already in app/build/windows/x64/runner/Release.

.PARAMETER FlutterPath
  Optional path to flutter.bat when Flutter is not on PATH and FLUTTER_ROOT is
  not set.

.EXAMPLE
  .\packaging\windows\build.ps1
#>
[CmdletBinding()]
param(
    [switch]$SkipBuild,
    [string]$FlutterPath
)

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$appDir = Join-Path $repoRoot 'app'
$issFile = Join-Path $PSScriptRoot 'suvi_share.iss'
$releaseDir = Join-Path $appDir 'build\windows\x64\runner\Release'
$symbolDir = Join-Path $appDir 'build\symbols\windows'

# --- Flutter -----------------------------------------------------------------
if (-not $FlutterPath) {
    $flutterCommand = Get-Command 'flutter.bat' -ErrorAction SilentlyContinue
    if (-not $flutterCommand) {
        $flutterCommand = Get-Command 'flutter' -ErrorAction SilentlyContinue
    }
    if ($flutterCommand) {
        $FlutterPath = $flutterCommand.Source
    } elseif ($env:FLUTTER_ROOT) {
        $FlutterPath = Join-Path $env:FLUTTER_ROOT 'bin\flutter.bat'
    }
}
if (-not $SkipBuild -and (-not $FlutterPath -or -not (Test-Path $FlutterPath))) {
    throw 'Flutter not found. Add it to PATH, set FLUTTER_ROOT, or pass -FlutterPath.'
}

# --- version -----------------------------------------------------------------
$pubspec = Get-Content (Join-Path $appDir 'pubspec.yaml')
$versionLine = $pubspec | Where-Object { $_ -match '^version:' } | Select-Object -First 1
if (-not $versionLine) { throw 'Could not read version from pubspec.yaml' }
# "version: 0.1.0+1" -> "0.1.0"
$version = ($versionLine -replace '^version:\s*', '').Split('+')[0].Trim()
Write-Host "Suvi Share $version" -ForegroundColor Cyan

# --- locate ISCC -------------------------------------------------------------
# @() keeps this an array even when a single path matches — otherwise
# PowerShell unwraps it to a string and [0] yields its first character.
$isccCandidates = @(
    @(
        (Get-Command 'iscc.exe' -ErrorAction SilentlyContinue).Source,
        "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
        "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
    ) | Where-Object { $_ -and (Test-Path $_) }
)

if ($isccCandidates.Count -eq 0) {
    throw "Inno Setup 6 not found. Install it with: winget install JRSoftware.InnoSetup"
}
$iscc = $isccCandidates[0]
Write-Host "Using $iscc"

# --- build -------------------------------------------------------------------
if (-not $SkipBuild) {
    Write-Host "`nBuilding Windows release..." -ForegroundColor Cyan
    Push-Location $appDir
    try {
        & $FlutterPath build windows --release --obfuscate "--split-debug-info=$symbolDir"
        if ($LASTEXITCODE -ne 0) { throw "flutter build windows failed ($LASTEXITCODE)" }
    } finally {
        Pop-Location
    }
}

if (-not (Test-Path (Join-Path $releaseDir 'suvi_share.exe'))) {
    throw "Release binary not found in $releaseDir. Run without -SkipBuild."
}

# --- package -----------------------------------------------------------------
Write-Host "`nCompiling installer..." -ForegroundColor Cyan
& $iscc "/DAppVersion=$version" $issFile
if ($LASTEXITCODE -ne 0) { throw "ISCC failed ($LASTEXITCODE)" }

$setup = Get-ChildItem (Join-Path $PSScriptRoot 'output') -Filter '*.exe' |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
Write-Host "`nInstaller: $($setup.FullName)" -ForegroundColor Green
Write-Host ("Size:      {0:N1} MB" -f ($setup.Length / 1MB))
Write-Host ("SHA-256:   {0}" -f (Get-FileHash $setup.FullName -Algorithm SHA256).Hash)
