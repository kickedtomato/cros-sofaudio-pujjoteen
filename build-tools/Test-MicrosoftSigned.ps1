param([Parameter(Mandatory = $true)][string]$Paths)

# Verifies that every listed driver file carries a valid signature from
# "Microsoft Windows Hardware Compatibility Publisher" (attestation/WHQL).
# .sys files are checked through the catalog of their package.
$ErrorActionPreference = 'Stop'
$msPublisher = 'Microsoft Windows Hardware Compatibility Publisher'

foreach ($path in ($Paths -split ';')) {
    if ([string]::IsNullOrWhiteSpace($path)) { continue }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing: $path" }
    $sig = Get-AuthenticodeSignature -LiteralPath $path
    if ($sig.Status -ne 'Valid') { throw "Not validly signed: $path ($($sig.Status))" }
    if ($path -match '\.cat$' -and $sig.SignerCertificate.Subject -notmatch [regex]::Escape($msPublisher)) {
        throw "Catalog not signed by Microsoft: $path ($($sig.SignerCertificate.Subject))"
    }
    Write-Host "  verified $path ($($sig.SignerCertificate.Subject))"
}
