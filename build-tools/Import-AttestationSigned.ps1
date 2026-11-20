<#
.SYNOPSIS
  Puts Microsoft attestation-signed drivers into the build output.

.DESCRIPTION
  Takes the signed package downloaded from Partner Center (a .zip, or the
  folder it was extracted to; it holds one folder per driver, as submitted
  by Make-AttestationCab.ps1), checks that every catalog is signed by
  "Microsoft Windows Hardware Compatibility Publisher", and copies the
  signed .sys/.cat/.inf files over x64\Release\<driver>\. It writes
  x64\Release\MICROSOFT_SIGNED so package.cmd verifies Microsoft signatures
  instead of the local test certificate.

  Then run package.cmd. Rebuilding with build.cmd overwrites the signed
  files with test-signed ones again.
#>
param([Parameter(Mandatory = $true)][string]$SignedPackage)

$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..')
$release = Join-Path $root 'x64\Release'
$packages = @('SklHdaudBus', 'CsAudioIntcsof', 'rt5682', 'rt5682s', 'max98357a')
$msPublisher = 'Microsoft Windows Hardware Compatibility Publisher'

$source = (Resolve-Path $SignedPackage).Path
if ((Get-Item $source).PSIsContainer -eq $false) {
    $extract = Join-Path ([IO.Path]::GetTempPath()) ("cros-sofaudio-signed-" + [guid]::NewGuid())
    Expand-Archive -LiteralPath $source -DestinationPath $extract
    $source = $extract
}

foreach ($pkg in $packages) {
    $dir = Get-ChildItem -LiteralPath $source -Directory -Recurse | Where-Object Name -eq $pkg | Select-Object -First 1
    if (-not $dir) { throw "The signed package has no '$pkg' folder." }
    $cat = Get-ChildItem -LiteralPath $dir.FullName -Filter *.cat | Select-Object -First 1
    if (-not $cat) { throw "$pkg has no catalog in the signed package." }
    $sig = Get-AuthenticodeSignature -LiteralPath $cat.FullName
    if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch [regex]::Escape($msPublisher)) {
        throw "$pkg catalog is not Microsoft-signed (status $($sig.Status), signer $($sig.SignerCertificate.Subject))."
    }
    $dest = Join-Path $release $pkg
    Get-ChildItem -LiteralPath $dest -Filter *.cat | Remove-Item -Force
    Get-ChildItem -LiteralPath $dir.FullName -File | Where-Object { $_.Extension -in '.sys', '.cat', '.inf', '.ri' } |
        Copy-Item -Destination $dest -Force
    Remove-Item -LiteralPath (Join-Path $dest 'ChromebookAudio.cer') -ErrorAction SilentlyContinue
    Write-Host "  $pkg: Microsoft-signed ($($cat.Name))"
}

Set-Content -LiteralPath (Join-Path $release 'MICROSOFT_SIGNED') -Value (Get-Date -Format o) -Encoding ASCII
Write-Host 'Done. Run package.cmd to build the Secure Boot compatible setup.'
