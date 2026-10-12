#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Print a FreeRTOS task table every period_ms (lines starting with "TS|") from a low priority
 * task. Neovim (Space ET) reads them from the monitor log and shows a live table.
 */
void nvim_task_stats_start(uint32_t period_ms);

/** Print the task table once, now. */
void nvim_task_stats_print(void);

#ifdef __cplusplus
}
#endif
