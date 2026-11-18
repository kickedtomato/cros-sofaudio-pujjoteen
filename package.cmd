@echo off
setlocal EnableDelayedExpansion

set "ROOT_DIR=%~dp0"
set "OUT_DIR=%ROOT_DIR%x64\Release"
set "VERSION=v0.1.0-pujjoteen"
if not "%~1"=="" set "VERSION=%~1"
set "PACKAGES=SklHdaudBus CsAudioIntcsof rt5682 max98357a"

set "DIST_DIR=%ROOT_DIR%dist\cros-sofaudio-%VERSION%"
set "ZIP_FILE=%ROOT_DIR%cros-sofaudio-%VERSION%.zip"

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

set "SIGN_PATHS="
for %%d in (%PACKAGES%) do (
    for %%f in ("%OUT_DIR%\%%d\*.sys" "%OUT_DIR%\%%d\*.cat") do set "SIGN_PATHS=!SIGN_PATHS!%%~ff;"
)
set "SIGN_PATHS=!SIGN_PATHS!%OUT_DIR%\csaudioendpointswitcher.exe;%OUT_DIR%\csaudiojackprompt.exe"

echo [INFO] Verifying package signatures and signer certificate...
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT_DIR%build-tools\Test-DriverSignatures.ps1" ^
    -CertificatePath "%CERT_FILE%" -Paths "!SIGN_PATHS!"
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

echo [INFO] Copying endpoint switcher service...
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

echo.
echo ====================================================================
echo  [SUCCESS] Release package created.
echo  Directory: %DIST_DIR%
echo  Archive:   %ZIP_FILE%
echo ====================================================================
endlocal
