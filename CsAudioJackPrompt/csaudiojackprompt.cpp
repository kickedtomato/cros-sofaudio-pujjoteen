/*
 * csaudiojackprompt.cpp — "Which device did you plug in?" dialog
 *
 * Runs in the signed-in user's session (started at sign-in from
 * HKLM\...\Run, see installer\install.ps1). The csaudioswitcher service
 * runs in session 0 and cannot show windows; it routes every jack change
 * automatically from the codec's detection. This app watches the same
 * rt5682 HID jack report and, when something is plugged in, asks what it
 * is, with the detected type preselected:
 *
 *   Headphones or line out  output -> Headphones, input -> built-in mics
 *   Headset                 output -> Headphones, input -> headset mic
 *   Microphone only         output -> Speakers,   input -> headset mic
 *
 * The microphone choices need a 4-pole (TRRS) plug; for a 3-pole plug the
 * codec leaves the mic contact unpowered, so those choices are disabled.
 * The choice is applied after the service's automatic routing, through the
 * same IPolicyConfig calls the service uses.
 *
 *   csaudiojackprompt.exe            run (one instance per session)
 *   csaudiojackprompt.exe /enable    ask again on every plug-in, then exit
 *   csaudiojackprompt.exe /disable   stop asking, then exit
 *
 * "Don't ask again" stores HKCU\Software\CrosSofAudio\AskOnJackPlug = 0.
 *
 * Copyright (c) 2026. Licensed under the MIT License.
 */
#define WIN32_LEAN_AND_MEAN
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0A00
#endif
#include <windows.h>
#include <commctrl.h>
#include <mmreg.h>
#include <setupapi.h>
#include <mmdeviceapi.h>
#include <initguid.h>
#include <functiondiscoverykeys_devpkey.h>
#include <hidsdi.h>
#include <hidpi.h>
#include <stdlib.h>
#include <strsafe.h>
#include "..\Common\csaudio_codec.h"

#pragma comment(lib, "comctl32.lib")
#pragma comment(lib, "setupapi.lib")
#pragma comment(lib, "hid.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "advapi32.lib")
#pragma comment(lib, "user32.lib")
#pragma comment(linker, "\"/manifestdependency:type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'\"")

/* Undocumented PolicyConfig interface (same as csaudioendpointswitcher). */
DEFINE_GUID(CLSID_PolicyConfigClient,
    0x870af99c, 0x171d, 0x4f9e, 0xaf, 0x0d, 0xe6, 0x3d, 0xf4, 0x0c, 0x2b, 0xc9);
DEFINE_GUID(IID_IPolicyConfig,
    0xf8679f50, 0x850a, 0x41cf, 0x9c, 0x72, 0x43, 0x0f, 0x29, 0x02, 0x90, 0xc8);

interface IPolicyConfig : public IUnknown
{
public:
    virtual HRESULT STDMETHODCALLTYPE GetMixFormat(PCWSTR, WAVEFORMATEX **) = 0;
    virtual HRESULT STDMETHODCALLTYPE GetDeviceFormat(PCWSTR, INT, WAVEFORMATEX **) = 0;
    virtual HRESULT STDMETHODCALLTYPE ResetDeviceFormat(PCWSTR) = 0;
    virtual HRESULT STDMETHODCALLTYPE SetDeviceFormat(PCWSTR, WAVEFORMATEX *, WAVEFORMATEX *) = 0;
    virtual HRESULT STDMETHODCALLTYPE GetProcessingPeriod(PCWSTR, INT, PINT64, PINT64) = 0;
    virtual HRESULT STDMETHODCALLTYPE SetProcessingPeriod(PCWSTR, PINT64) = 0;
    virtual HRESULT STDMETHODCALLTYPE GetShareMode(PCWSTR, struct DeviceShareMode *) = 0;
    virtual HRESULT STDMETHODCALLTYPE SetShareMode(PCWSTR, struct DeviceShareMode *) = 0;
    virtual HRESULT STDMETHODCALLTYPE GetPropertyValue(PCWSTR, const PROPERTYKEY &, PROPVARIANT *) = 0;
    virtual HRESULT STDMETHODCALLTYPE SetPropertyValue(PCWSTR, const PROPERTYKEY &, PROPVARIANT *) = 0;
    virtual HRESULT STDMETHODCALLTYPE SetDefaultEndpoint(PCWSTR wszDeviceId, ERole eRole) = 0;
    virtual HRESULT STDMETHODCALLTYPE SetEndpointVisibility(PCWSTR wszDeviceId, INT isVisible) = 0;
};

#define WM_APP_JACK         (WM_APP + 1)    /* wParam = CSAUDIO_JACK_STATE */
#define JACK_STATE_UNKNOWN  0xFF

#define CHOICE_HEADPHONES   100
#define CHOICE_HEADSET      101
#define CHOICE_MIC_ONLY     102

static const WCHAR kRegKey[]   = L"Software\\CrosSofAudio";
static const WCHAR kRegValue[] = L"AskOnJackPlug";

static HWND   g_MsgWindow = NULL;
static HANDLE g_StopEvent = NULL;
static HWND   g_Dialog = NULL;          /* open task dialog, if any */
static UINT   g_LastState = JACK_STATE_UNKNOWN;

/* =========================================================================
 * Log: %LOCALAPPDATA%\CrosSofAudio\jackprompt.log
 * ========================================================================= */

static void LogMsg(const WCHAR* fmt, ...) {
    WCHAR msg[512];
    va_list args;
    va_start(args, fmt);
    StringCchVPrintfW(msg, ARRAYSIZE(msg), fmt, args);
    va_end(args);
    OutputDebugStringW(msg);

    WCHAR path[MAX_PATH];
    DWORD n = GetEnvironmentVariableW(L"LOCALAPPDATA", path, MAX_PATH);
    if (n == 0 || n > MAX_PATH - 40) return;
    StringCchCatW(path, MAX_PATH, L"\\CrosSofAudio");
    CreateDirectoryW(path, NULL);
    StringCchCatW(path, MAX_PATH, L"\\jackprompt.log");
    HANDLE h = CreateFileW(path, FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL,
                           OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (h == INVALID_HANDLE_VALUE) return;
    SYSTEMTIME st;
    GetLocalTime(&st);
    char line[700];
    int len = _snprintf_s(line, sizeof(line), _TRUNCATE, "%04u-%02u-%02u %02u:%02u:%02u %ls\r\n",
                          st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond, msg);
    if (len > 0) { DWORD w; WriteFile(h, line, (DWORD)len, &w, NULL); }
    CloseHandle(h);
}

/* =========================================================================
 * Settings
 * ========================================================================= */

static BOOL AskOnPlug() {
    DWORD value = 1, size = sizeof(value);
    if (RegGetValueW(HKEY_CURRENT_USER, kRegKey, kRegValue, RRF_RT_REG_DWORD,
                     NULL, &value, &size) != ERROR_SUCCESS) {
        return TRUE;
    }
    return value != 0;
}

static void SetAskOnPlug(BOOL ask) {
    DWORD value = ask ? 1 : 0;
    RegSetKeyValueW(HKEY_CURRENT_USER, kRegKey, kRegValue, REG_DWORD, &value, sizeof(value));
}

/* =========================================================================
 * Endpoint routing
 * ========================================================================= */

typedef struct _ENDPOINTS {
    WCHAR speaker[MAX_PATH];
    WCHAR headphone[MAX_PATH];
    WCHAR micArray[MAX_PATH];
    WCHAR headsetMic[MAX_PATH];
} ENDPOINTS;

static BOOL IsOurDevice(const WCHAR* name) {
    return name && (wcsstr(name, L"SOF Audio") || wcsstr(name, L"Chromebook") || wcsstr(name, L"CoolStar"));
}

/* Same name matching as csaudioendpointswitcher's RefreshEndpoints(). */
static void FindEndpoints(ENDPOINTS* ep) {
    ZeroMemory(ep, sizeof(*ep));
    IMMDeviceEnumerator* pEnum = NULL;
    if (FAILED(CoCreateInstance(__uuidof(MMDeviceEnumerator), NULL, CLSCTX_ALL,
                                __uuidof(IMMDeviceEnumerator), (void**)&pEnum)) || !pEnum) {
        return;
    }

    const EDataFlow flows[] = { eRender, eCapture };
    for (int f = 0; f < 2; f++) {
        IMMDeviceCollection* pCol = NULL;
        if (FAILED(pEnum->EnumAudioEndpoints(flows[f],
                DEVICE_STATE_ACTIVE | DEVICE_STATE_DISABLED | DEVICE_STATE_UNPLUGGED, &pCol)) || !pCol) {
            continue;
        }
        UINT count = 0;
        pCol->GetCount(&count);
        for (UINT i = 0; i < count; i++) {
            IMMDevice* pDev = NULL;
            if (FAILED(pCol->Item(i, &pDev)) || !pDev) continue;
            LPWSTR id = NULL;
            IPropertyStore* pProps = NULL;
            pDev->GetId(&id);
            pDev->OpenPropertyStore(STGM_READ, &pProps);
            if (id && pProps) {
                PROPVARIANT pv;
                PropVariantInit(&pv);
                if (SUCCEEDED(pProps->GetValue(PKEY_Device_FriendlyName, &pv)) &&
                    pv.vt == VT_LPWSTR && IsOurDevice(pv.pwszVal)) {
                    PCWSTR name = pv.pwszVal;
                    WCHAR* target = NULL;
                    if (flows[f] == eRender) {
                        if (wcsstr(name, L"Headphone"))    target = ep->headphone;
                        else if (wcsstr(name, L"Speaker")) target = ep->speaker;
                    } else {
                        if (wcsstr(name, L"Headset"))                                target = ep->headsetMic;
                        else if (wcsstr(name, L"Internal") || wcsstr(name, L"Array")) target = ep->micArray;
                        else if (wcsstr(name, L"Microphone"))                         target = ep->headsetMic;
                    }
                    if (target) StringCchCopyW(target, MAX_PATH, id);
                }
                PropVariantClear(&pv);
            }
            if (pProps) pProps->Release();
            if (id) CoTaskMemFree(id);
            pDev->Release();
        }
        pCol->Release();
    }
    pEnum->Release();
}

static void MakeDefault(IPolicyConfig* pConfig, PCWSTR id) {
    if (!id || !id[0]) return;
    pConfig->SetEndpointVisibility(id, TRUE);
    /* Communications first, as the service does, so VoIP apps follow. */
    const ERole roles[] = { eCommunications, eMultimedia, eConsole };
    for (int i = 0; i < ARRAYSIZE(roles); i++) {
        for (int attempt = 0; attempt < 3; attempt++) {
            if (SUCCEEDED(pConfig->SetDefaultEndpoint(id, roles[i]))) break;
            Sleep(100);
        }
    }
}

static void ApplyChoice(int choice) {
    ENDPOINTS ep;
    FindEndpoints(&ep);

    IPolicyConfig* pConfig = NULL;
    if (FAILED(CoCreateInstance(CLSID_PolicyConfigClient, NULL, CLSCTX_ALL,
                                IID_IPolicyConfig, (void**)&pConfig)) || !pConfig) {
        MessageBoxW(NULL, L"Could not change the default audio devices.", L"Chromebook Audio",
                    MB_OK | MB_ICONWARNING | MB_TOPMOST);
        return;
    }

    switch (choice) {
    case CHOICE_HEADSET:
        MakeDefault(pConfig, ep.headphone);
        MakeDefault(pConfig, ep.headsetMic);
        break;
    case CHOICE_MIC_ONLY:
        MakeDefault(pConfig, ep.speaker);
        MakeDefault(pConfig, ep.headsetMic);
        break;
    case CHOICE_HEADPHONES:
    default:
        MakeDefault(pConfig, ep.headphone);
        MakeDefault(pConfig, ep.micArray);
        break;
    }
    pConfig->Release();
}

/* =========================================================================
 * Dialog
 * ========================================================================= */

typedef struct _PROMPT_CONTEXT {
    BOOL micContact;    /* 4-pole plug detected */
} PROMPT_CONTEXT;

static HRESULT CALLBACK PromptCallback(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam, LONG_PTR refData) {
    UNREFERENCED_PARAMETER(wParam);
    UNREFERENCED_PARAMETER(lParam);
    PROMPT_CONTEXT* ctx = (PROMPT_CONTEXT*)refData;

    switch (msg) {
    case TDN_CREATED:
        g_Dialog = hwnd;
        if (!ctx->micContact) {
            SendMessageW(hwnd, TDM_ENABLE_RADIO_BUTTON, CHOICE_HEADSET, FALSE);
            SendMessageW(hwnd, TDM_ENABLE_RADIO_BUTTON, CHOICE_MIC_ONLY, FALSE);
        }
        /* Started from the Run key, the app may not own the foreground. */
        SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
        SetForegroundWindow(hwnd);
        break;
    case TDN_DESTROYED:
        g_Dialog = NULL;
        break;
    }
    return S_OK;
}

static void ShowPrompt(UINT state) {
    PROMPT_CONTEXT ctx;
    ctx.micContact = (state == CSAUDIO_JACK_HEADSET_4POLE);

    const TASKDIALOG_BUTTON radios[] = {
        { CHOICE_HEADPHONES, L"Headphones or line out\nHeadphones, or an amplifier or powered speakers. "
                             L"Sound plays through the jack; recording stays on the built-in microphones." },
        { CHOICE_HEADSET,    L"Headset\nHeadphones with a microphone. Sound and recording both use the jack." },
        { CHOICE_MIC_ONLY,   L"Microphone only\nSound stays on the built-in speakers; recording uses the jack." },
    };

    TASKDIALOGCONFIG cfg;
    ZeroMemory(&cfg, sizeof(cfg));
    cfg.cbSize = sizeof(cfg);
    cfg.dwFlags = TDF_ALLOW_DIALOG_CANCELLATION | TDF_POSITION_RELATIVE_TO_WINDOW;
    cfg.dwCommonButtons = TDCBF_OK_BUTTON | TDCBF_CANCEL_BUTTON;
    cfg.pszWindowTitle = L"Chromebook Audio";
    cfg.pszMainIcon = TD_INFORMATION_ICON;
    cfg.pszMainInstruction = L"Which device did you plug in?";
    cfg.pszContent = ctx.micContact
        ? L"A plug with a microphone contact (4-pole) was detected."
        : L"A plug without a microphone contact (3-pole) was detected, so the microphone "
          L"choices are unavailable. Microphones need a 4-pole (TRRS) plug on this jack.";
    cfg.cRadioButtons = ARRAYSIZE(radios);
    cfg.pRadioButtons = radios;
    cfg.nDefaultRadioButton = ctx.micContact ? CHOICE_HEADSET : CHOICE_HEADPHONES;
    cfg.pszVerificationText = L"Don't ask again (always use automatic detection)";
    cfg.pszFooter = L"Cancel keeps the automatic choice.";
    cfg.pfCallback = PromptCallback;
    cfg.lpCallbackData = (LONG_PTR)&ctx;

    int button = 0, radio = 0;
    BOOL dontAsk = FALSE;
    if (FAILED(TaskDialogIndirect(&cfg, &button, &radio, &dontAsk))) return;

    LogMsg(L"Dialog closed: button %d, choice %d, don't ask again %d.", button, radio, dontAsk);
    if (dontAsk) SetAskOnPlug(FALSE);
    if (button == IDOK) ApplyChoice(radio);
}

/* =========================================================================
 * rt5682 HID jack reader (worker thread)
 * ========================================================================= */

static HANDLE OpenJackDevice(USHORT* inputLength) {
    GUID hidGuid;
    HidD_GetHidGuid(&hidGuid);
    HDEVINFO devs = SetupDiGetClassDevsW(&hidGuid, NULL, NULL, DIGCF_PRESENT | DIGCF_DEVICEINTERFACE);
    if (devs == INVALID_HANDLE_VALUE) return INVALID_HANDLE_VALUE;

    HANDLE found = INVALID_HANDLE_VALUE;
    SP_DEVICE_INTERFACE_DATA ifData;
    ifData.cbSize = sizeof(ifData);
    for (DWORD i = 0; found == INVALID_HANDLE_VALUE &&
                      SetupDiEnumDeviceInterfaces(devs, NULL, &hidGuid, i, &ifData); i++) {
        DWORD size = 0;
        SetupDiGetDeviceInterfaceDetailW(devs, &ifData, NULL, 0, &size, NULL);
        PSP_DEVICE_INTERFACE_DETAIL_DATA_W detail = (PSP_DEVICE_INTERFACE_DETAIL_DATA_W)malloc(size);
        if (!detail) continue;
        detail->cbSize = sizeof(*detail);
        if (SetupDiGetDeviceInterfaceDetailW(devs, &ifData, detail, size, NULL, NULL)) {
            /* Read-only access is enough to receive input reports. */
            HANDLE h = CreateFileW(detail->DevicePath, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE,
                                   NULL, OPEN_EXISTING, FILE_FLAG_OVERLAPPED, NULL);
            if (h != INVALID_HANDLE_VALUE) {
                HIDD_ATTRIBUTES attr;
                attr.Size = sizeof(attr);
                BOOL match = FALSE;
                if (HidD_GetAttributes(h, &attr) &&
                    attr.VendorID == CSAUDIO_RT5682_HID_VID && attr.ProductID == CSAUDIO_RT5682_HID_PID) {
                    PHIDP_PREPARSED_DATA pp = NULL;
                    if (HidD_GetPreparsedData(h, &pp)) {
                        HIDP_CAPS caps;
                        if (HidP_GetCaps(pp, &caps) == HIDP_STATUS_SUCCESS &&
                            caps.UsagePage == CSAUDIO_RT5682_HID_USAGE_PAGE &&
                            caps.InputReportByteLength >= 3) {
                            *inputLength = caps.InputReportByteLength;
                            match = TRUE;
                        }
                        HidD_FreePreparsedData(pp);
                    }
                }
                if (match) found = h; else CloseHandle(h);
            }
        }
        free(detail);
    }
    SetupDiDestroyDeviceInfoList(devs);
    return found;
}

static CSAUDIO_JACK_STATE JackStateFromRt5682(BYTE type) {
    if (type & CSAUDIO_RT5682_JACK_MICROPHONE) return CSAUDIO_JACK_HEADSET_4POLE;
    if (type & CSAUDIO_RT5682_JACK_HEADPHONE)  return CSAUDIO_JACK_HEADPHONES_3POLE;
    return CSAUDIO_JACK_UNPLUGGED;
}

static DWORD WINAPI ReaderThread(LPVOID) {
    while (WaitForSingleObject(g_StopEvent, 0) != WAIT_OBJECT_0) {
        USHORT length = 0;
        HANDLE dev = OpenJackDevice(&length);
        if (dev == INVALID_HANDLE_VALUE) {
            if (WaitForSingleObject(g_StopEvent, 3000) == WAIT_OBJECT_0) break;
            continue;
        }
        LogMsg(L"Connected to the rt5682 jack collection.");

        BYTE* report = (BYTE*)calloc(1, length);
        OVERLAPPED ov;
        ZeroMemory(&ov, sizeof(ov));
        ov.hEvent = CreateEventW(NULL, TRUE, FALSE, NULL);
        while (report && ov.hEvent) {
            ResetEvent(ov.hEvent);
            DWORD got = 0;
            if (!ReadFile(dev, report, length, &got, &ov) && GetLastError() != ERROR_IO_PENDING) break;

            HANDLE waits[2] = { g_StopEvent, ov.hEvent };
            DWORD w = WaitForMultipleObjects(2, waits, FALSE, INFINITE);
            if (w != WAIT_OBJECT_0 + 1) {
                CancelIoEx(dev, &ov);
                GetOverlappedResult(dev, &ov, &got, TRUE);
                break;
            }
            if (!GetOverlappedResult(dev, &ov, &got, FALSE)) break;

            if (got >= 3 && report[0] == CSAUDIO_RT5682_REPORTID_JACK &&
                report[1] == CSAUDIO_RT5682_CONTROL_JACK_TYPE) {
                PostMessageW(g_MsgWindow, WM_APP_JACK, (WPARAM)JackStateFromRt5682(report[2]), 0);
            }
        }
        if (ov.hEvent) CloseHandle(ov.hEvent);
        free(report);
        CloseHandle(dev);
        /* Device went away (driver restart, sleep); look for it again. */
        if (WaitForSingleObject(g_StopEvent, 1000) == WAIT_OBJECT_0) break;
    }
    return 0;
}

/* =========================================================================
 * Main
 * ========================================================================= */

static LRESULT CALLBACK MsgWndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    if (msg == WM_APP_JACK) {
        UINT state = (UINT)wParam;
        LogMsg(L"Jack report: state 0x%02X (previous 0x%02X).", state, g_LastState);
        if (state == CSAUDIO_JACK_UNPLUGGED) {
            /* Unplugged while asking: the question no longer applies. */
            if (g_Dialog) PostMessageW(g_Dialog, TDM_CLICK_BUTTON, IDCANCEL, 0);
        } else if (state != g_LastState && !g_Dialog && AskOnPlug()) {
            g_LastState = state;
            /* Give the service a moment to finish its automatic routing so
             * the user's choice is applied after it, not before. */
            Sleep(750);
            ShowPrompt(state);
            return 0;
        }
        /* rt5682 repeats the jack report on headset button presses; only
         * a change of state is a new plug-in. */
        g_LastState = state;
        return 0;
    }
    return DefWindowProcW(hwnd, msg, wParam, lParam);
}

int WINAPI wWinMain(HINSTANCE hInstance, HINSTANCE, PWSTR cmdLine, int) {
    if (cmdLine && _wcsicmp(cmdLine, L"/enable") == 0)  { SetAskOnPlug(TRUE);  return 0; }
    if (cmdLine && _wcsicmp(cmdLine, L"/disable") == 0) { SetAskOnPlug(FALSE); return 0; }

    /* CreateMutexW only sets the last error when the mutex already exists,
     * so clear any leftover value first. */
    SetLastError(ERROR_SUCCESS);
    HANDLE mutex = CreateMutexW(NULL, TRUE, L"Local\\CrosSofAudioJackPrompt");
    if (!mutex) { LogMsg(L"CreateMutex failed (%lu)", GetLastError()); return 1; }
    if (GetLastError() == ERROR_ALREADY_EXISTS) { LogMsg(L"Already running in this session; exiting."); return 0; }
    LogMsg(L"Started (session ask-on-plug=%d).", AskOnPlug());

    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    if (FAILED(CoInitializeEx(NULL, COINIT_APARTMENTTHREADED))) return 1;

    INITCOMMONCONTROLSEX icc = { sizeof(icc), ICC_STANDARD_CLASSES };
    InitCommonControlsEx(&icc);

    WNDCLASSW wc;
    ZeroMemory(&wc, sizeof(wc));
    wc.lpfnWndProc = MsgWndProc;
    wc.hInstance = hInstance;
    wc.lpszClassName = L"CrosSofAudioJackPrompt";
    RegisterClassW(&wc);
    g_MsgWindow = CreateWindowExW(0, wc.lpszClassName, L"", 0, 0, 0, 0, 0, HWND_MESSAGE, NULL, hInstance, NULL);
    g_StopEvent = CreateEventW(NULL, TRUE, FALSE, NULL);
    if (!g_MsgWindow || !g_StopEvent) return 1;

    HANDLE reader = CreateThread(NULL, 0, ReaderThread, NULL, 0, NULL);
    if (!reader) return 1;

    MSG msg;
    while (GetMessageW(&msg, NULL, 0, 0) > 0) {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }

    LogMsg(L"Message loop ended; exiting.");
    SetEvent(g_StopEvent);
    WaitForSingleObject(reader, 5000);
    CloseHandle(reader);
    CoUninitialize();
    ReleaseMutex(mutex);
    CloseHandle(mutex);
    return 0;
}
