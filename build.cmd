@echo off
setlocal EnableDelayedExpansion
:: Started from PowerShell 7 (as in GitHub Actions), PSModulePath lists the
:: PowerShell 7 modules, and the Windows PowerShell 5.1 helpers below then fail
:: to load their Certificate provider. Empty, 5.1 uses its own defaults.
set "PSModulePath="

:: Builds, catalogs and test-signs the pujjoteen driver set:
::   SklHdaudBus     Intel HDA / audio DSP bus      PCI\VEN_8086&DEV_54C8
::   CsAudioIntcsof  SOF DSP driver + sof-adl-n.ri  CSAUDIO\ADSP&...&CTLR_DEV_54C8
::   rt5682          ALC5682I-VD headset codec      ACPI\10EC5682
::   max98357a       MAX98360A speaker amp          ACPI\MX98360A
::   csaudioendpointswitcher.exe (jack -> default endpoint service)
::   csaudiojackprompt.exe       (asks the plugged-in device type, user session)
::
:: Signing certificate: SIGN_CERT_SHA1 if set, otherwise the
:: "CN=audiodriver test signing" certificate from CurrentUser\My or
:: LocalMachine\My (build-tools\Find-DefaultSigningCertificate.ps1).
:: SIGN_CERT_PFX_PATH / SIGN_CERT_PFX_PASSWORD sign from a PFX instead.

set "ROOT_DIR=%~dp0"
set "OUT_DIR=%ROOT_DIR%x64\Release"
set "ERROR_LOG=%ROOT_DIR%build_errors.log"
set "FULL_LOG=%ROOT_DIR%build_full.log"
set "BUILD_RESULT=0"
set "PACKAGES=SklHdaudBus CsAudioIntcsof rt5682 max98357a"

echo ====================================================================
echo  Chromebook SOF Audio Drivers (pujjoteen: MAX98360A + ALC5682I-VD)
echo ====================================================================
echo.

set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "!VSWHERE!" (
    echo [ERROR] vswhere.exe not found. Install Visual Studio 2022/2026 with the WDK.
    set "BUILD_RESULT=1"
    goto :BuildDone
)
for /f "usebackq tokens=*" %%i in (`"!VSWHERE!" -latest -products * -requires Microsoft.Component.MSBuild -property installationPath`) do set "VS_PATH=%%i"
if not defined VS_PATH (
    echo [ERROR] Visual Studio with MSBuild not detected.
    set "BUILD_RESULT=1"
    goto :BuildDone
)
set "MSBUILD=!VS_PATH!\MSBuild\Current\Bin\MSBuild.exe"
if not exist "!MSBUILD!" (
    echo [ERROR] MSBuild.exe not found at "!MSBUILD!".
    set "BUILD_RESULT=1"
    goto :BuildDone
)
echo [INFO] Visual Studio: "!VS_PATH!"

set "TARGET_PLATFORM_ARG="
if defined WINDOWS_TARGET_PLATFORM_VERSION (
    set "TARGET_PLATFORM_ARG=/p:WindowsTargetPlatformVersion=!WINDOWS_TARGET_PLATFORM_VERSION!"
    echo [INFO] Pinning Windows SDK/WDK target to !WINDOWS_TARGET_PLATFORM_VERSION!.
)

if exist "!ERROR_LOG!" del /f /q "!ERROR_LOG!"
if exist "!FULL_LOG!" del /f /q "!FULL_LOG!"

:: Never reuse a catalog generated for older INF or binary contents.
for %%d in (%PACKAGES%) do if exist "%OUT_DIR%\%%d\*.cat" del /f /q "%OUT_DIR%\%%d\*.cat"
:: A rebuild replaces any Microsoft-signed drivers with test-signed ones.
if exist "%OUT_DIR%\MICROSOFT_SIGNED" del /f /q "%OUT_DIR%\MICROSOFT_SIGNED"

:: ---------------------------------------------------------------- build
echo [INFO] Building ChromebookAudioDrivers.sln (Release ^| x64)...
"!MSBUILD!" "%ROOT_DIR%ChromebookAudioDrivers.sln" ^
    /p:Configuration=Release ^
    /p:Platform=x64 !TARGET_PLATFORM_ARG! ^
    /m ^
    /v:minimal ^
    /flp1:logfile="!ERROR_LOG!";errorsonly ^
    /flp2:logfile="!FULL_LOG!";verbosity=normal
if errorlevel 1 (
    echo.
    echo [ERROR] MSBuild failed. Errors:
    if exist "!ERROR_LOG!" type "!ERROR_LOG!"
    set "BUILD_RESULT=1"
    goto :BuildDone
)

:: The DSP driver package carries the Intel-signed SOF firmware.
copy /y "%ROOT_DIR%CsAudioIntcsof\sof-adl-n.ri" "%OUT_DIR%\CsAudioIntcsof\" >nul || (
    echo [ERROR] Could not copy sof-adl-n.ri into the CsAudioIntcsof package.
    set "BUILD_RESULT=1"
    goto :BuildDone
)

for %%d in (%PACKAGES%) do (
    if not exist "%OUT_DIR%\%%d\%%d.sys" (
        echo [ERROR] Missing driver package output: %OUT_DIR%\%%d\%%d.sys
        set "BUILD_RESULT=1"
        goto :BuildDone
    )
)

:: ---------------------------------------------------------------- catalogs
set "INF2CAT="
for /f "usebackq delims=" %%i in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT_DIR%build-tools\Find-Inf2Cat.ps1"`) do set "INF2CAT=%%i"
if not defined INF2CAT (
    echo [ERROR] inf2cat.exe was not found in the installed Windows Driver Kit.
    set "BUILD_RESULT=1"
    goto :BuildDone
)
for %%d in (%PACKAGES%) do (
    echo [INFO] Generating catalog for %%d...
    "!INF2CAT!" /driver:"%OUT_DIR%\%%d" /os:10_X64 /uselocaltime >"%OUT_DIR%\%%d.inf2cat.log" 2>&1
    if errorlevel 1 (
        type "%OUT_DIR%\%%d.inf2cat.log"
        echo [ERROR] inf2cat failed for %%d.
        set "BUILD_RESULT=1"
        goto :BuildDone
    )
)

:: ---------------------------------------------------------------- signing
set "SIGNTOOL="
for /f "usebackq delims=" %%i in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT_DIR%build-tools\Find-SignTool.ps1"`) do set "SIGNTOOL=%%i"
if not defined SIGNTOOL (
    echo [ERROR] signtool.exe was not found in the installed Windows Driver Kit.
    set "BUILD_RESULT=1"
    goto :BuildDone
)

set "SIGN_CERT_STORE="
set "RESOLVED_SIGN_CERT_SHA1="
if defined SIGN_CERT_PFX_PATH (
    for /f "usebackq delims=" %%a in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT_DIR%build-tools\Resolve-PfxSigningCertificate.ps1" -PfxPath "!SIGN_CERT_PFX_PATH!" -ExpectedCertificatePath "%ROOT_DIR%ChromebookAudio.cer" -OutputPath "%OUT_DIR%\ChromebookAudio.cer"`) do set "RESOLVED_SIGN_CERT_SHA1=%%a"
    set "SIGN_CERT_STORE=PFX"
) else (
    if not defined SIGN_CERT_SHA1 (
        for /f "usebackq delims=" %%a in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT_DIR%build-tools\Find-DefaultSigningCertificate.ps1"`) do set "SIGN_CERT_SHA1=%%a"
    )
    if not defined SIGN_CERT_SHA1 (
        echo [ERROR] No signing certificate. Set SIGN_CERT_SHA1 to a code-signing certificate
        echo         in CurrentUser\My, or create "CN=audiodriver test signing".
        set "BUILD_RESULT=1"
        goto :BuildDone
    )
    for /f "tokens=1,2 delims=|" %%a in ('powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT_DIR%build-tools\Resolve-SigningCertificate.ps1" -CertificatePath "%ROOT_DIR%ChromebookAudio.cer" -OutputPath "%OUT_DIR%\ChromebookAudio.cer" -Thumbprint "!SIGN_CERT_SHA1!"') do (
        set "SIGN_CERT_STORE=%%a"
        set "RESOLVED_SIGN_CERT_SHA1=%%b"
    )
)
if not defined RESOLVED_SIGN_CERT_SHA1 (
    echo [ERROR] Could not resolve the driver signing certificate and private key.
    set "BUILD_RESULT=1"
    goto :BuildDone
)

set "SIGN_PATHS="
for %%d in (%PACKAGES%) do (
    for %%f in ("%OUT_DIR%\%%d\*.sys" "%OUT_DIR%\%%d\*.cat") do set "SIGN_PATHS=!SIGN_PATHS!%%~ff;"
)
set "SIGN_PATHS=!SIGN_PATHS!%OUT_DIR%\csaudioendpointswitcher.exe;%OUT_DIR%\csaudiojackprompt.exe"

echo [INFO] Signing with certificate !RESOLVED_SIGN_CERT_SHA1!...
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT_DIR%build-tools\Sign-BuildOutputs.ps1" ^
    -SignToolPath "!SIGNTOOL!" -Thumbprint "!RESOLVED_SIGN_CERT_SHA1!" ^
    -StoreLocation "!SIGN_CERT_STORE!" -Paths "!SIGN_PATHS!" >"%OUT_DIR%\signtool.log" 2>&1
if errorlevel 1 (
    type "%OUT_DIR%\signtool.log"
    echo [ERROR] Driver package signing failed.
    set "BUILD_RESULT=1"
    goto :BuildDone
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT_DIR%build-tools\Test-DriverSignatures.ps1" ^
    -CertificatePath "%OUT_DIR%\ChromebookAudio.cer" -Paths "!SIGN_PATHS!"
if errorlevel 1 (
    echo [ERROR] One or more build outputs were signed by a different certificate.
    set "BUILD_RESULT=1"
    goto :BuildDone
)

for %%d in (%PACKAGES%) do copy /y "%OUT_DIR%\ChromebookAudio.cer" "%OUT_DIR%\%%d\ChromebookAudio.cer" >nul

echo.
echo ====================================================================
echo  [SUCCESS] Drivers built, cataloged and signed.
echo  Packages: %OUT_DIR%\{%PACKAGES: =,%}
echo  Signer certificate: %OUT_DIR%\ChromebookAudio.cer
echo ====================================================================

:BuildDone
endlocal & exit /b %BUILD_RESULT%
