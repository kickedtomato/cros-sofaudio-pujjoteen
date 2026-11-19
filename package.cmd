@echo off
setlocal EnableDelayedExpansion
:: Started from PowerShell 7 (as in GitHub Actions), PSModulePath lists the
:: PowerShell 7 modules, and the Windows PowerShell 5.1 helpers below then fail
:: to load their Certificate provider. Empty, 5.1 uses its own defaults.
set "PSModulePath="

:: Packages the signed build into
::   dist\cros-sofaudio-<version>\                folder (scripts + drivers)
::   cros-sofaudio-<version>.zip                   same, zipped
::   dist\cros-sofaudio-pujjoteen-setup-<version>.exe   NSIS setup (if NSIS is installed)
::
:: Test-signed builds (build.cmd) need Test Mode on the target. After
:: attestation signing (build-tools\Make-AttestationCab.ps1, then
:: build-tools\Import-AttestationSigned.ps1) x64\Release\MICROSOFT_SIGNED
:: exists, the driver catalogs are checked for Microsoft's signature, and
:: the setup works with Secure Boot on.

set "ROOT_DIR=%~dp0"
set "OUT_DIR=%ROOT_DIR%x64\Release"
set "VERSION=v0.1.0-pujjoteen"
if not "%~1"=="" set "VERSION=%~1"
set "PACKAGES=SklHdaudBus CsAudioIntcsof rt5682 max98357a"

set "DIST_DIR=%ROOT_DIR%dist\cros-sofaudio-%VERSION%"
set "ZIP_FILE=%ROOT_DIR%cros-sofaudio-%VERSION%.zip"
set "SETUP_FILE=%ROOT_DIR%dist\cros-sofaudio-pujjoteen-setup-%VERSION%.exe"

echo ====================================================================
echo  Chromebook SOF Audio Drivers (pujjoteen) - Packaging %VERSION%
echo ====================================================================
echo.

if not exist "%OUT_DIR%\CsAudioIntcsof\csaudiointcsof.cat" (
    echo [INFO] Signed packages not found. Running build.cmd first...
    call "%ROOT_DIR%build.cmd"
    if !ERRORLEVEL! neq 0 (
        echo [ERROR] Build failed! Cannot package release.
        exit /b 1
    )
)

set "CERT_FILE=%OUT_DIR%\ChromebookAudio.cer"
if not exist "%CERT_FILE%" (
    echo [ERROR] %CERT_FILE% is missing. Run build.cmd before packaging.
    exit /b 1
)

set "DRIVER_PATHS="
for %%d in (%PACKAGES%) do (
    for %%f in ("%OUT_DIR%\%%d\*.sys" "%OUT_DIR%\%%d\*.cat") do set "DRIVER_PATHS=!DRIVER_PATHS!%%~ff;"
)
set "PROGRAM_PATHS=%OUT_DIR%\csaudioendpointswitcher.exe;%OUT_DIR%\csaudiojackprompt.exe"

if exist "%OUT_DIR%\MICROSOFT_SIGNED" (
    echo [INFO] Verifying Microsoft attestation signatures on the drivers...
    powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT_DIR%build-tools\Test-MicrosoftSigned.ps1" -Paths "!DRIVER_PATHS!"
    if !ERRORLEVEL! neq 0 (
        echo [ERROR] The drivers are not all Microsoft-signed.
        exit /b 1
    )
    set "VERIFY_PATHS=!PROGRAM_PATHS!"
) else (
    echo [INFO] Test-signed drivers: the setup will need Test Mode on the target.
    set "VERIFY_PATHS=!DRIVER_PATHS!!PROGRAM_PATHS!"
)

echo [INFO] Verifying signatures against %CERT_FILE%...
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT_DIR%build-tools\Test-DriverSignatures.ps1" ^
    -CertificatePath "%CERT_FILE%" -Paths "!VERIFY_PATHS!"
if !ERRORLEVEL! neq 0 (
    echo [ERROR] Packaging stopped because the certificate does not match the signed binaries.
    exit /b 1
)

if exist "%DIST_DIR%" rmdir /s /q "%DIST_DIR%"
mkdir "%DIST_DIR%"

echo [INFO] Copying driver packages to Drivers\...
for %%d in (%PACKAGES%) do (
    mkdir "%DIST_DIR%\Drivers\%%d"
    xcopy /y /e "%OUT_DIR%\%%d\*" "%DIST_DIR%\Drivers\%%d\" >nul
)

echo [INFO] Copying endpoint switcher service and plug-in dialog...
mkdir "%DIST_DIR%\Switcher"
copy /y "%OUT_DIR%\csaudioendpointswitcher.exe" "%DIST_DIR%\Switcher\" >nul
copy /y "%OUT_DIR%\csaudiojackprompt.exe" "%DIST_DIR%\Switcher\" >nul

echo [INFO] Copying installer scripts, documentation and licences...
for %%f in (Install.cmd install.ps1 Uninstall.cmd uninstall.ps1 Collect-Logs.cmd README.txt) do (
    copy /y "%ROOT_DIR%installer\%%f" "%DIST_DIR%\" >nul
)
copy /y "%CERT_FILE%" "%DIST_DIR%\ChromebookAudio.cer" >nul
copy /y "%ROOT_DIR%LICENSE" "%DIST_DIR%\LICENSE.txt" >nul
copy /y "%ROOT_DIR%CsAudioIntcsof\LICENCE.sof-firmware-intel" "%DIST_DIR%\LICENCE.sof-firmware.txt" >nul
copy /y "%ROOT_DIR%rt5682\LICENSE.txt" "%DIST_DIR%\LICENSE.rt5682.txt" >nul
copy /y "%ROOT_DIR%max98357a\LICENSE.txt" "%DIST_DIR%\LICENSE.max98357a.txt" >nul
echo %VERSION%> "%DIST_DIR%\VERSION.txt"

if exist "%ZIP_FILE%" del /f /q "%ZIP_FILE%"
echo [INFO] Creating release archive: %ZIP_FILE%...
powershell -NoProfile -Command "Compress-Archive -Path '%DIST_DIR%\*' -DestinationPath '%ZIP_FILE%' -CompressionLevel Optimal"
if errorlevel 1 (
    echo [ERROR] Failed to create ZIP archive!
    exit /b 1
)

:: ---------------------------------------------------------------- NSIS setup
set "MAKENSIS="
for %%p in ("%ProgramFiles(x86)%\NSIS\makensis.exe" "%ProgramFiles%\NSIS\makensis.exe") do if exist "%%~p" set "MAKENSIS=%%~p"
if not defined MAKENSIS (
    echo [WARN] NSIS ^(makensis.exe^) not found; skipping the setup .exe.
    goto :Done
)

set "VERSION_NUM="
for /f "usebackq delims=" %%v in (`powershell -NoProfile -Command "if ('%VERSION%' -match '(\d+)\.(\d+)\.(\d+)') { '{0}.{1}.{2}.0' -f $Matches[1],$Matches[2],$Matches[3] } else { '0.0.0.0' }"`) do set "VERSION_NUM=%%v"

:: Sign the setup with the same certificate as the programs.
set "SIGN_ARG="
for /f "usebackq delims=" %%i in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT_DIR%build-tools\Find-SignTool.ps1"`) do set "SIGNTOOL=%%i"
if not defined SIGN_CERT_PFX_PATH if not defined SIGN_CERT_SHA1 (
    for /f "usebackq delims=" %%t in (`powershell -NoProfile -Command "(New-Object System.Security.Cryptography.X509Certificates.X509Certificate2('%CERT_FILE%')).Thumbprint"`) do set "SIGN_CERT_SHA1=%%t"
)
if defined SIGNTOOL set "SIGN_ARG=/DSIGN_SCRIPT=%ROOT_DIR%build-tools\sign-file.cmd"

echo [INFO] Building NSIS setup: %SETUP_FILE%...
"%MAKENSIS%" /V2 /DVERSION=%VERSION% /DVERSION_NUM=%VERSION_NUM% "/DDISTDIR=%DIST_DIR%" "/DOUTFILE=%SETUP_FILE%" %SIGN_ARG% "%ROOT_DIR%installer\nsis\cros-sofaudio-pujjoteen.nsi"
if errorlevel 1 (
    echo [ERROR] makensis failed.
    exit /b 1
)

:Done
echo.
echo ====================================================================
echo  [SUCCESS] Release package created.
echo  Directory: %DIST_DIR%
echo  Archive:   %ZIP_FILE%
if exist "%SETUP_FILE%" echo  Setup:     %SETUP_FILE%
echo ====================================================================
endlocal
