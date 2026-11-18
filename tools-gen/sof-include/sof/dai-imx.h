/* Vendored from Linux include/sound/sof/dai-imx.h by tools/vendor_sof_headers.py.
 * Used under the BSD-3-Clause option of its dual license. */
#include "sof/compat.h"
#pragma pack(push, 1)
/* SPDX-License-Identifier: (GPL-2.0-only OR BSD-3-Clause) */
/*
 * Copyright 2019 NXP
 *
 * Author: Daniel Baluta <daniel.baluta@nxp.com>
 */

#ifndef __INCLUDE_SOUND_SOF_DAI_IMX_H__
#define __INCLUDE_SOUND_SOF_DAI_IMX_H__

#include "sof/header.h"

/* ESAI Configuration Request - SOF_IPC_DAI_ESAI_CONFIG */
struct sof_ipc_dai_esai_params {
	struct sof_ipc_hdr hdr;

	/* MCLK */
	uint16_t reserved1;
	uint16_t mclk_id;
	uint32_t mclk_direction;

	uint32_t mclk_rate;	/* MCLK frequency in Hz */
	uint32_t fsync_rate;	/* FSYNC frequency in Hz */
	uint32_t bclk_rate;	/* BCLK frequency in Hz */

	/* TDM */
	uint32_t tdm_slots;
	uint32_t rx_slots;
	uint32_t tx_slots;
	uint16_t tdm_slot_width;
	uint16_t reserved2;	/* alignment */
};

/* SAI Configuration Request - SOF_IPC_DAI_SAI_CONFIG */
struct sof_ipc_dai_sai_params {
	struct sof_ipc_hdr hdr;

	/* MCLK */
	uint16_t reserved1;
	uint16_t mclk_id;
	uint32_t mclk_direction;

	uint32_t mclk_rate;	/* MCLK frequency in Hz */
	uint32_t fsync_rate;	/* FSYNC frequency in Hz */
	uint32_t bclk_rate;	/* BCLK frequency in Hz */

	/* TDM */
	uint32_t tdm_slots;
	uint32_t rx_slots;
	uint32_t tx_slots;
	uint16_t tdm_slot_width;
	uint16_t reserved2;	/* alignment */
};

/* MICFIL Configuration Request - SOF_IPC_DAI_MICFIL_CONFIG */
struct sof_ipc_dai_micfil_params {
	uint32_t pdm_rate;
	uint32_t pdm_ch;
};

#endif
#pragma pack(pop)
