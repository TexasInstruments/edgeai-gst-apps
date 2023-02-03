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

#ifndef _TI_EDGEAI_UTILS_H_
#define _TI_EDGEAI_UTILS_H_

/* Standard headers. */
#include <string>
#include <thread>

/* Third-party headers. */
#include <yaml-cpp/yaml.h>

/* Module headers. */
#include <edgeai_dl_inferer/ti_dl_inferer.h>
#include <common/include/post_process_image.h>
#include <common/include/pre_process_image.h>
#include <common/include/edgeai_gst_helper.h>
#include <common/include/edgeai_gstelementmap.h>

#define MAX_SCALE_FACTOR           4

using namespace std;

namespace ti::edgeai::common
{
    using namespace ti::dl_inferer;

    /* Forward declaration. */
    struct StatEntry;

    using MapStatEntry   = map<uint32_t, StatEntry>;

    /** Statistics database. */
    /**
     * \brief Class for holding the performance information during the DL
     *        model inference runs.
     *
     * \ingroup group_edgeai_common
     */
    class Statistics
    {
        public:
            /** Vector of ststistics objects. */
            static MapStatEntry m_stats;

            /** Flag to control curses report thread */
            static bool m_printCurses;

            /** Flag to control STDOUT prints if curses is disabled*/
            static bool m_printStdout;

            /** Reporting thread identifier. */
            static thread m_reportingThread;

            /** Function for registering the model to track statistics specific
             * to this model.
             *
             * @param key Identifier for retrieving the appropriate record.
             * @param inputName Name String representation of the input
             * @param modelType Type of the model
             * @param modelName Name of the model to start tracking statistics
             *                  for.
             */
            static int32_t addEntry(uint32_t        key,
                                    const string   &inputName,
                                    const string   &modelType,
                                    const string   &modelName);

            /**
             * Utility Function for reporting processing time measurements
             * It will update the last average with the new sample value
             *
             * @param key Idetfier for retrieving the appropriate record.
             * @param tag unique string to represent the processing time of certain operation
             * @param value processing time measured in milliseconds
             */
            static int32_t reportProcTime(uint32_t      key,
                                          const string &tag,
                                          float         value);

            /**
             * Utility Function for reporting performence metrics
             * It will update the last average with the new sample value
             *
             * @param key Idetfier for retrieving the appropriate record.
             * @param tag unique string to represent each metric
             * @param unit unit of measurment
             * @param value measured value
             */
            static int32_t reportMetric(uint32_t        key,
                                        const string   &tag,
                                        const string   &unit,
                                        float           value);
            /**
             * Thread callback function which prints a table of reported processing times
             * using ncurses library.
             *
             * The number of columns displayed is dynamically computed based on the length
             * of the modelpath.
             */
             static void reportingLoop(const string &demoName);
            /**
             * Control if the processing time should be printed to the console or shown
             * in a nice looking, table using ncurses library. If you use the curses method,
             * only the processing time is shown and other debug prints will not be visible.
             * If you do not use the curses library, all the processing time are simply
             * printed to the console. It's a choice between debug prints v/s demo appearance.
             *
             * @param state passing true will start the curses thread
             * @param verbose Verbose flag for controlling the output prints to the screen
             * @param demoName Demo name to display
             */
            static void enableCursesReport(bool            state,
                                           bool            verbose,
                                           const string   &demoName);

            /**
             * Disables the curses process printing to the output, if enabled.
             */
            static void disableCursesReport();
    };

    /**
    * Function to make scalerElements for a flow.
    * @param preProcCfg        PreProcessImage Config Struct
    * @param preProcElements   Vector to store scalerElements
    * @param isMultiSrc        If scaler is multisrc (like tiovxmultiscaler)
    */
    void getPreProcScalerElements(const PreprocessImageConfig   *preProcCfg,
                                  std::vector<GstElement *>     &preProcElements,
                                  bool                           isMultiSrc);

    /**
        * Updates the vector preProcElements with the gst videoscale and videobox
        * command strings based on the pre-processor configuration 'config'.
        * The video scale element is always generated but the videobox string
        * will be conditionally generated only if any of the crop
        * (top/bottom, left/right) are non-zero.
        *
        * @param preProcCfg        PreProcessImage Config Struct
        * @param preProcElements  vector to store generated elements
        */
    void getPreProcElements(const PreprocessImageConfig *preProcCfg,
                            std::vector<GstElement *>   &preProcElements);

    /**
     * Helper function to convert string to fraction
     *
     * @param num numeric integer or decimal string
     *
     * @return string representation of fraction (Ex: "1/2")
     */
    const std::string to_fraction(std::string& num);

    /**
     * Helper function to check if string is numeric
     *
     * @param s string to be checked
     *
     * @return true if string is purely numeric, else false
     */
    template<typename Numeric> bool _is_number(const std::string& s);

} // namespace ti::edgeai::common

#endif /* _TI_EDGEAI_UTILS_H_ */

