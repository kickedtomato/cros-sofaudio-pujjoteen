/* Vendored from Linux include/sound/sof/dai-amd.h by tools/vendor_sof_headers.py.
 * Used under the BSD-3-Clause option of its dual license. */
#include "sof/compat.h"
#pragma pack(push, 1)
/* SPDX-License-Identifier: (GPL-2.0-only OR BSD-3-Clause) */
/*
 * This file is provided under a dual BSD/GPLv2 license. When using or
 * redistributing this file, you may do so under either license.
 *
 * Copyright(c) 2021 Advanced Micro Devices, Inc.. All rights reserved.
 */

#ifndef __INCLUDE_SOUND_SOF_DAI_AMD_H__
#define __INCLUDE_SOUND_SOF_DAI_AMD_H__

#include "sof/header.h"

/* ACP Configuration Request - SOF_IPC_DAI_AMD_CONFIG */
struct sof_ipc_dai_acp_params {
	struct sof_ipc_hdr hdr;

	uint32_t fsync_rate;    /* FSYNC frequency in Hz */
	uint32_t tdm_slots;
	uint32_t tdm_mode;
	uint32_t format;
};

/* ACPDMIC Configuration Request - SOF_IPC_DAI_AMD_CONFIG */
struct sof_ipc_dai_acpdmic_params {
	uint32_t pdm_rate;
	uint32_t pdm_ch;
};

/* ACP_SDW Configuration Request - SOF_IPC_DAI_AMD_SDW_CONFIG */
struct sof_ipc_dai_acp_sdw_params {
	struct sof_ipc_hdr hdr;
	u32 rate;
	u32 channels;
};

#endif
#pragma pack(pop)
