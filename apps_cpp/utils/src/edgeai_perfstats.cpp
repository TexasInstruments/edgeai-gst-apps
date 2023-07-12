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
