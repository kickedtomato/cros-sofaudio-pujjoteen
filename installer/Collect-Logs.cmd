@echo off
rem Saves a diagnostic log (DSP boot, pipelines, drivers, switcher) next to this file.
set "LOG=%~dp0audio-log.txt"
(
  echo == DSP boot ==
  reg query HKLM\SOFTWARE\CrosSofAudio\DspBoot
  echo.
  echo == DSP IPC / pipelines ==
  reg query HKLM\SOFTWARE\CrosSofAudio\DspIpc
  echo.
  echo == Data-flow snapshots ==
  reg query HKLM\SOFTWARE\CrosSofAudio\DspDiag
  echo.
  echo == Settings ==
  reg query HKLM\SOFTWARE\CrosSofAudio /v *Atten*
  reg query HKLM\SYSTEM\CurrentControlSet\Control\CI\Config /v VulnerableDriverBlocklistEnable
  echo.
  echo == Switcher service ==
  sc query csaudioswitcher
  powershell -NoProfile -Command "if (Test-Path \"$env:ProgramData\CrosSofAudio\switcher.log\") { Get-Content \"$env:ProgramData\CrosSofAudio\switcher.log\" -Tail 40 }"
  echo.
  echo == Drivers ==
  powershell -NoProfile -Command "Get-CimInstance Win32_PnPSignedDriver | Where-Object { $_.DeviceID -match 'CSAUDIO\\ADSP|DEV_54C8|10EC5682|MX98360A' } | Format-List DeviceName,DeviceID,DriverVersion,DriverProviderName,InfName"
  echo == Device status ==
  powershell -NoProfile -Command "Get-PnpDevice | Where-Object { $_.InstanceId -match 'CSAUDIO\\ADSP|DEV_54C8|10EC5682|MX98360A' } | Format-Table -AutoSize Status,FriendlyName,InstanceId | Out-String -Width 300"
  echo == Audio endpoints ==
  powershell -NoProfile -Command "Get-PnpDevice | Where-Object { $_.Class -eq 'AudioEndpoint' -and $_.FriendlyName -match 'Chromebook' } | Format-Table -AutoSize Status,FriendlyName | Out-String -Width 300"
) > "%LOG%" 2>&1
type "%LOG%"
echo.
echo Saved to %LOG%
pause
