@echo off
:: Builds the host-side IPC3 pipeline generators with MSVC and regenerates
:: the pipeline headers the DSP driver compiles in.
::
::   build_generators.cmd            writes ..\CsAudioIntcsof\sof_*_pipeline(s).h
::   build_generators.cmd <dir>      writes the headers into <dir> instead
::
:: The generators include <ipc/*.h> (SOF firmware spelling); include\ipc maps
:: those onto the Linux SOF ABI headers vendored in sof-include (BSD-3-Clause
:: option of their dual license). Both describe the same IPC3 ABI 3.22 layout.
setlocal EnableDelayedExpansion

set "HERE=%~dp0"
set "BIN=%HERE%out"
set "DEST=%~1"
if "%DEST%"=="" set "DEST=%HERE%..\CsAudioIntcsof"

set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
for /f "usebackq tokens=*" %%i in (`"!VSWHERE!" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VS_PATH=%%i"
if not defined VS_PATH (
    echo [ERROR] Visual Studio with the C++ x64 tools was not found.
    exit /b 1
)
call "%VS_PATH%\VC\Auxiliary\Build\vcvars64.bat" >nul || exit /b 1

if not exist "%BIN%" mkdir "%BIN%"
if not exist "%DEST%" mkdir "%DEST%"

for %%g in (gen_spk_pipeline gen_hp_pipeline gen_capture_pipelines) do (
    cl /nologo /W3 /TC /DCONFIG_IPC_MAJOR_3=1 /I"%HERE%include" /I"%HERE%sof-include" ^
       "%HERE%%%g.c" /Fo"%BIN%\%%g.obj" /Fe"%BIN%\%%g.exe" >"%BIN%\%%g.log" 2>&1
    if errorlevel 1 (
        type "%BIN%\%%g.log"
        echo [ERROR] %%g.c failed to compile.
        exit /b 1
    )
)

"%BIN%\gen_spk_pipeline.exe"      > "%DEST%\sof_spk_pipeline.h"      || exit /b 1
"%BIN%\gen_hp_pipeline.exe"       > "%DEST%\sof_hp_pipeline.h"       || exit /b 1
"%BIN%\gen_capture_pipelines.exe" > "%DEST%\sof_capture_pipelines.h" || exit /b 1

echo [OK] Pipeline headers written to %DEST%
exit /b 0
