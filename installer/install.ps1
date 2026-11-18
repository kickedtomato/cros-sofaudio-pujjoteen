# install.ps1 - Chromebook Audio for Windows (pujjoteen: Intel Alder Lake-N + MAX98360A + ALC5682I-VD)
#
#   -Force     install even if the hardware check fails (not recommended)
#
param([switch]$Force)

$ErrorActionPreference = 'Stop'
$here    = $PSScriptRoot
$version = (Get-Content (Join-Path $here 'VERSION.txt') -ErrorAction SilentlyContinue | Select-Object -First 1)
$regRoot = 'HKLM:\SOFTWARE\CrosSofAudio'
$progDir = Join-Path $env:ProgramFiles 'CrosSofAudio'
$svcName = 'csaudioswitcher'

function Step($m) { Write-Host "`n=== $m ===" -ForegroundColor Cyan }
function Fail($m) { Write-Host "`n$m" -ForegroundColor Red; exit 1 }

function Normalize-Thumbprint([string]$value) {
    return ($value -replace '[^0-9A-Fa-f]', '').ToUpperInvariant()
}

function Test-CodeSigningEku($certificate) {
    foreach ($extension in $certificate.Extensions) {
        if ($extension.Oid.Value -ne '2.5.29.37') { continue }
        foreach ($usage in $extension.EnhancedKeyUsages) {
            if ($usage.Value -eq '1.3.6.1.5.5.7.3.3') { return $true }
        }
    }
    return $false
}

function Add-CertificateToStore([string]$store, [string]$path) {
    $output = & certutil.exe -addstore -f $store $path 2>&1
    if ($LASTEXITCODE -ne 0) {
        $output | Out-Host
        Fail "Could not import the driver certificate into LocalMachine\$store (code $LASTEXITCODE)."
    }
}

function Test-PackageSignature([string]$path, [string]$expectedThumbprint) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Fail "The signed package file is missing: $path"
    }

    $signature = Get-AuthenticodeSignature -LiteralPath $path
    if (-not $signature.SignerCertificate) {
        Fail "The package file is not signed: $path (status: $($signature.Status))"
    }

    $actualThumbprint = Normalize-Thumbprint $signature.SignerCertificate.Thumbprint
    if ($actualThumbprint -ne $expectedThumbprint) {
        Fail ("The package contains mixed signing certificates.`n" +
              "Expected: $expectedThumbprint`nFound:    $actualThumbprint`nFile:     $path")
    }

    if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
        Fail ("Windows could not validate the signature on:`n$path`n" +
              "Status: $($signature.Status) - $($signature.StatusMessage)")
    }
}

Write-Host "Chromebook Audio for Windows  $version" -ForegroundColor Green

# ------------------------------------------------------------------ hardware
Step 'Checking hardware'
$present = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue
$dsp   = $present | Where-Object { $_.InstanceId -match '^PCI\\VEN_8086&DEV_54C8&' }
$codec = $present | Where-Object { $_.InstanceId -match '^ACPI\\10EC5682\\' }
$amp   = $present | Where-Object { $_.InstanceId -match '^ACPI\\MX98360A\\' }

Write-Host ("  Intel Alder Lake-N audio DSP : {0}" -f $(if ($dsp) { 'found' } else { 'NOT FOUND' }))
Write-Host ("  ALC5682I headset codec       : {0}" -f $(if ($codec) { 'found' } else { 'NOT FOUND' }))
Write-Host ("  MAX98360A speaker amp        : {0}" -f $(if ($amp) { 'found' } else { 'NOT FOUND' }))

$ok = $dsp -and $codec -and $amp
if (-not $ok) {
    if (-not $Force) {
        Fail ("This package is for the Google pujjoteen Chromebook (Intel Alder Lake-N with an`n" +
              "ALC5682I headset codec and a MAX98360A speaker amp). This laptop does not have`n" +
              "that combination, so nothing was installed.")
    }
    Write-Warning 'Hardware check failed - continuing because -Force was given.'
}

# ------------------------------------------------------------------ test signing
Step 'Checking driver signing mode'
$bootOptions = Get-ItemPropertyValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control' `
                                     -Name 'SystemStartOptions' -ErrorAction SilentlyContinue
$testSigningActive = (($bootOptions -split '\s+') -contains 'TESTSIGNING')
if (-not $testSigningActive) {
    Write-Host 'These drivers are test-signed, so Windows must be in Test Mode.' -ForegroundColor Yellow
    $a = Read-Host 'Turn Test Mode on now? (Y/N)'
    if ($a -match '^[Yy]') {
        bcdedit /set testsigning on | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Fail ("Could not turn on Test Mode. Secure Boot is probably enabled - turn it off in the`n" +
                  "firmware setup (UEFI) and run this installer again.")
        }
        Fail 'Test Mode is now on. REBOOT, then run Install.cmd again.'
    }
    Fail 'Installation stopped: Test Mode is required.'
}
Write-Host '  Test Mode is on.'

# ------------------------------------------------------------------ certificate
Step 'Trusting the driver certificate'
$cer = Join-Path $here 'ChromebookAudio.cer'
if (-not (Test-Path -LiteralPath $cer -PathType Leaf)) {
    Fail "The package signing certificate is missing: $cer"
}

$certificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($cer)
$certificateThumbprint = Normalize-Thumbprint $certificate.Thumbprint
if ((Get-Date) -lt $certificate.NotBefore -or (Get-Date) -gt $certificate.NotAfter) {
    Fail "The package signing certificate is not currently valid ($($certificate.NotBefore) through $($certificate.NotAfter))."
}
if (-not (Test-CodeSigningEku $certificate)) {
    Fail 'The package certificate is not valid for code signing.'
}

# A self-signed test certificate must be trusted as both its own root and its publisher.
if ($certificate.Subject -eq $certificate.Issuer) {
    Add-CertificateToStore 'Root' $cer
}
Add-CertificateToStore 'TrustedPublisher' $cer

$publisher = Get-Item -LiteralPath "Cert:\LocalMachine\TrustedPublisher\$certificateThumbprint" -ErrorAction SilentlyContinue
if (-not $publisher) {
    Fail "The driver certificate was not found in LocalMachine\TrustedPublisher after import."
}
if ($certificate.Subject -eq $certificate.Issuer) {
    $root = Get-Item -LiteralPath "Cert:\LocalMachine\Root\$certificateThumbprint" -ErrorAction SilentlyContinue
    if (-not $root) { Fail 'The self-signed driver certificate was not found in LocalMachine\Root after import.' }
}

foreach ($signedFile in @(
    'Drivers\SklHdaudBus\SklHdaudBus.sys',
    'Drivers\SklHdaudBus\sklhdaudbus.cat',
    'Drivers\CsAudioIntcsof\CsAudioIntcsof.sys',
    'Drivers\CsAudioIntcsof\csaudiointcsof.cat',
    'Drivers\rt5682\rt5682.sys',
    'Drivers\rt5682\rt5682.cat',
    'Drivers\max98357a\max98357a.sys',
    'Drivers\max98357a\max98357a.cat',
    'Switcher\csaudioendpointswitcher.exe'
)) {
    Test-PackageSignature (Join-Path $here $signedFile) $certificateThumbprint
}
Write-Host "  trusted and verified ($certificateThumbprint)"

# ------------------------------------------------------------------ code integrity policy
# These open-source drivers are test-signed and can otherwise be rejected by
# the Microsoft vulnerable-driver blocklist before PnP gets a chance to load
# them. Do this only after the complete package has passed signature checks.
Step 'Configuring Windows driver compatibility'
$ciConfigPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Config'
New-Item -Path $ciConfigPath -Force | Out-Null
New-Item -Path $regRoot -Force | Out-Null

$backupCaptured = (Get-ItemProperty -Path $regRoot -Name 'BlocklistBackupCaptured' -ErrorAction SilentlyContinue).BlocklistBackupCaptured
if ($backupCaptured -ne 1) {
    $ciConfigKey = Get-Item -Path $ciConfigPath
    $previousBlocklistValue = $ciConfigKey.GetValue('VulnerableDriverBlocklistEnable', $null)
    $blocklistValueWasPresent = if ($null -eq $previousBlocklistValue) { 0 } else { 1 }
    if ($null -eq $previousBlocklistValue) { $previousBlocklistValue = 1 }

    New-ItemProperty -Path $regRoot -Name 'BlocklistValueWasPresent' -PropertyType DWord -Value $blocklistValueWasPresent -Force | Out-Null
    New-ItemProperty -Path $regRoot -Name 'PreviousVulnerableDriverBlocklistEnable' -PropertyType DWord -Value ([int]$previousBlocklistValue) -Force | Out-Null
    New-ItemProperty -Path $regRoot -Name 'BlocklistBackupCaptured' -PropertyType DWord -Value 1 -Force | Out-Null
}

New-ItemProperty -Path $ciConfigPath `
                 -Name 'VulnerableDriverBlocklistEnable' `
                 -PropertyType DWord `
                 -Value 0 `
                 -Force | Out-Null
$blocklistValue = Get-ItemPropertyValue -Path $ciConfigPath -Name 'VulnerableDriverBlocklistEnable'
if ($blocklistValue -ne 0) {
    Fail 'Windows did not accept the VulnerableDriverBlocklistEnable=0 compatibility setting.'
}
Write-Warning 'Microsoft Vulnerable Driver Blocklist disabled for these test-signed drivers. A reboot is required.'

# Keep an older switcher from reacting to PnP endpoint churn while its driver
# packages and executable are being replaced.
$existingSwitcher = Get-Service -Name $svcName -ErrorAction SilentlyContinue
if ($existingSwitcher -and $existingSwitcher.Status -ne 'Stopped') {
    Stop-Service $svcName -Force
    $existingSwitcher.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(15))
}

function Install-Inf($rel) {
    $path = Join-Path $here $rel
    if (-not (Test-Path $path)) { Fail "The package is incomplete; missing $rel" }
    Write-Host "  $rel"
    $out = pnputil /add-driver $path /install
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 3010 -and $LASTEXITCODE -ne 259) {
        $out | Out-Host
        Fail "pnputil failed on $rel (code $LASTEXITCODE)"
    }
}

function Remove-SupersededDriverPackages([string[]]$originalNames) {
    # pnputil intentionally keeps older packages in Driver Store. Restrict
    # cleanup to this project's original INF names and providers, retain the
    # newest package for each INF, and remove only the superseded oem*.inf
    # packages after the replacement drivers have been installed.
    $projectProviders = @(
        'The Scape Network',
        'Chromebook Audio Open Source Project',
        'CoolStar'
    )

    try {
        $activeInfs = @(
            Get-CimInstance Win32_PnPSignedDriver -ErrorAction Stop |
                Where-Object { $_.InfName -match '^oem\d+\.inf$' } |
                ForEach-Object { $_.InfName.ToLowerInvariant() } |
                Sort-Object -Unique
        )
        $storePackages = @(Get-WindowsDriver -Online -All -ErrorAction Stop)
    } catch {
        Write-Warning "Could not enumerate Driver Store for old-package cleanup: $($_.Exception.Message)"
        return
    }

    foreach ($originalName in $originalNames) {
        $wantedName = $originalName.ToLowerInvariant()
        $packages = @(
            $storePackages | Where-Object {
                $original = [IO.Path]::GetFileName([string]$_.OriginalFileName).ToLowerInvariant()
                $version = try { [version]$_.Version } catch { [version]'0.0.0.0' }
                $original -eq $wantedName -and
                    $projectProviders -contains $_.ProviderName
            }
        )
        if ($packages.Count -le 1) { continue }

        # Driver version and date decide package rank. For an exact tie, retain
        # the package currently selected by PnP, then the newest OEM number.
        $ordered = @(
            $packages | Sort-Object `
                @{ Expression = { try { [version]$_.Version } catch { [version]'0.0.0.0' } }; Descending = $true }, `
                @{ Expression = { $_.Date }; Descending = $true }, `
                @{ Expression = { $activeInfs -contains ([string]$_.Driver).ToLowerInvariant() }; Descending = $true }, `
                @{ Expression = { if ($_.Driver -match '^oem(\d+)\.inf$') { [int]$Matches[1] } else { -1 } }; Descending = $true }
        )
        $keep = $ordered[0]
        Write-Host "  Keeping $($keep.Driver) for $originalName (version $($keep.Version))."

        foreach ($old in ($ordered | Select-Object -Skip 1)) {
            $publishedName = ([string]$old.Driver).ToLowerInvariant()
            if ($publishedName -notmatch '^oem\d+\.inf$') {
                Write-Warning "Skipping unexpected published driver name '$publishedName'."
                continue
            }

            Write-Host "  Removing superseded $publishedName (version $($old.Version))..."
            $deleteOutput = & pnputil.exe /delete-driver $publishedName /uninstall /force 2>&1
            $deleteCode = $LASTEXITCODE
            if ($deleteCode -ne 0 -and $deleteCode -ne 3010) {
                $deleteOutput | Out-Host
                Write-Warning "Could not remove $publishedName (code $deleteCode); Windows may still be using it until reboot."
            }
        }
    }

    pnputil.exe /scan-devices | Out-Null
}

function Remove-ConflictingDspDrivers {
    # Other SOF drivers for the same CSAUDIO\ADSP device (for example the
    # earlier pujjoteen bring-up driver, original name sofaudio.inf) would
    # compete with csaudiointcsof.inf for the DSP, so remove their packages.
    $text = (pnputil /enum-drivers) -join "`n"
    foreach ($block in ($text -split "(\r?\n){2,}")) {
        if ($block -match 'Original Name:\s+sofaudio\.inf' -and
            $block -match 'Published Name:\s+(oem\d+\.inf)') {
            $published = $Matches[1]
            Write-Host "  Removing the earlier bring-up DSP driver $published (sofaudio.inf)..."
            $out = & pnputil.exe /delete-driver $published /uninstall /force 2>&1
            if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 3010) {
                $out | Out-Host
                Write-Warning "Could not remove $published (code $LASTEXITCODE)."
            }
        }
    }
}

# ------------------------------------------------------------------ bus driver
# Always install this package's bus driver: the DSP driver is built and tested
# against it (another sklhdaudbus build may expose a different bus interface).
Step 'Intel audio bus driver'
Install-Inf 'Drivers\SklHdaudBus\sklhdaudbus.inf'
Set-ItemProperty -Path $regRoot -Name 'InstalledBusDriver' -Value 1 -Type DWord
pnputil /scan-devices | Out-Null

# ------------------------------------------------------------------ audio drivers
Step 'Audio drivers'
foreach ($k in 'DspBoot', 'DspIpc', 'DspDiag', 'Codec', 'AmpLeft', 'AmpRight', 'Amp0', 'Amp1') {
    if (Test-Path "$regRoot\$k") { Remove-Item "$regRoot\$k" -Recurse -Force }
}
# Settings that only applied to volmar's MAX98373 / NAU88L25 drivers.
foreach ($n in 'JackActiveLow', 'SpeakerLimiterThresholdDb') {
    Remove-ItemProperty -Path $regRoot -Name $n -ErrorAction SilentlyContinue
}
reg add HKLM\SOFTWARE\CrosSofAudio\DspBoot /f | Out-Null
# The MAX98360A has no volume control of its own; keep ~80 % speaker
# amplitude (-2 dB) in the DSP so loud content does not clip.
Set-ItemProperty -Path $regRoot -Name 'SpeakerDspAttenDb' -Value 2 -Type DWord
Remove-ConflictingDspDrivers
Install-Inf 'Drivers\CsAudioIntcsof\csaudiointcsof.inf'
Install-Inf 'Drivers\rt5682\rt5682.inf'
Install-Inf 'Drivers\max98357a\max98357a.inf'

Step 'Cleaning superseded driver packages'
Remove-SupersededDriverPackages @(
    'csaudiointcsof.inf',
    'rt5682.inf',
    'max98357a.inf',
    'sklhdaudbus.inf'
)

# ------------------------------------------------------------------ switcher service
Step 'Headphone / speaker auto-switcher'
$exeSrc = Join-Path $here 'Switcher\csaudioendpointswitcher.exe'
if (Test-Path $exeSrc) {
    $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    if ($svc) {
        if ($svc.Status -ne 'Stopped') {
            Stop-Service $svcName -Force
            $svc.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(15))
        }
    }
    New-Item -ItemType Directory -Force $progDir | Out-Null
    Copy-Item $exeSrc $progDir -Force
    $exe = Join-Path $progDir 'csaudioendpointswitcher.exe'
    if ($svc) {
        sc.exe config $svcName binPath= "`"$exe`"" start= auto | Out-Null
        if ($LASTEXITCODE -ne 0) { Fail "Could not update the $svcName service (code $LASTEXITCODE)." }
    } else {
        New-Service -Name $svcName -BinaryPathName "`"$exe`"" -DisplayName 'Chromebook Audio Jack Switcher' `
                    -Description 'Switches between Speakers and Headphones when headphones are plugged in or out.' `
                    -StartupType Automatic | Out-Null
    }
    sc.exe failure $svcName reset= 86400 actions= restart/5000/restart/5000/restart/30000 | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail "Could not configure recovery for the $svcName service (code $LASTEXITCODE)." }
    Start-Service $svcName
    $svc = Get-Service -Name $svcName
    $svc.WaitForStatus('Running', [TimeSpan]::FromSeconds(15))
    Write-Host "  installed ($exe)"
} else {
    Fail 'The package is incomplete; the endpoint switcher is missing.'
}

# ------------------------------------------------------------------ check
Step 'Result'
$drivers = Get-CimInstance Win32_PnPSignedDriver
foreach ($d in ($drivers | Where-Object { $_.DeviceID -match '^ACPI\\MX98360A\\' })) {
    Write-Host "  Speaker amp driver : $($d.DriverVersion) ($($d.InfName))"
}
foreach ($d in ($drivers | Where-Object { $_.DeviceID -match '^ACPI\\10EC5682\\' })) {
    Write-Host "  Headset codec      : $($d.DriverVersion) ($($d.InfName))"
}
foreach ($d in ($drivers | Where-Object { $_.DeviceID -match '^CSAUDIO\\ADSP' })) {
    Write-Host "  SOF DSP driver     : $($d.DriverVersion) ($($d.InfName))"
}

Write-Host "`nDone. REBOOT the laptop to start the new drivers." -ForegroundColor Green
Write-Host 'Volume tuning and troubleshooting: see README.txt.'
