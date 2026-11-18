/*++

Module Name:

    csaudioapi.cpp

Abstract:

    Codec bridge for the pujjoteen SOF driver. The DSP driver talks to the
    codec drivers only through CoolStar's \Callback\CsAudioCallbackAPI
    callback object:

      * max98357a.sys (MAX98360A, SSP1): Start raises SD_MODE after its
        sdmode-delay, Stop lowers it. The amp has no control bus.
      * rt5682.sys (ALC5682I-VD, SSP0): powers up and handles jack
        detection on its own. It needs the SSP0 clocking once
        (CSAudioEndpointI2SParameters) to run its PLL from the 19.2 MHz
        MCLK; it ignores Start/Stop.

--*/

#include "definitions.h"
#include "endpoints.h"
#include "hw.h"

/*
 * SSP0 "SSP0-Codec" link of sof-adl-max98360a-rt5682.tplg. These must match
 * make_ssp0_config() / make_dai_config() in tools-gen/gen_hp_pipeline.c and
 * gen_capture_pipelines.c, which produce the DAI_CONFIG the DSP runs SSP0 with.
 */
#define PUJJO_SSP0_MCLK         19200000
#define PUJJO_SSP0_BCLK         2400000
#define PUJJO_SSP0_RATE         48000
#define PUJJO_SSP0_SLOTS        2
#define PUJJO_SSP0_SLOT_WIDTH   25
#define PUJJO_SSP0_SLOT_MASK    0x3
#define PUJJO_SSP0_VALID_BITS   24      /* rt5682 data length: 16/20/24/32 */

static VOID CsAudioCallbackFunction(
    CCsAudioSofHW* hw,
    CsAudioArg* arg,
    PVOID Argument2
)
{
    if (!hw || !arg) {
        return;
    }

    if (Argument2 == &hw->CsAudioArg2) {
        return;     /* our own notification */
    }

    CsAudioArg localArg;
    RtlZeroMemory(&localArg, sizeof(CsAudioArg));
    RtlCopyMemory(&localArg, arg, min(arg->argSz, sizeof(CsAudioArg)));

    hw->CSAudioAPICalled(localArg);
}

NTSTATUS CCsAudioSofHW::CSAudioAPIInit()
{
    NTSTATUS status;

    UNICODE_STRING CSAudioCallbackAPI;
    RtlInitUnicodeString(&CSAudioCallbackAPI, L"\\CallBack\\CsAudioCallbackAPI");

    OBJECT_ATTRIBUTES attributes;
    InitializeObjectAttributes(
        &attributes,
        &CSAudioCallbackAPI,
        OBJ_KERNEL_HANDLE | OBJ_OPENIF | OBJ_CASE_INSENSITIVE | OBJ_PERMANENT,
        NULL,
        NULL
    );

    status = ExCreateCallback(&this->m_CsAudioAPICallback, &attributes, TRUE, TRUE);
    if (!NT_SUCCESS(status)) {
        return status;
    }

    this->m_CsAudioAPICallbackObj = ExRegisterCallback(
        this->m_CsAudioAPICallback,
        (PCALLBACK_FUNCTION)CsAudioCallbackFunction,
        this
    );

    if (!this->m_CsAudioAPICallbackObj) {
        return STATUS_NO_CALLBACK_ACTIVE;
    }

    // Ask codec drivers that loaded before us to announce themselves; each
    // answer arrives in CSAudioAPICalled() as a Register request.
    CsAudioArg arg;
    RtlZeroMemory(&arg, sizeof(CsAudioArg));
    arg.argSz = sizeof(CsAudioArg);
    arg.endpointType = CSAudioEndpointTypeDSP;
    arg.endpointRequest = CSAudioEndpointRegister;
    ExNotifyCallback(this->m_CsAudioAPICallback, &arg, &CsAudioArg2);

    return STATUS_SUCCESS;
}

NTSTATUS CCsAudioSofHW::CSAudioAPIDeinit()
{
    if (this->m_CsAudioAPICallbackObj) {
        ExUnregisterCallback(this->m_CsAudioAPICallbackObj);
        this->m_CsAudioAPICallbackObj = NULL;
    }

    if (this->m_CsAudioAPICallback) {
        ObfDereferenceObject(this->m_CsAudioAPICallback);
        this->m_CsAudioAPICallback = NULL;
    }

    return STATUS_SUCCESS;
}

/*
 * A codec driver registered an endpoint (at its start, or in answer to our
 * DSP Register broadcast). Put it in the stopped state, as upstream does,
 * and give the headset codec the SSP0 clocking it needs for its PLL.
 */
void CCsAudioSofHW::CSAudioAPICalled(CsAudioArg arg)
{
    if (arg.endpointRequest != CSAudioEndpointRegister ||
        arg.endpointType == CSAudioEndpointTypeDSP) {
        return;
    }

    CsAudioArg newArg;
    RtlZeroMemory(&newArg, sizeof(CsAudioArg));
    newArg.argSz = sizeof(CsAudioArg);
    newArg.endpointType = arg.endpointType;
    newArg.endpointRequest = CSAudioEndpointStop;
    ExNotifyCallback(this->m_CsAudioAPICallback, &newArg, &CsAudioArg2);

    if (arg.endpointType == CSAudioEndpointTypeHeadphone ||
        arg.endpointType == CSAudioEndpointTypeMicJack) {
        SendI2SParameters(arg.endpointType);
    }
}

/*
 * Tell rt5682.sys how SSP0 is clocked. It reprograms PLL1 (19.2 MHz MCLK ->
 * 24.576 MHz SYSCLK), its SYSCLK source and its I2S data length, and keeps
 * the values for its own D0 re-initialisation. Callers make sure SSP0 is
 * idle, because a PLL change under a running stream glitches it.
 */
void CCsAudioSofHW::SendI2SParameters(_In_ CSAudioEndpointType endpointType)
{
    if (!m_CsAudioAPICallback) {
        return;
    }
    if (KeGetCurrentIrql() != PASSIVE_LEVEL) {
        // rt5682.sys writes its registers synchronously over I2C here.
        DPF(D_TERSE, ("[CSAudio] I2S parameters skipped at IRQL %u\n", (ULONG)KeGetCurrentIrql()));
        return;
    }

    CsAudioArg arg;
    RtlZeroMemory(&arg, sizeof(CsAudioArg));
    arg.argSz = sizeof(CsAudioArg);
    arg.endpointType = endpointType;
    arg.endpointRequest = CSAudioEndpointI2SParameters;
    arg.i2sParameters.version = 1;
    arg.i2sParameters.mclk = PUJJO_SSP0_MCLK;
    arg.i2sParameters.bclk_rate = PUJJO_SSP0_BCLK;
    arg.i2sParameters.frequency = PUJJO_SSP0_RATE;
    arg.i2sParameters.tdm_slots = PUJJO_SSP0_SLOTS;
    arg.i2sParameters.tdm_slot_width = PUJJO_SSP0_SLOT_WIDTH;
    arg.i2sParameters.rx_slots = PUJJO_SSP0_SLOT_MASK;
    arg.i2sParameters.tx_slots = PUJJO_SSP0_SLOT_MASK;
    arg.i2sParameters.valid_bits = PUJJO_SSP0_VALID_BITS;
    ExNotifyCallback(m_CsAudioAPICallback, &arg, &CsAudioArg2);
}
