@echo off
:: Signs one file with the release certificate. Used by package.cmd and by
:: the NSIS script (!finalize / !uninstfinalize).
::   SIGNTOOL            full path to signtool.exe
::   SIGN_CERT_PFX_PATH  sign from a PFX (with SIGN_CERT_PFX_PASSWORD), or
::   SIGN_CERT_SHA1      thumbprint of a certificate in CurrentUser\My
setlocal
if "%~1"=="" exit /b 2
if not defined SIGNTOOL (
    echo [ERROR] SIGNTOOL is not set.
    exit /b 1
)
if defined SIGN_CERT_PFX_PATH (
    if defined SIGN_CERT_PFX_PASSWORD (
        "%SIGNTOOL%" sign /q /f "%SIGN_CERT_PFX_PATH%" /p "%SIGN_CERT_PFX_PASSWORD%" /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 "%~1"
    ) else (
        "%SIGNTOOL%" sign /q /f "%SIGN_CERT_PFX_PATH%" /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 "%~1"
    )
) else (
    if not defined SIGN_CERT_SHA1 (
        echo [ERROR] SIGN_CERT_SHA1 is not set.
        exit /b 1
    )
    "%SIGNTOOL%" sign /q /s My /sha1 %SIGN_CERT_SHA1% /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 "%~1"
)
exit /b %ERRORLEVEL%
