/* <ipc/control.h> for the host generators.
 *
 * Linux sof/control.h (vendored in sof-include) declares sof_manifest and
 * sof_ipc_ctrl_data with flexible arrays inside arrays and unions, which
 * MSVC's C compiler rejects (C2233). The generators only need the channel
 * value form of sof_ipc_ctrl_data, so it is declared here with the same
 * packed layout as the firmware's struct (checked below). */
#pragma once
#include "sof/header.h"

enum sof_ipc_ctrl_type {
	SOF_CTRL_TYPE_VALUE_CHAN_GET = 0,
	SOF_CTRL_TYPE_VALUE_CHAN_SET,
	SOF_CTRL_TYPE_VALUE_COMP_GET,
	SOF_CTRL_TYPE_VALUE_COMP_SET,
	SOF_CTRL_TYPE_DATA_GET,
	SOF_CTRL_TYPE_DATA_SET,
};

enum sof_ipc_ctrl_cmd {
	SOF_CTRL_CMD_VOLUME = 0,
	SOF_CTRL_CMD_ENUM,
	SOF_CTRL_CMD_SWITCH,
	SOF_CTRL_CMD_BINARY,
};

#pragma pack(push, 1)
struct sof_ipc_ctrl_value_chan {
	uint32_t channel;
	uint32_t value;
};

struct sof_ipc_ctrl_data {
	struct sof_ipc_reply rhdr;
	uint32_t comp_id;
	uint32_t type;
	uint32_t cmd;
	uint32_t index;
	struct sof_ipc_host_buffer buffer;
	uint32_t num_elems;
	uint32_t elems_remaining;
	uint32_t msg_index;
	uint32_t reserved[6];
	struct sof_ipc_ctrl_value_chan chanv[];
};
#pragma pack(pop)

/* rhdr 12 + 4 words + host_buffer 28 + 3 words + reserved 24 */
typedef char sof_ipc_ctrl_data_size_check[sizeof(struct sof_ipc_ctrl_data) == 92 ? 1 : -1];
