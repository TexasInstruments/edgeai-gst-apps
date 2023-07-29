/* Standard headers. */
#include <filesystem>
#include <thread>
#include <unistd.h>

/* Module headers. */
#include <utils/include/edgeai_perfstats.h>

/*
 * Outputs log files containing real-time performance metrics.
 * Log files generated with performance metrics averaged over some fixed time interval.
 */

// bool ti::edgeai::utils::printstats = false;
namespace ti::utils
{
    static bool                printstats;
    static thread              perfThreadId;
    static const char         *sub_dir_name{nullptr};
#if not defined(SOC_AM62X)
    static app_perf_point_t    perf;
#endif

    static void perfThread()
    {
#if not defined(SOC_AM62X)
        app_perf_point_t   *perf_arr[1];
        int32_t             logNumber = 0;
        const int32_t       save_history = 16;      // Defines how many log files to keep at a time
        std::string         base_dir = "../perf_logs";

#if defined(SOC_J721E)
        /* open sysfs files for reading temperature data*/
        FILE *cpuTempFd  = fopen("/sys/class/thermal/thermal_zone1/temp", "rb");
        FILE *wkupTempFd = fopen("/sys/class/thermal/thermal_zone0/temp", "rb");
        FILE *c7xTempFd  = fopen("/sys/class/thermal/thermal_zone2/temp", "rb");
        FILE *gpuTempFd  = fopen("/sys/class/thermal/thermal_zone3/temp", "rb");
        FILE *r5fTempFd  = fopen("/sys/class/thermal/thermal_zone4/temp", "rb");
        uint32_t cpuTemp, wkupTemp, c7xTemp, gpuTemp, r5fTemp, ret=0;
#endif

        if (sub_dir_name)
        {
            base_dir += string("/") + sub_dir_name;
        }

        std::filesystem::remove_all(base_dir);
        std::filesystem::create_directories(base_dir);

        while (printstats)
        {
            perf_arr[0] = &perf;

            std::string file_name = "Log" + std::to_string(logNumber);

            FILE *fp = appPerfStatsExportOpenFile(base_dir.c_str(), file_name.c_str());

            if (NULL != fp)
            {
                ::appPerfStatsExportAll(fp, perf_arr, 1);

#if defined(SOC_J721E)
                /* print temperature stats*/
                if (NULL != cpuTempFd ||
                    NULL != wkupTempFd ||
                    NULL != c7xTempFd ||
                    NULL != gpuTempFd ||
                    NULL != r5fTempFd)
                {
                    fprintf(fp,"\n");
                    fprintf(fp,"# Temperature statistics\n");
                    fprintf(fp,"\n");
                    fprintf(fp,"ZONE      | TEMPERATURE\n");
                    fprintf(fp,"----------|--------------\n");
                }

                /* Read temperature data*/
                if (NULL != cpuTempFd)
                {
                    ret = fscanf(cpuTempFd, "%u", &cpuTemp);
                    if (ret != 1)
                        printf("[ERROR]Failed to read cpuTemp\n");
                    rewind(cpuTempFd);
                    fflush(cpuTempFd);
                    fprintf(fp,"CPU   |   %0.2f Celsius\n",float(cpuTemp)/1000);
                }
                if (NULL != wkupTempFd)
                {
                    ret = fscanf(wkupTempFd, "%u", &wkupTemp);
                    if (ret != 1)
                        printf("[ERROR]Failed to read wkupTemp\n");
                    rewind(wkupTempFd);
                    fflush(wkupTempFd);
                    fprintf(fp,"WKUP  |   %0.2f Celsius\n",float(wkupTemp)/1000);
                }
                if (NULL != c7xTempFd)
                {
                    ret = fscanf(c7xTempFd, "%u", &c7xTemp);
                    if (ret != 1)
                        printf("[ERROR]Failed to read c7xTemp\n");
                    rewind(c7xTempFd);
                    fflush(c7xTempFd);
                    fprintf(fp,"C7X   |   %0.2f Celsius\n",float(c7xTemp)/1000);
                }
                if (NULL != gpuTempFd)
                {
                    ret = fscanf(gpuTempFd, "%u", &gpuTemp);
                    if (ret != 1)
                        printf("[ERROR]Failed to read gpuTemp\n");
                    rewind(gpuTempFd);
                    fflush(gpuTempFd);
                    fprintf(fp,"GPU   |   %0.2f Celsius\n",float(gpuTemp)/1000);
                }
                if (NULL != r5fTempFd)
                {
                    ret = fscanf(r5fTempFd, "%u", &r5fTemp);
                    if (ret != 1)
                        printf("[ERROR]Failed to read r5fTemp\n");
                    rewind(r5fTempFd);
                    fflush(r5fTempFd);
                    fprintf(fp,"R5F   |   %0.2f Celsius\n",float(r5fTemp)/1000);
                }
#endif
                ::appPerfStatsExportCloseFile(fp);
                ::appPerfStatsResetAll();
            }
            else
            {
                printf("fp is null\n");
            }

            /* Increment the log file number. */
            logNumber = (logNumber + 1) % save_history;

            /* Log files generated every 2s */
            this_thread::sleep_for(chrono::milliseconds(2000));
        }

#if defined(SOC_J721E)
    /* close fds*/
    if (NULL != cpuTempFd)
    {
        fclose(cpuTempFd);
    }
    if (NULL != wkupTempFd)
    {
        fclose(wkupTempFd);
    }
    if (NULL != c7xTempFd)
    {
        fclose(c7xTempFd);
    }
    if (NULL != gpuTempFd)
    {
        fclose(gpuTempFd);
    }
    if (NULL != r5fTempFd)
    {
        fclose(r5fTempFd);
    }
#endif
#endif
    }

    // Starts thread to log performance files
    void enableReport(bool state, const char *dir_name)
    {
        printstats = state;
        sub_dir_name = dir_name;
        if (state)
        {
            perfThreadId = thread(perfThread);
        }
    }

    // When called, start recording and averaging performance metrics
    void startRec()
    {
#if not defined(SOC_AM62X)
        appPerfPointBegin(&perf);
#endif
    }

    // When called, pause recording and averaging performance metrics
    void endRec()
    {
#if not defined(SOC_AM62X)
        appPerfPointEnd(&perf);
#endif
    }

    void waitForPerfThreadExit()
    {
        if (perfThreadId.joinable())
        {
            perfThreadId.join();
        }
    }

    // Stop performance logs
    void disableReport()
    {
        printstats = false;
        sleep(1);
    }
}
