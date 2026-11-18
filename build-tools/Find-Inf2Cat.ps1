$ErrorActionPreference = 'Stop'

# inf2cat.exe ships only as an x86 binary (Windows Kits\10\bin\<ver>\x86).
# MSBuild's Inf2Cat task cannot launch it from 64-bit MSBuild on WDK
# 10.0.28000, so build.cmd runs it directly (see Directory.Build.targets).
$programFilesX86 = [Environment]::GetFolderPath('ProgramFilesX86')
$root = Join-Path $programFilesX86 'Windows Kits\10\bin'
if (-not (Test-Path -LiteralPath $root)) { exit 1 }

$requestedVersion = $env:WINDOWS_TARGET_PLATFORM_VERSION
if (-not [string]::IsNullOrWhiteSpace($requestedVersion)) {
    $tool = Join-Path $root "$requestedVersion\x86\inf2cat.exe"
    if (Test-Path -LiteralPath $tool -PathType Leaf) { Write-Output $tool; exit 0 }
    throw "inf2cat.exe for requested kit $requestedVersion was not found."
}

$tool = Get-ChildItem -Path $root -Filter inf2cat.exe -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match '\\10\.0\.\d+\.\d+\\x86\\inf2cat\.exe$' } |
    Sort-Object { [version]($_.Directory.Parent.Name) } |
    Select-Object -Last 1

if (-not $tool) { exit 1 }
Write-Output $tool.FullName
