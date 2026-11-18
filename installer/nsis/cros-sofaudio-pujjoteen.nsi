; cros-sofaudio-pujjoteen.nsi - NSIS setup for the pujjoteen Chromebook audio drivers
;
; Built by package.cmd:
;   makensis /DVERSION=v0.1.0-pujjoteen /DVERSION_NUM=0.1.0.0 /DDISTDIR=<dist folder>
;            /DOUTFILE=<setup.exe> [/DSIGN_SCRIPT=<build-tools\sign-file.cmd>] cros-sofaudio-pujjoteen.nsi
;
; The setup copies the package (drivers, switcher, plug-in dialog, scripts) to
; %ProgramFiles%\CrosSofAudio\Package and runs installer\install.ps1 there with
; -Unattended. install.ps1 does the hardware check, signature checks, driver
; installation and service setup, and decides between the Microsoft-signed
; (Secure Boot) and test-signed (Test Mode) paths. Its exit code drives the
; messages below. The uninstaller runs uninstall.ps1 from the same folder.

Unicode true
ManifestDPIAware true
RequestExecutionLevel admin
SetCompressor /SOLID lzma

!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "x64.nsh"
!include "WinVer.nsh"

!ifndef VERSION
  !define VERSION "v0.0.0-dev"
!endif
!ifndef VERSION_NUM
  !define VERSION_NUM "0.0.0.0"
!endif
!ifndef DISTDIR
  !error "Pass /DDISTDIR=<package folder from package.cmd>"
!endif
!ifndef OUTFILE
  !define OUTFILE "cros-sofaudio-pujjoteen-setup.exe"
!endif

!define APPNAME   "Chromebook Audio for Windows (pujjoteen)"
!define PUBLISHER "cros-sofaudio-pujjoteen"
!define UNINSTKEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\CrosSofAudioPujjoteen"

!ifdef SIGN_SCRIPT
  ; Sign the setup and the embedded uninstaller with the release certificate
  ; (sign-file.cmd reads SIGNTOOL and SIGN_CERT_SHA1 / SIGN_CERT_PFX_PATH).
  !finalize '"${SIGN_SCRIPT}" "%1"' = 0
  !uninstfinalize '"${SIGN_SCRIPT}" "%1"' = 0
!endif

Name "${APPNAME}"
OutFile "${OUTFILE}"
InstallDir "$PROGRAMFILES64\CrosSofAudio"
ShowInstDetails show
ShowUninstDetails show
BrandingText "${APPNAME} ${VERSION}"

VIProductVersion "${VERSION_NUM}"
VIAddVersionKey "ProductName"     "${APPNAME}"
VIAddVersionKey "FileDescription" "${APPNAME} setup"
VIAddVersionKey "FileVersion"     "${VERSION}"
VIAddVersionKey "ProductVersion"  "${VERSION}"
VIAddVersionKey "CompanyName"     "${PUBLISHER}"
VIAddVersionKey "LegalCopyright"  "MIT / Apache-2.0 / BSD-3-Clause; see LICENSE files"

!define MUI_ABORTWARNING
!define MUI_WELCOMEPAGE_TEXT "This installs Intel Sound Open Firmware audio drivers for the Google pujjoteen Chromebook (Intel Alder Lake-N, MAX98360A speaker amp, ALC5682I headset codec):$\r$\n$\r$\n  - speakers, headphones and headset microphone$\r$\n  - the built-in microphones$\r$\n  - automatic speaker/headphone switching$\r$\n$\r$\nThe laptop must be restarted afterwards."
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "${DISTDIR}\LICENSE.txt"
!insertmacro MUI_PAGE_INSTFILES
!define MUI_FINISHPAGE_TEXT_REBOOT "Restart now to start the new audio drivers."
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_UNPAGE_FINISH
!insertmacro MUI_LANGUAGE "English"

Function .onInit
  ${IfNot} ${RunningX64}
    MessageBox MB_ICONSTOP "These drivers need 64-bit Windows 10 or 11." /SD IDOK
    Abort
  ${EndIf}
  ${IfNot} ${AtLeastWin10}
    MessageBox MB_ICONSTOP "These drivers need Windows 10 or 11." /SD IDOK
    Abort
  ${EndIf}
  SetRegView 64
FunctionEnd

Function un.onInit
  SetRegView 64
FunctionEnd

Section "Install"
  SetShellVarContext all
  SetOutPath "$INSTDIR\Package"
  File /r "${DISTDIR}\*.*"

  ; The setup is a 32-bit process: without this, $SYSDIR paths are redirected
  ; to SysWOW64, starting 32-bit PowerShell, which cannot see pnputil.exe or
  ; bcdedit.exe (both exist only as 64-bit).
  ${DisableX64FSRedirection}

  DetailPrint "Running the driver installer (log: $INSTDIR\Package\install.log)..."
  nsExec::ExecToLog `"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -Command "& '$INSTDIR\Package\install.ps1' -Unattended *>&1 | Tee-Object -FilePath '$INSTDIR\Package\install.log'; exit $$LASTEXITCODE"`
  Pop $0
  DetailPrint "install.ps1 exit code: $0"

  ${If} $0 == 2
    ; Test-signed package and Windows is not in Test Mode.
    MessageBox MB_YESNO|MB_ICONEXCLAMATION "This build of the drivers is test-signed, so Windows must run in Test Mode, and Test Mode needs Secure Boot turned off in the firmware settings.$\r$\n$\r$\n(Releases signed by Microsoft do not need this.)$\r$\n$\r$\nTurn on Test Mode now? You will need to restart and run this setup again." /SD IDNO IDYES enable_testmode
    RMDir /r "$INSTDIR\Package"
    Abort "Installation stopped: Test Mode is required for test-signed drivers."
  enable_testmode:
    nsExec::ExecToLog '"$SYSDIR\bcdedit.exe" /set testsigning on'
    Pop $1
    RMDir /r "$INSTDIR\Package"
    ${If} $1 != 0
      MessageBox MB_ICONSTOP "Windows refused to turn on Test Mode. Secure Boot is probably on: turn it off in the firmware (UEFI) setup, then run this setup again." /SD IDOK
      Abort "Could not turn on Test Mode."
    ${EndIf}
    MessageBox MB_ICONINFORMATION "Test Mode is now on. Restart the laptop, then run this setup again." /SD IDOK
    SetRebootFlag true
    Abort "Restart, then run setup again."
  ${ElseIf} $0 == 3
    RMDir /r "$INSTDIR\Package"
    MessageBox MB_ICONSTOP "This laptop is not a pujjoteen Chromebook (Alder Lake-N with a MAX98360A amp and an ALC5682I codec). Nothing was installed." /SD IDOK
    Abort "Unsupported hardware."
  ${ElseIf} $0 != 0
    MessageBox MB_ICONSTOP "The driver installation failed (code $0). See the details above; Collect-Logs.cmd in $INSTDIR\Package gathers diagnostics." /SD IDOK
    Abort "Driver installation failed."
  ${EndIf}

  ${EnableX64FSRedirection}
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  WriteRegStr   HKLM "${UNINSTKEY}" "DisplayName"          "${APPNAME}"
  WriteRegStr   HKLM "${UNINSTKEY}" "DisplayVersion"       "${VERSION}"
  WriteRegStr   HKLM "${UNINSTKEY}" "Publisher"            "${PUBLISHER}"
  WriteRegStr   HKLM "${UNINSTKEY}" "InstallLocation"      "$INSTDIR"
  WriteRegStr   HKLM "${UNINSTKEY}" "UninstallString"      '"$INSTDIR\Uninstall.exe"'
  WriteRegStr   HKLM "${UNINSTKEY}" "QuietUninstallString" '"$INSTDIR\Uninstall.exe" /S'
  WriteRegDWORD HKLM "${UNINSTKEY}" "NoModify" 1
  WriteRegDWORD HKLM "${UNINSTKEY}" "NoRepair" 1
  WriteRegDWORD HKLM "${UNINSTKEY}" "EstimatedSize" 4096

  SetRebootFlag true
SectionEnd

Section "Uninstall"
  SetShellVarContext all
  InitPluginsDir
  ; 64-bit PowerShell, so uninstall.ps1 can run pnputil (see the install section).
  ${DisableX64FSRedirection}
  DetailPrint "Removing the drivers, the switcher service and the plug-in dialog..."
  ${If} ${FileExists} "$INSTDIR\Package\uninstall.ps1"
    ; uninstall.ps1 deletes %ProgramFiles%\CrosSofAudio, so copy it out first.
    CopyFiles /SILENT "$INSTDIR\Package\uninstall.ps1" "$PLUGINSDIR\uninstall.ps1"
    nsExec::ExecToLog '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$PLUGINSDIR\uninstall.ps1"'
    Pop $0
    DetailPrint "uninstall.ps1 exit code: $0"
  ${EndIf}
  DeleteRegKey HKLM "${UNINSTKEY}"
  RMDir /r "$INSTDIR"
  SetRebootFlag true
SectionEnd
