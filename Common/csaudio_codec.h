/*
 * csaudio_codec.h — Shared definitions between the SOF DSP driver, the
 * codec drivers and the endpoint switcher (pujjoteen build).
 *
 * The DSP driver talks to the codec drivers only through CoolStar's
 * \Callback\CsAudioCallbackAPI kernel callback object. On pujjoteen the
 * codec drivers are CoolStar's open-source rt5682.sys (ALC5682I-VD headset
 * codec) and max98357a.sys (MAX98360A speaker amp); CsAudioArg below must
 * keep the same layout as their copies (rt5682.h / max98357a driver.h).
 *
 * Copyright (c) 2026. Licensed under the MIT License.
 */

#pragma once

/* =========================================================================
 * \Callback\CsAudioCallbackAPI arguments (CoolStar layout)
 * ========================================================================= */

typedef enum {
    CSAudioEndpointTypeDSP        = 0,
    CSAudioEndpointTypeSpeaker    = 1,
    CSAudioEndpointTypeHeadphone  = 2,
    CSAudioEndpointTypeMicArray   = 3,
    CSAudioEndpointTypeMicJack    = 4
} CSAudioEndpointType;

typedef enum {
    CSAudioEndpointRegister       = 0,
    CSAudioEndpointStart          = 1,
    CSAudioEndpointStop           = 2,
    CSAudioEndpointOverrideFormat = 3,
    CSAudioEndpointI2SParameters  = 4   /* DSP -> codec: link clocking */
} CSAudioEndpointRequest;

typedef struct CSAUDIOFORMATOVERRIDE {
    UINT16 channels;
    UINT16 frequency;
    UINT16 bitsPerSample;
    UINT16 validBitsPerSample;
    BOOLEAN force32BitOutputContainer;
} CsAudioFormatOverride;

/*
 * I2S link clocking, sent with CSAudioEndpointI2SParameters. rt5682.sys
 * (version >= 1) programs PLL1 from mclk to 512 * frequency, sets its
 * SYSCLK and uses valid_bits as the I2S/TDM data length (16/20/24/32).
 */
typedef struct CSAUDIOI2SPARAMS {
    UINT32 version;         /* 1 */

    UINT32 mclk;
    UINT32 bclk_rate;
    UINT32 frequency;
    UINT32 tdm_slots;
    UINT32 tdm_slot_width;
    UINT32 rx_slots;
    UINT32 tx_slots;
    UINT32 valid_bits;      /* end of version 1 */
} CsAudioI2SParameters;

#pragma warning(push)
#pragma warning(disable:4201)
typedef struct CSAUDIOARG {
    UINT32 argSz;
    CSAudioEndpointType endpointType;
    CSAudioEndpointRequest endpointRequest;
    union {
        CsAudioFormatOverride formatOverride;
        CsAudioI2SParameters i2sParameters;
    };
} CsAudioArg, *PCsAudioArg;
#pragma warning(pop)

/* =========================================================================
 * Headset jack (rt5682.sys HID vendor collection)
 *
 * rt5682.sys exposes a HID device (VID 0x10EC, PID 0x5682). Its vendor
 * collection (usage page 0xFF00) sends input report
 *     { CSAUDIO_RT5682_REPORTID_JACK, CSAUDIO_RT5682_CONTROL_JACK_TYPE, type }
 * on every jack change and again whenever output report
 *     { CSAUDIO_RT5682_REPORTID_JACK, 0 }
 * is written. "type" uses the Linux SND_JACK_* bits below.
 * ========================================================================= */

#define CSAUDIO_RT5682_HID_VID            0x10EC
#define CSAUDIO_RT5682_HID_PID            0x5682
#define CSAUDIO_RT5682_HID_USAGE_PAGE     0xFF00
#define CSAUDIO_RT5682_REPORTID_JACK      0x02
#define CSAUDIO_RT5682_CONTROL_JACK_TYPE  0x01
#define CSAUDIO_RT5682_JACK_HEADPHONE     0x01   /* SND_JACK_HEADPHONE */
#define CSAUDIO_RT5682_JACK_MICROPHONE    0x02   /* SND_JACK_MICROPHONE */

/* Jack routing state used by the endpoint switcher. */
typedef enum _CSAUDIO_JACK_STATE {
    CSAUDIO_JACK_UNPLUGGED        = 0x00,
    CSAUDIO_JACK_HEADPHONES_3POLE = 0x01,  /* Standard TRS stereo headphones (no mic) */
    CSAUDIO_JACK_HEADSET_4POLE    = 0x02,  /* TRRS headset with microphone (CTIA/OMTP) */
    CSAUDIO_JACK_LINE_OUT         = 0x04,  /* High impedance line output */
} CSAUDIO_JACK_STATE, *PCSAUDIO_JACK_STATE;
