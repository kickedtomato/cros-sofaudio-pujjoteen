<#
.SYNOPSIS
  Builds the CAB to submit for Microsoft attestation signing.

.DESCRIPTION
  Drivers that load with Secure Boot on (and without Test Mode) must be
  signed by Microsoft. For a non-WHQL driver that means attestation signing
  in the Windows Hardware Dev Center (Partner Center):

    1. Get an EV code-signing certificate and register a Hardware Dev Center
       account with it.
    2. Run build.cmd, then this script with the EV certificate's thumbprint:
         powershell -File build-tools\Make-AttestationCab.ps1 -Thumbprint <EV SHA1>
       It packs the four driver packages (INF + SYS + firmware, no catalogs;
       Microsoft generates those) into one CAB, one folder per driver, and
       signs the CAB with the EV certificate.
    3. Submit dist\attestation\cros-sofaudio-pujjoteen-drivers.cab as a new
       hardware submission ("Attestation" signing, Windows 10/11 x64).
    4. Download the signed result and run Import-AttestationSigned.ps1 on it,
       then package.cmd. The installer detects the Microsoft signature and
       works with Secure Boot on.

  Without -Thumbprint the CAB is created unsigned (for inspection only;
  Partner Center rejects unsigned CABs).
#>
param(
    [string]$Thumbprint,
    [string]$OutDir = (Join-Path $PSScriptRoot '..\dist\attestation')
)

$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..')
$release = Join-Path $root 'x64\Release'
$packages = @('SklHdaudBus', 'CsAudioIntcsof', 'rt5682', 'rt5682s', 'max98357a')

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$OutDir = (Resolve-Path $OutDir).Path
$cabName = 'cros-sofaudio-pujjoteen-drivers.cab'
$ddf = Join-Path $OutDir 'drivers.ddf'

$lines = @(
    '.OPTION EXPLICIT',
    '.Set CabinetFileCountThreshold=0',
    '.Set FolderFileCountThreshold=0',
    '.Set FolderSizeThreshold=0',
    '.Set MaxCabinetSize=0',
    '.Set MaxDiskFileCount=0',
    '.Set MaxDiskSize=0',
    '.Set CompressionType=MSZIP',
    '.Set Cabinet=on',
    '.Set Compress=on',
    ".Set CabinetNameTemplate=$cabName",
    ".Set DiskDirectoryTemplate=$OutDir"
)
foreach ($pkg in $packages) {
    $dir = Join-Path $release $pkg
    $files = @(Get-ChildItem -LiteralPath $dir -File | Where-Object { $_.Extension -in '.inf', '.sys', '.ri' })
    if (-not ($files | Where-Object Extension -eq '.inf') -or -not ($files | Where-Object Extension -eq '.sys')) {
        throw "$dir has no INF/SYS. Run build.cmd first."
    }
    $lines += ".Set DestinationDir=$pkg"
    foreach ($f in $files) { $lines += "`"$($f.FullName)`"" }
    # Symbols help Microsoft's crash analysis; include them when present.
    $pdb = Join-Path $release "$pkg.pdb"
    if (Test-Path -LiteralPath $pdb) { $lines += "`"$pdb`"" }
}
Set-Content -LiteralPath $ddf -Value $lines -Encoding ASCII

Push-Location $OutDir
try {
    & makecab.exe /F $ddf | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "makecab failed ($LASTEXITCODE)" }
} finally {
    Pop-Location
    Remove-Item -LiteralPath (Join-Path $OutDir 'setup.inf'), (Join-Path $OutDir 'setup.rpt') -ErrorAction SilentlyContinue
}
$cab = Join-Path $OutDir $cabName
Write-Host "Created $cab"

if ($Thumbprint) {
    $signtool = & (Join-Path $PSScriptRoot 'Find-SignTool.ps1')
    if (-not $signtool) { throw 'signtool.exe was not found in the installed Windows Driver Kit.' }
    & $signtool sign /v /s My /sha1 $Thumbprint /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 $cab
    if ($LASTEXITCODE -ne 0) { throw "signtool failed ($LASTEXITCODE)" }
    Write-Host 'CAB signed. Submit it in Partner Center (Hardware > Submit new hardware > Attestation).'
} else {
    Write-Warning 'CAB is unsigned. Pass -Thumbprint <EV certificate SHA1> to sign it for submission.'
}
