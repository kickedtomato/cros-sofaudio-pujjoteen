CHROMEBOOK AUDIO FOR WINDOWS - pujjoteen (Alder Lake-N + MAX98360A + ALC5682I)
==============================================================================

Supported laptop
  Google "pujjoteen" Chromebooks: Intel Alder Lake-N (N100/N200) audio DSP,
  Realtek ALC5682I-VD headset codec and Maxim MAX98360A speaker amp - the
  hardware Linux drives with the "sof-adl-max98360a-rt5682" topology. The
  installer checks for it and stops on anything else.
  Windows must run in Test Mode (the drivers are test-signed); the installer
  can switch it on (Secure Boot must be off for that).

Install
  Easiest: run cros-sofaudio-pujjoteen-setup-<version>.exe and restart.
  Uninstall it from Settings -> Apps. From this folder instead:
  1. Double-click Install.cmd (it asks for administrator rights).
  2. Reboot.
  Test-signed builds need Test Mode (Secure Boot off). Builds whose drivers
  are signed by Microsoft (attestation) work with Secure Boot on and skip
  Test Mode, the certificate import and the blocklist change.
  The installer verifies every driver signature, disables the Microsoft
  Vulnerable Driver Blocklist for these test-signed drivers, removes the
  earlier bring-up DSP driver (sofaudio.inf) if present, and removes
  superseded copies of these packages from Driver Store. Windows then shows
  "Chromebook Speakers", "Chromebook Headphones", "Chromebook Internal
  Microphone" and "Chromebook Headset Microphone". The auto-switcher moves
  playback to Headphones when you plug in and back to Speakers when you
  unplug.

Plugging something into the 3.5 mm jack
  The codec detects the plug's wiring: 3-pole (headphones, line out) or
  4-pole (headset with a microphone contact). The auto-switcher routes from
  that at once, and a small dialog then asks what you plugged in:
    Headphones or line out  sound on the jack, built-in microphones
    Headset                 sound and microphone on the jack
    Microphone only         sound on the built-in speakers, microphone on
                            the jack
  Microphones need a 4-pole (TRRS, CTIA) plug; a 3-pole microphone plug
  cannot be recorded on this jack, so those choices are greyed out for a
  3-pole plug. Line-out devices use the Headphones output (same jack).
  "Don't ask again" turns the dialog off; turn it back on with
    "C:\Program Files\CrosSofAudio\csaudiojackprompt.exe" /enable

What it contains
  Drivers\SklHdaudBus     Intel audio bus driver (CoolStar sklhdaudbus, as
                          modified by cros-sofaudio)
  Drivers\CsAudioIntcsof  boots Intel Sound Open Firmware (sof-adl-n.ri) on
                          the audio DSP; speaker (SSP1), headphone and
                          headset-mic (SSP0) and internal-mic (DMIC0) pipelines
  Drivers\rt5682          ALC5682I-VD headset codec + jack detection (CoolStar)
  Drivers\max98357a       MAX98360A speaker amp enable (CoolStar)
  Switcher\               auto-switch service (csaudioswitcher) and the
                          plug-in dialog (csaudiojackprompt.exe)

Volume tuning (registry, HKLM\SOFTWARE\CrosSofAudio, DWORD; reboot after)
  SpeakerDspAttenDb       speaker attenuation in dB, default 2 (~79% amplitude)
  HeadphoneDspAttenDb     headphone attenuation in dB, default 10
  HeadsetMicDspAttenDb    headset microphone attenuation in dB, default 0
  MicArrayDspAttenDb      internal microphone attenuation in dB, default 0
  Example (6 dB quieter speakers):
    reg add HKLM\SOFTWARE\CrosSofAudio /v SpeakerDspAttenDb /t REG_DWORD /d 6 /f
  The MAX98360A has no volume control; the Windows volume slider scales the
  audio in software and these values set the fixed DSP attenuation.

Problems
  - Collect-Logs.cmd writes audio-log.txt with everything needed to debug.
  - DspBoot\Result says whether the DSP firmware booted; DspIpc\*PipelineResult
    say whether each of the four DSP pipelines was created.
  - Uninstall.cmd removes everything, restores the prior vulnerable-driver
    blocklist setting, and lets Windows fall back to older drivers.
  - Disable the DSP boot:
      reg add HKLM\SOFTWARE\CrosSofAudio /v EnableDspBoot /t REG_DWORD /d 0 /f
  - Blue screen at boot: start Safe Mode and run Uninstall.cmd.

Credits / licences: CoolStar (SklHdaudBus, rt5682, max98357a, csaudio
architecture; Apache-2.0 / BSD-3-Clause), isaiahscape (cros-sofaudio, MIT),
Linux SOF / ASoC drivers (sequences ported), Intel SOF firmware
(LICENCE.sof-firmware.txt, redistributable).
