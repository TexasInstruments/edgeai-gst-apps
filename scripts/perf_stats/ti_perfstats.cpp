/*
 *  Copyright (C) 2021 Texas Instruments Incorporated - http://www.ti.com/
 *
 *  Redistribution and use in source and binary forms, with or without
 *  modification, are permitted provided that the following conditions
 *  are met:
 *
 *    Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *
 *    Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the
 *    distribution.
 *
 *    Neither the name of Texas Instruments Incorporated nor the names of
 *    its contributors may be used to endorse or promote products derived
 *    from this software without specific prior written permission.
 *
 *  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 *  "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 *  LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 *  A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 *  OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 *  SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 *  LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 *  DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 *  THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 *  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 *  OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

/* Standard headers. */
#include <signal.h>
#include <getopt.h>
#include <thread>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern "C" {

/* Module headers. */
#if defined(SOC_J721E) || defined(SOC_J721S2) || defined(SOC_J784S4) || defined(SOC_J722S) || defined(SOC_AM62A)
#include <utils/app_init/include/app_init.h>
#include <utils/perf_stats/include/app_perf_stats.h>
#include <utils/ipc/include/app_ipc.h>
#endif
#include <edgeai_perf_stats_utils.h>

}

#define SLEEP_INTERVAL 1000

static bool gStop = false;
static std::thread gDispThreadId;

static void sigHandler(int32_t sig)
{
    gStop = true;
}

void displayThread()
{

    int32_t status=0;
#if defined(SOC_J721E) || defined(SOC_J721S2) || defined(SOC_J784S4) || defined(SOC_J722S) || defined(SOC_AM62A)
    app_perf_stats_cpu_load_t cpu_load;
#else
    perfStatsCpuLoad cpu_load;
    perfStatsCpuStatsInit(&cpu_load);
#endif

    perfStatsSOCTemp soc_temp;
    perfStatsSocTempInit(&soc_temp);

    while (!gStop)
    {
        system("clear");

#if defined(SOC_J721E) || defined(SOC_J721S2) || defined(SOC_J784S4) || defined(SOC_J722S) || defined(SOC_AM62A)
        printf("Summary of CPU load,\n");
        printf("====================\n\n");

        for(int cpu_id=0; cpu_id<APP_IPC_CPU_MAX; cpu_id++) {
            if (appIpcIsCpuEnabled(cpu_id)) {
                status = appPerfStatsCpuLoadGet(cpu_id, &cpu_load);
                if(status==0)
                {
                    appPerfStatsCpuLoadPrint(cpu_id, &cpu_load);
                }
            }
        }


        appPerfStatsHwaLoadPrintAll();
        appPerfStatsResetAll();
#else
        perfStatsCpuStatsPrint(&cpu_load);
        perfStatsResetCpuLoadCalc(&cpu_load);
#endif
        perfStatsDdrStatsPrintAll();
        perfStatsResetDdrLoadCalcAll();

        perfStatsSocTempGet(&soc_temp);

        if (NUM_THERMAL_ZONE > 0)
        {
            printf("\n");
            printf("SoC temperature statistics\n");
            printf("==========================\n");
            printf("\n");
        }

        for (uint32_t i = 0; i < NUM_THERMAL_ZONE; i++)
        {
            printf("%s:\t%0.2f degree Celsius\n",
                  soc_temp.thermal_zone_name[i], soc_temp.thermal_zone_temp[i]);
        }

        std::this_thread::sleep_for(std::chrono::milliseconds(SLEEP_INTERVAL));
    }

}

int main()
{
    int32_t status = 0;

    /* Register SIGINT handler. */
    signal(SIGINT, sigHandler);

#if defined(SOC_J721E) || defined(SOC_J721S2) || defined(SOC_J784S4) || defined(SOC_J722S) || defined(SOC_AM62A)
    /* Initialize the system. */
    status = appInit();

    if(status < 0)
    {
        perror("appInit failed");
        return status;
    }
#endif

    gDispThreadId = std::thread([]{displayThread();});

    gDispThreadId.join();

#if defined(SOC_J721E) || defined(SOC_J721S2) || defined(SOC_J784S4) || defined(SOC_J722S) || defined(SOC_AM62A)
    printf("CALLING DE-INIT.\n");

    /* De-Initialize the system. */
    status = appDeInit();
#endif

    return status;
}
