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
#include <algorithm>
#include <filesystem>
#include <thread>
#include <unistd.h>
#include <ncurses.h>
#include <cmath>

/* Module headers. */
#include <utils/include/ti_logger.h>
#include <common/include/edgeai_utils.h>

namespace ti::edgeai::common
{
using namespace ti::utils;
using namespace ti::dl_inferer;

 /** target index for dlpreproc. */
uint32_t targetIdx = 0;

// Please keep the following array and map consistent in terms of the
// number anf names of the elements
const string gStatKeys[] = {"dl-inference"};
const string gMetricKeys[] = {"total time", "framerate"};

/**
 * Hold the processing time of different operations
 */
struct ProcTime
{
    float       average{0.0f};
    uint64_t    samples{0};
};

struct Metrics
{
    float       value{0.0f};
    string      unit{"ms"};
    uint64_t    samples{0};
};

using MapProcTime = map<string, ProcTime>;
using MapMetrics  = map<string, Metrics>;

struct StatEntry
{
    /** Name of the input source. */
    string      m_inputName;

    /** Type of the model.
     * - classification
     * - detection
     * = segmentation
     */
    string      m_modelType;

    /** Name of the model. */
    string      m_modelName;

    /** Processing time details. */
    MapProcTime m_proc{};

    /** Metrics context. */
    MapMetrics  m_metrics{};
};

/* Initialize the status. */
MapStatEntry Statistics::m_stats{};
bool Statistics::m_printCurses = false;
bool Statistics::m_printStdout = !Statistics::m_printCurses;
thread Statistics::m_reportingThread;

int32_t Statistics::addEntry(uint32_t       key,
                             const string  &inputName,
                             const string  &modelType,
                             const string  &modelPath)
{
    int32_t status = 0;

    /* Check if an entry for this key already exists. */
    if (m_stats.find(key) != m_stats.end())
    {
        LOG_ERROR("An entry for the key [%d] already exists.\n");
        status = -1;
    }

    if (status == 0)
    {
        string      fName = modelPath;
        StatEntry   s;

        /* Delete the trailing '/' if present. This will lead to an empty
         * string in the call to filename() below, if not deleted.
         */
        if (fName.back() == '/')
        {
            fName.pop_back();
        }

        s.m_modelName = "Model Name:   " + string(filesystem::path(fName).filename());
        s.m_modelType = "Model Type:   " + modelType;
        s.m_inputName = "Input Source: " + inputName;

        /* Initialize the maps. */
        for (auto const &tag : gStatKeys)
        {
            s.m_proc[tag] = ProcTime();
        }

        for (auto const &tag : gMetricKeys)
        {
            s.m_metrics[tag] = Metrics();
        }

        m_stats[key] = s;
    }

    return status;
}

int32_t Statistics::reportProcTime(uint32_t         key,
                                   const string    &tag,
                                   float            value)
{
    StatEntry  *e;
    ProcTime   *p;
    int32_t     status = 0;

    if (m_stats.find(key) == m_stats.end())
    {
        LOG_ERROR("Key [%d] not found.\n", key);
        status = -1;
    }

    if (status == 0)
    {
        e = &m_stats[key];
        p = &e->m_proc[tag];

        p->average = (p->average * p->samples + value)/(p->samples + 1);
        p->samples++;

        if (m_printStdout)
        {
            printf("[UTILS] [%s] Time for '%s': %5.2f ms (avg %5.2f ms)\n",
                    e->m_modelName.c_str(),
                    tag.c_str(), value, p->average);
        }
    }

    return status;
}

int32_t Statistics::reportMetric(uint32_t       key,
                                 const string  &tag,
                                 const string  &unit,
                                 float          value)
{
    StatEntry  *e;
    Metrics    *m;
    int32_t     status = 0;

    if (m_stats.find(key) == m_stats.end())
    {
        LOG_ERROR("Key [%d] not found.\n", key);
        status = -1;
    }

    if (status == 0)
    {
        e = &m_stats[key];
        m = &e->m_metrics[tag];

        m->value = (m->value * m->samples + value)/(m->samples + 1);
        m->unit  = unit;

        m->samples++;

        if (m_printStdout)
        {
            printf("[UTILS] [%s] Metric '%s': %5.2f %s\n",
                    e->m_modelName.c_str(),
                    tag.c_str(), m->value, m->unit.c_str());
        }
    }

    return status;
}

static inline void drawDataRow(int32_t     &row,
                               const char  *title,
                               float        data1,
                               const char  *data1Unit,
                               int32_t      data2,
                               int32_t      lastPos)
{
    mvprintw(row, 1, "| %-29s:", title);
    attron(A_BOLD);
    mvprintw(row, 34, "%8.2f %s", data1, data1Unit);
    attroff(A_BOLD);
    mvprintw(row, 46, " from %5d samples", data2);
    mvprintw(row, lastPos, "|");
    row++;
}

void Statistics::reportingLoop(const string &demoName)
{
    int32_t     len;
    int32_t     maxLen = 65;
    uint64_t    samples;
    auto       &statsDb = m_stats;

    initscr();
    cbreak();
    noecho();
    keypad(stdscr, true);

    /* Compute the length of a data row. It is of the form
     * | .............. |
     *  ^              ^
     * which means that we need a space at the either end of the string
     * and hence +2 below.
     */
    len = 0;
    for (uint64_t i = 0; i < statsDb.size(); i++)
    {
        auto const s = &statsDb[i];
        int32_t ml = s->m_modelName.length() + 2;
        int32_t nl = s->m_inputName.length() + 2;

        len = std::max({len, ml, nl});
    }

    /* Set the length to fit the data nicely. */
    len = std::max(len, maxLen);

    const string   &border = '+' + string(len, '-') + '+';
    const string   &fmt = "| %-" + to_string(len-1) + "s|";

    while (m_printCurses)
    {
        clear();
        int row = 1;

        mvprintw(row++, 1, border.c_str());
        mvprintw(row++, 1, fmt.c_str(), demoName.c_str());
        mvprintw(row++, 1, border.c_str());

        for (uint64_t i = 0; i < statsDb.size(); i++)
        {
            auto const s = &statsDb[i];

            mvprintw(row++, 1, border.c_str());
            mvprintw(row++, 1, fmt.c_str(), s->m_inputName.c_str());
            mvprintw(row++, 1, fmt.c_str(), s->m_modelName.c_str());
            mvprintw(row++, 1, fmt.c_str(), s->m_modelType.c_str());
            mvprintw(row++, 1, border.c_str());

            for (auto &key : gStatKeys)
            {
                auto const *p = &s->m_proc[key];
                float avg = p->average;

                samples = p->samples;
                drawDataRow(row, key.c_str(), avg, "ms", samples, len+2);
            }

            for (auto &key : gMetricKeys)
            {
                auto const *m = &s->m_metrics[key];

                drawDataRow(row, key.c_str(), m->value,
                            m->unit.c_str(), m->samples, len+2);
            }

            mvprintw(row++, 1, border.c_str());
        }

        refresh();
        this_thread::sleep_for(chrono::milliseconds(1000));
    }

    echo();
    nocbreak();
    endwin();
}

void Statistics::enableCursesReport(bool            state,
                                    bool            verbose,
                                    const string   &demoName)
{
    m_printCurses = state;
    m_printStdout = !state && verbose;

    if (state)
    {
        m_reportingThread = std::thread(reportingLoop, demoName);
    }
}

void Statistics::disableCursesReport()
{
    m_printCurses = false;
    if (m_reportingThread.joinable())
    {
        m_reportingThread.join();
    }
}

void getPreProcScalerElements(const PreprocessImageConfig   *preProcCfg,
                              vector<GstElement *>          &preProcElements,
                              bool                           isMultiSrc)
{
    /*
     * tiovxmultiscaler dose not support upscaling and downscaling with
     * scaling factor < 1/4, So use "videoscale" insted
     */
    string dlCaps = "video/x-raw,"
                    " width="
                    + to_string(preProcCfg->resizeWidth)
                    + ", height="
                    + to_string(preProcCfg->resizeHeight);
    if (isMultiSrc == false) {
        vector<vector<const gchar*>> elem_property;
        makeElement(preProcElements,"queue", elem_property, NULL);
        makeElement(preProcElements,
                    gstElementMap["scaler"]["element"].as<string>().c_str(),
                    elem_property,
                    dlCaps.c_str());
        return;
    }

    vector<vector<const gchar*>> elem_property;
    if ((float)preProcCfg->inDataWidth/preProcCfg->resizeWidth > MAX_SCALE_FACTOR ||
        (float)preProcCfg->inDataHeight/preProcCfg->resizeHeight > MAX_SCALE_FACTOR)
    {
        int width = max(preProcCfg->inDataWidth/4, preProcCfg->resizeWidth);
        int height = max(preProcCfg->inDataHeight/4, preProcCfg->resizeHeight);
        if (width % 2 != 0)
        {
            width += 1;
        }
        if (height % 2 != 0)
        {
            height += 1;
        }

        string caps = "video/x-raw,"
                      " width="
                      + to_string(width)
                      + ", height="
                      + to_string(height);
        makeElement(preProcElements,"queue", elem_property, caps.c_str());
        elem_property = {{"target","1"}};
        makeElement(preProcElements,
                    gstElementMap["scaler"]["element"].as<string>().c_str(),
                    elem_property,
                    dlCaps.c_str());
        return;
    }
    else if (preProcCfg->inDataWidth/preProcCfg->resizeWidth < 1 ||
             preProcCfg->inDataHeight/preProcCfg->resizeHeight < 1)
    {
        int width = preProcCfg->inDataWidth;
        int height = preProcCfg->inDataHeight;
        string caps = "video/x-raw,"
                      " width="
                      + to_string(width)
                      + ", height="
                      + to_string(height);
        makeElement(preProcElements,"queue", elem_property, caps.c_str());
        makeElement(preProcElements,"videoscale", elem_property, dlCaps.c_str());
        return;
    }
    else {
        makeElement(preProcElements,"queue", elem_property, dlCaps.c_str());
        return;
    }
}

void getPreProcElements(const PreprocessImageConfig *preProcCfg,
                        vector<GstElement *>        &preProcElements)
{
    int32_t top;
    int32_t left;
    int32_t bottom;
    int32_t right;
    int32_t t;

    t      = preProcCfg->resizeWidth - preProcCfg->outDataWidth;
    left   = t/2;
    right  = t - left;

    t      = preProcCfg->resizeHeight - preProcCfg->outDataHeight;
    top    = t/2;
    bottom = t - top;

    if (left || right || top || bottom)
    {
        vector<vector<const gchar*>> elem_property;
        elem_property = {{"top",to_string(top).c_str()},
                         {"bottom",to_string(bottom).c_str()},
                         {"left",to_string(left).c_str()},
                         {"right",to_string(right).c_str()}
                        };
        makeElement(preProcElements,"videobox", elem_property, NULL);
    }

    if(gstElementMap["dlpreproc"]["element"])
    {
        std::string channelOrder{""};
        if (preProcCfg->dataLayout == "NCHW")
        {
            channelOrder += "0";
        }
        else if (preProcCfg->dataLayout == "NHWC")
        {
            channelOrder += "1";
        }

        std::string tensorFormat{""};
        if (preProcCfg->reverseChannel)
        {
            tensorFormat += "1"; //bgr
        }
        else
        {
            tensorFormat += "0"; //rgb
        }

        /*
        * dlpreproc takes data-type as an interger which maps to certain
        * data types, DlInferType enum in dl inferer is aligned with the
        * maping of dlpreproc
        */
        vector<vector<const gchar*>> elem_property;

        string mean_0,mean_1,mean_2;
        string scale_0,scale_1,scale_2;
        string target;
        string out_pool_size;
        string _data_type = to_string(preProcCfg->inputTensorTypes[0]);
        elem_property = {
                        {"data-type",_data_type.c_str()},
                        {"channel-order",channelOrder.c_str()},
                        {"tensor-format",tensorFormat.c_str()},
                        };

        if(gstElementMap["dlpreproc"]["property"])
        {
            if(gstElementMap["dlpreproc"]["property"]["target"])
            {
                vector<string> targets;
                targets = gstElementMap["dlpreproc"]["property"]["target"].as<vector<string>>();
                target = targets[targetIdx];

                elem_property.push_back({"target",target.c_str()});

                targetIdx++;
                if(targetIdx >= targets.size())
                {
                    targetIdx = 0;
                }
            }

            if(gstElementMap["dlpreproc"]["property"]["out-pool-size"])
            {
                out_pool_size = gstElementMap["dlpreproc"]["property"]["out-pool-size"].as<string>();
                elem_property.push_back({"out-pool-size",out_pool_size.c_str()});
            }
        }

        if (preProcCfg->mean.size() >= 3)
        {
            mean_0 = to_string(preProcCfg->mean[0]);
            mean_1 = to_string(preProcCfg->mean[1]);
            mean_2 = to_string(preProcCfg->mean[2]);
            elem_property.push_back({"mean-0",mean_0.c_str()});
            elem_property.push_back({"mean-1",mean_1.c_str()});
            elem_property.push_back({"mean-2",mean_2.c_str()});
        }

        if (preProcCfg->scale.size() >= 3)
        {
            scale_0 = to_string(preProcCfg->scale[0]);
            scale_1 = to_string(preProcCfg->scale[1]);
            scale_2 = to_string(preProcCfg->scale[2]);
            elem_property.push_back({"scale-0",scale_0.c_str()});
            elem_property.push_back({"scale-1",scale_1.c_str()});
            elem_property.push_back({"scale-2",scale_2.c_str()});
        }
        string caps = "application/x-tensor-tiovx";
        makeElement(preProcElements,
                    gstElementMap["dlpreproc"]["element"].as<string>().c_str(),
                    elem_property,
                    caps.c_str());
    }
}

const std::string to_fraction(std::string& num)
{
    if(_is_number<int>(num))
    {
        return num+"/1";
    }
    else if(_is_number<double>(num))
    {
        int dec_pos = num.find(".");
        int dec_length = num.length() - dec_pos - 1;
        num.erase(dec_pos, 1);
        int numerator = stoi(num);
        int denom = pow(10,dec_length);
        string fps = to_string(numerator)+"/"+to_string(denom);
        return fps;
    }
    else
    {
        LOG_ERROR("Framerate is not numeric.\n");
        throw runtime_error("Invalid Framerate.");
    }
}

template<typename Numeric>
bool _is_number(const std::string& s)
{
    Numeric n;
    return((std::istringstream(s) >> n >> std::ws).eof());
}

} // namespace ti::edgeai::common

