#include <stdio.h>
#include <stdlib.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/idf_additions.h"
#include "esp_timer.h"
#include "nvim_task_stats.h"

/* Run time counters from the previous print, so CPU % is for the last period, not since boot */
#define MAX_TASKS 64
typedef struct {
    TaskHandle_t handle;
    uint64_t run_time;
} previous_t;

static previous_t s_prev[MAX_TASKS];
static int s_prev_count;
static uint64_t s_prev_total;

static char state_char(eTaskState state)
{
    switch (state) {
    case eRunning: return 'X';
    case eReady: return 'R';
    case eBlocked: return 'B';
    case eSuspended: return 'S';
    case eDeleted: return 'D';
    default: return '?';
    }
}

static uint64_t previous_run_time(TaskHandle_t handle)
{
    for (int i = 0; i < s_prev_count; i++) {
        if (s_prev[i].handle == handle) {
            return s_prev[i].run_time;
        }
    }
    return 0;
}

void nvim_task_stats_print(void)
{
    UBaseType_t count = uxTaskGetNumberOfTasks();
    TaskStatus_t *tasks = malloc(count * sizeof(TaskStatus_t));
    if (tasks == NULL) {
        return;
    }
    configRUN_TIME_COUNTER_TYPE total = 0;
    count = uxTaskGetSystemState(tasks, count, &total);
    uint64_t period_total = (uint64_t)total - s_prev_total;

    printf("TS|BEGIN|%lld|%d\n", esp_timer_get_time() / 1000, configNUMBER_OF_CORES);
    for (UBaseType_t i = 0; i < count; i++) {
        uint64_t run = (uint64_t)tasks[i].ulRunTimeCounter;
        uint64_t delta = run - previous_run_time(tasks[i].xHandle);
        /* % of one core: on dual core systems the sum can reach 200 */
        double cpu = period_total ? (double)delta * 100.0 / (double)period_total : 0.0;
        BaseType_t core = xTaskGetCoreID(tasks[i].xHandle);
        printf("TS|%s|%c|%u|%u|%.1f|%d\n", tasks[i].pcTaskName, state_char(tasks[i].eCurrentState),
               (unsigned)tasks[i].uxCurrentPriority, (unsigned)tasks[i].usStackHighWaterMark, cpu,
               core == tskNO_AFFINITY ? -1 : (int)core);
    }
    printf("TS|END\n");

    s_prev_count = 0;
    for (UBaseType_t i = 0; i < count && s_prev_count < MAX_TASKS; i++) {
        s_prev[s_prev_count++] = (previous_t){tasks[i].xHandle, (uint64_t)tasks[i].ulRunTimeCounter};
    }
    s_prev_total = (uint64_t)total;
    free(tasks);
}

static void stats_task(void *arg)
{
    uint32_t period_ms = (uint32_t)(uintptr_t)arg;
    while (1) {
        nvim_task_stats_print();
        vTaskDelay(pdMS_TO_TICKS(period_ms));
    }
}

void nvim_task_stats_start(uint32_t period_ms)
{
    xTaskCreate(stats_task, "nvim_stats", 3072, (void *)(uintptr_t)period_ms, tskIDLE_PRIORITY + 1, NULL);
}
