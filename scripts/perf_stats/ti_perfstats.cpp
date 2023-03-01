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
#include <stdlib.h>
#include <string.h>

extern "C" {

/* Module headers. */
#include <utils/app_init/include/app_init.h>
#include <utils/perf_stats/include/app_perf_stats.h>
#include <utils/ipc/include/app_ipc.h>

}

static bool gStop = false;
static std::thread gDispThreadId;

static void sigHandler(int32_t sig)
{
    gStop = true;
}

void displayThread()
{

    int32_t status=0;
    app_perf_stats_cpu_load_t cpu_load;

#if defined(SOC_J721E)
    /* open sysfs files for reading temperature data*/
    FILE *cpuTempFd  = fopen("/sys/class/thermal/thermal_zone1/temp", "rb");
    FILE *wkupTempFd = fopen("/sys/class/thermal/thermal_zone0/temp", "rb");
    FILE *c7xTempFd  = fopen("/sys/class/thermal/thermal_zone2/temp", "rb");
    FILE *gpuTempFd  = fopen("/sys/class/thermal/thermal_zone3/temp", "rb");
    FILE *r5fTempFd  = fopen("/sys/class/thermal/thermal_zone4/temp", "rb");
    uint32_t cpuTemp, wkupTemp, c7xTemp, gpuTemp, r5fTemp, ret=0;
#endif

    while (!gStop)
    {
        system("clear");

        printf("Summary of CPU load,\n");
        printf("====================\n\n");

        for(int cpu_id=0; cpu_id<APP_IPC_CPU_MAX; cpu_id++) {
            if (strstr(appIpcGetCpuName(cpu_id), "mcu") != NULL) {
                continue;
            }
            status = appPerfStatsCpuLoadGet(cpu_id, &cpu_load);
            if(status==0)
            {
                appPerfStatsCpuLoadPrint(cpu_id, &cpu_load);
            }
        }
        appPerfStatsHwaLoadPrintAll();
        appPerfStatsDdrStatsPrintAll();
        appPerfStatsResetAll();

#if defined(SOC_J721E)
        /* Read temperature data*/
        ret = fscanf(cpuTempFd, "%u", &cpuTemp);
        if (ret != 1)
            printf("[ERROR]Failed to read cpuTemp\n");
        rewind(cpuTempFd);
        fflush(cpuTempFd);
        ret = fscanf(wkupTempFd, "%u", &wkupTemp);
        if (ret != 1)
            printf("[ERROR]Failed to read wkupTemp\n");
        rewind(wkupTempFd);
        fflush(wkupTempFd);
        ret = fscanf(c7xTempFd, "%u", &c7xTemp);
        if (ret != 1)
            printf("[ERROR]Failed to read c7xTemp\n");
        rewind(c7xTempFd);
        fflush(c7xTempFd);
        ret = fscanf(gpuTempFd, "%u", &gpuTemp);
        if (ret != 1)
            printf("[ERROR]Failed to read gpuTemp\n");
        rewind(gpuTempFd);
        fflush(gpuTempFd);
        ret = fscanf(r5fTempFd, "%u", &r5fTemp);
        if (ret != 1)
            printf("[ERROR]Failed to read r5fTemp\n");
        rewind(r5fTempFd);
        fflush(r5fTempFd);

        /* print temperature stats*/
        printf("\n");
        printf("SoC temperature statistics\n");
        printf("==========================\n");
        printf("\n");
        printf("CPU:\t%0.2f degree Celsius\n", float(cpuTemp)/1000);
        printf("WKUP:\t%0.2f degree Celsius\n", float(wkupTemp)/1000);
        printf("C7X:\t%0.2f degree Celsius\n", float(c7xTemp)/1000);
        printf("GPU:\t%0.2f degree Celsius\n", float(gpuTemp)/1000);
        printf("R5F:\t%0.2f degree Celsius\n", float(r5fTemp)/1000);
#endif
        std::this_thread::sleep_for(std::chrono::milliseconds(2000));
    }

#if defined(SOC_J721E)
    /* close fds*/
    fclose(cpuTempFd);
    fclose(wkupTempFd);
    fclose(c7xTempFd);
    fclose(gpuTempFd);
    fclose(r5fTempFd);
#endif
}

int main()
{
    int32_t status = 0;

    /* Register SIGINT handler. */
    signal(SIGINT, sigHandler);

    /* Initialize the system. */
    status = appInit();

    if(status < 0)
    {
        perror("appInit failed");
        return status;
    }

    gDispThreadId = std::thread([]{displayThread();});

    gDispThreadId.join();

    printf("CALLING DE-INIT.\n");

    /* De-Initialize the system. */
    status = appDeInit();

    return status;
}
