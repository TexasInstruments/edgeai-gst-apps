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
#include <filesystem>

/* Module headers. */
#include <utils/include/ti_stl_helpers.h>
#include <common/include/edgeai_utils.h>
#include <common/include/edgeai_demo_config.h>

#define TI_DEFAULT_LDC_WIDTH       1920
#define TI_DEFAULT_LDC_HEIGHT      1080

namespace ti::edgeai::common
{
using namespace std;
using namespace cv;

using namespace ti::edgeai::common;
using namespace ti::dl_inferer;

uint32_t C7_CORE_ID_INDEX = 0;
uint32_t ISP_TARGET_INDEX = 0;
uint32_t LDC_TARGET_INDEX = 0;

static char gFilePath[2048];

static map<string, string> gImageFormatMap =
{
    {".jpg", "jpeg"},
    {".png", "png"}
};

static map<string, string> gImageDecMap =
{
    {".jpg", "jpegdec"},
    {".png", "pngdec"}
};

static map<string, string> gVideoInExtMap =
{
    {".mp4", "qtdemux"},
    {".mov", " qtdemux"},
    {".avi", "avidemux"},
    {".mkv", "matroskademux"}
};

static map<string, vector<string>> gVideoDecMap =
{
    {"h264", {"h264parse"}},
    {"h265", {"h265parse"}},
    {"auto", {"decodebin"}}
};

static map<string, vector<string>> gVideoEncMap =
{
    {".mov", {"h264parse","qtmux"}},
    {".mp4", {"h264parse","mp4mux"}},
    {".mkv", {"h264parse","matroskamux"}}
};

int32_t InputInfo::m_numInstances = 0;

InputInfo::InputInfo(const YAML::Node &node)
{
    m_instId = m_numInstances++;

    m_source    = node["source"].as<string>();
    m_width     = node["width"].as<int32_t>();
    m_height    = node["height"].as<int32_t>();
    m_framerate = node["framerate"].as<string>();

    /* Change framerate to string representation of fraction. 0.5 = "1/2". */
    m_framerate = to_fraction(m_framerate);

    if (node["index"])
    {
        m_index = node["index"].as<int32_t>();
    }

    if (node["format"])
    {
        m_format = node["format"].as<string>();
    }

    if (node["drop"])
    {
        m_drop = node["drop"].as<bool>();
    }

    if (node["loop"])
    {
        m_loop = node["loop"].as<bool>();
    }

    if (node["pattern"])
    {
        m_pattern = node["pattern"].as<string>();
    }

    if (node["subdev-id"])
    {
        m_subdev_id = node["subdev-id"].as<string>();
    }

    if (node["ldc"])
    {
        m_ldc = node["ldc"].as<bool>();
    }

    if (node["sen-id"])
    {
        m_sen_id = node["sen-id"].as<string>();
    }

    GstStaticPadTemplate*   padtemplate;
    GstElementFactory*      factory;
    string                  scaler;

    scaler = gstElementMap["scaler"]["element"].as<string>();

    factory = gst_element_factory_find(scaler.c_str());
    padtemplate = get_pad_template(factory, GST_PAD_SRC);

    m_scalerIsMulltiSrc = (padtemplate->presence == GST_PAD_REQUEST)?true:false;

    LOG_DEBUG("CONSTRUCTOR\n");
}

void InputInfo::dumpInfo(const char *prefix) const
{
    LOG_INFO("%sInputInfo::source        = %s\n", prefix, m_source.c_str());
    LOG_INFO("%sInputInfo::width         = %d\n", prefix, m_width);
    LOG_INFO("%sInputInfo::height        = %d\n", prefix, m_height);
    LOG_INFO("%sInputInfo::framerate     = %s\n", prefix, m_framerate.c_str());
    LOG_INFO("%sInputInfo::index         = %d\n", prefix, m_index);

    LOG_INFO("%sInputInfo::srcElemNames  =\n", prefix);
    for (auto const &s: m_srcElemNames)
    {
        LOG_INFO("\t\t%s\n", s.c_str());
    }
    LOG_INFO_RAW("\n");
}

int32_t InputInfo::addGstPipeline(vector<vector<GstElement*>>   &preProcElementVec,
                                  vector<vector<GstElement*>>   &preProcScalerElementVec,
                                  const vector<string>          &srcElemNames,
                                  const vector<vector<int32_t>> &sensorDimVec)
{
    string  srcExt;
    string  whStr;
    int32_t status = 0;
    int32_t indexEnd = -1;
    srcExt = filesystem::path(m_source).extension();
    whStr  = "width=" + to_string(m_width) + ",height=" + to_string(m_height);

    //Handle decoder
    if (gVideoDecMap["h264"].size()<=1)
        gVideoDecMap["h264"].push_back(gstElementMap["h264dec"]["element"].as<string>());
    if (gVideoDecMap["h265"].size()<=1)
        gVideoDecMap["h265"].push_back(gstElementMap["h265dec"]["element"].as<string>());

    if (filesystem::exists(m_source))
    {
        if (srcExt == ".h264" || srcExt == ".h265")
        {
            m_srcType = "raw_video";
            indexEnd = 0;
        }
        else if (gVideoInExtMap.find(srcExt) != gVideoInExtMap.end())
        {
            m_srcType = "video";
        }
        else if (gImageDecMap.find(srcExt) != gImageDecMap.end())
        {
            m_srcType = "image";
            indexEnd = 0;
        }
        else
        {
            m_srcType = "camera";
        }
    }
    else if (m_source.rfind("rtsp") == 0)
    {
        m_srcType = "rtsp";
    }
    else if (m_source.rfind("http") == 0)
    {
        if (gVideoInExtMap.find(srcExt) != gVideoInExtMap.end())
        {
            m_srcType = "http";
        }
        else
        {
            LOG_ERROR("Invalid source format.\n");
            status = -1;
        }
    }
    else if (m_source.rfind('%') != string::npos)
    {
        /* Form the file name, replacing with the index. */
        sprintf(gFilePath, m_source.c_str(), m_index);

        /* Check if the file exists. */
        if (filesystem::exists(gFilePath) &&
            (gImageDecMap.find(srcExt) != gImageDecMap.end()))
        {
            m_srcType = "image";
        }
        else
        {
            LOG_ERROR("Invalid source format.\n");
            status = -1;
        }
    }
    else if (m_source == "videotestsrc")
    {
        m_srcType = "videotestsrc";
    }
    else
    {
        LOG_ERROR("Invalid source.\n");
        status = -1;
    }

    if (status == 0)
    {
        string          srcStr;
        string          srcName = "source0";

        if (m_srcType == "camera")
        {
            if (m_format == "jpeg")
            {
                m_gstElementProperty = {{"device",m_source.c_str()},
                                        {"name",srcName.c_str()}};
                string caps = "image/jpeg," + whStr;
                makeElement(m_inputElements,"v4l2src",m_gstElementProperty,caps.c_str());
                makeElement(m_inputElements,"jpegdec", m_gstElementProperty, NULL);
            }

            else if (m_format.rfind("rggb") == 0 || m_format.rfind("bggi") == 0)
            {
                if(!gstElementMap["isp"]["element"])
                {
                    LOG_ERROR("ISP element not defined for this target.");
                    throw runtime_error("Failed to create Gstreamer Pipeline.");
                }

                m_gstElementProperty = {{"device",m_source.c_str()},
                                        {"io-mode","5"},
                                        {"name",srcName.c_str()}};
                makeElement(m_inputElements,"v4l2src",m_gstElementProperty,NULL);

                m_gstElementProperty = {{"leaky","2"}};
                string caps = "video/x-bayer," + whStr + ",format=" + m_format;
                makeElement(m_inputElements,"queue",m_gstElementProperty,caps.c_str());

                string dcc_isp_file =  "/opt/imaging/" + m_sen_id + "/linear/dcc_viss.bin";
                string senName;
                string formatMsb;

                if (m_sen_id == "imx219")
                {
                    senName = "SENSOR_SONY_IMX219_RPI";
                    formatMsb = "7";
                }
                else if (m_sen_id == "imx390")
                {
                    senName = "SENSOR_SONY_IMX390_UB953_D3";
                    formatMsb = "11";
                }
                else if (m_sen_id == "ov2312")
                {
                    senName = "SENSOR_OV2312_UB953_LI";
                    formatMsb = "9";
                }

                m_gstElementProperty = {{"sensor-name",senName.c_str()},
                                        {"dcc-isp-file",dcc_isp_file.c_str()},
                                        {"format-msb",formatMsb.c_str()},
                                        };

                vector<int> ispTargets;
                int         ispTarget;
                string      ispTargetStr;
                if (gstElementMap["isp"]["property"] &&
                    gstElementMap["isp"]["property"]["target"])
                {
                    ispTargets = gstElementMap["isp"]["property"]["target"].as<vector<int>>();
                    ispTarget = ispTargets[ISP_TARGET_INDEX];
                    ISP_TARGET_INDEX++;
                    if(ISP_TARGET_INDEX >= ispTargets.size())
                    {
                        ISP_TARGET_INDEX = 0;
                    }
                    ispTargetStr = to_string(ispTarget);
                    m_gstElementProperty.push_back({"target",ispTargetStr.c_str()});
                }

                caps = "video/x-raw, format=NV12";
                makeElement(m_inputElements,
                            gstElementMap["isp"]["element"].as<string>().c_str(),
                            m_gstElementProperty,
                            caps.c_str());
                if (m_ldc)
                {
                    if(!gstElementMap["ldc"]["element"])
                    {
                        LOG_ERROR("LDC element not defined for this target.");
                        throw runtime_error("Failed to create Gstreamer Pipeline.");
                    }
                    m_width = TI_DEFAULT_LDC_WIDTH;
                    m_height = TI_DEFAULT_LDC_HEIGHT;

                    whStr  = "width=" +
                             to_string(m_width) +
                             ",height=" +
                             to_string(m_height);

                    string dcc_file = "/opt/imaging/" + m_sen_id + "/linear/dcc_ldc.bin";

                    m_gstElementProperty = {{"sensor-name",senName.c_str()},
                                            {"dcc-file",dcc_file.c_str()},
                                            };

                    vector<int> ldcTargets;
                    int         ldcTarget;
                    string      ldcTargetStr;
                    if (gstElementMap["ldc"]["property"] &&
                        gstElementMap["ldc"]["property"]["target"])
                    {
                        ldcTargets = gstElementMap["ldc"]["property"]["target"].as<vector<int>>();
                        ldcTarget = ldcTargets[LDC_TARGET_INDEX];
                        LDC_TARGET_INDEX++;
                        if(LDC_TARGET_INDEX >= ldcTargets.size())
                        {
                            LDC_TARGET_INDEX = 0;
                        }
                        ldcTargetStr = to_string(ldcTarget);
                        m_gstElementProperty.push_back({"target",ldcTargetStr.c_str()});
                    }

                    caps = "video/x-raw,format=NV12," +whStr;

                    makeElement(m_inputElements,
                                gstElementMap["ldc"]["element"].as<string>().c_str(),
                                m_gstElementProperty,
                                caps.c_str());
                }
            }
            else
            {
                m_gstElementProperty = {{"device",m_source.c_str()},
                                        {"name",srcName.c_str()}};
                string caps = "video/x-raw,"+whStr;

                makeElement(m_inputElements,"v4l2src",m_gstElementProperty,caps.c_str());
            }
        }
        else if (m_srcType == "image")
        {   
            string multifile_caps = "image/" +
                                    gImageFormatMap[srcExt] +
                                    ",framerate=" +
                                    m_framerate;

            m_gstElementProperty = {{"location",m_source.c_str()},
                                    {"loop",to_string(m_loop).c_str()},
                                    {"index",to_string(m_index).c_str()},
                                    {"stop-index",to_string(indexEnd).c_str()},
                                    {"caps",multifile_caps.c_str()},
                                    {"name",srcName.c_str()}
                                    };
            makeElement(m_inputElements,"multifilesrc",m_gstElementProperty,NULL);

            makeElement(m_inputElements,
                        gImageDecMap[srcExt].c_str(),
                        m_gstElementProperty,
                        NULL);

            string caps = "video/x-raw," + whStr;
            makeElement(m_inputElements,"videoscale",m_gstElementProperty,caps.c_str());
        }

        else if (m_srcType == "raw_video")
        {
            if (gVideoDecMap.find(m_format) == gVideoDecMap.end())
            {
                m_format = "auto";
            }

            string multifile_caps = "";
            if ((m_format == "h264" &&
                 gstElementMap["h264dec"]["element"].as<string>() == "v4l2h264dec")
                ||
                (m_format == "h265" &&
                 gstElementMap["h264dec"]["element"].as<string>() == "v4l2h265dec"))
            {
                multifile_caps = "video/x-" +
                                 m_format +
                                 ",width=" +
                                 to_string(m_width) +
                                 ",height=" +
                                 to_string(m_height) +
                                 ",framerate=" +
                                 m_framerate;
            }

            if (multifile_caps != "")
            {
                m_gstElementProperty = {{"location",m_source.c_str()},
                                        {"loop",to_string(m_loop).c_str()},
                                        {"stop-index",to_string(indexEnd).c_str()},
                                        {"caps",multifile_caps.c_str()},
                                        {"name",srcName.c_str()}
                                        };
            }

            else
            {
                m_gstElementProperty = {{"location",m_source.c_str()},
                                        {"loop",to_string(m_loop).c_str()},
                                        {"stop-index",to_string(indexEnd).c_str()},
                                        {"name",srcName.c_str()}
                                        };
            }

            makeElement(m_inputElements,"multifilesrc",m_gstElementProperty, NULL);

            for (uint32_t i=0;i<gVideoDecMap[m_format].size();i++)
            {
                if (gVideoDecMap[m_format][i] == "v4l2h264dec" ||
                    gVideoDecMap[m_format][i] == "v4l2h265dec")
                {
                    string capture_io_mode;
                    if(gVideoDecMap[m_format][i] == "v4l2h264dec" &&
                       gstElementMap["h264dec"]["property"] &&
                       gstElementMap["h264dec"]["property"]["capture-io-mode"])
                    {
                        capture_io_mode = gstElementMap["h264dec"]["property"]["capture-io-mode"].as<string>();
                        m_gstElementProperty = {{"capture-io-mode",capture_io_mode.c_str()}};
                    }

                    if(gVideoDecMap[m_format][i] == "v4l2h265dec" &&
                       gstElementMap["h265dec"]["property"] &&
                       gstElementMap["h265dec"]["property"]["capture-io-mode"])
                    {
                        capture_io_mode = gstElementMap["h265dec"]["property"]["capture-io-mode"].as<string>();
                        m_gstElementProperty = {{"capture-io-mode",capture_io_mode.c_str()}};
                    }

                    makeElement(m_inputElements,
                                gVideoDecMap[m_format][i].c_str(),
                                m_gstElementProperty,
                                NULL);

                    m_gstElementProperty = {{"pool-size","12"}};
                    string caps = "video/x-raw, format=NV12";
                    makeElement(m_inputElements,
                                "tiovxmemalloc",
                                m_gstElementProperty,
                                caps.c_str());
                }
                else {
                    makeElement(m_inputElements,
                                gVideoDecMap[m_format][i].c_str(),
                                m_gstElementProperty,
                                NULL);
                }
            }
        }

        else if (m_srcType == "video")
        {
            if (gVideoDecMap.find(m_format) == gVideoDecMap.end())
            {
                m_format = "auto";
            }
            m_gstElementProperty = {{"location",m_source.c_str()},
                                    {"name",srcName.c_str()}};
            makeElement(m_inputElements,"filesrc",m_gstElementProperty,NULL);
            
            makeElement(m_inputElements,
                        gVideoInExtMap[srcExt].c_str(),
                        m_gstElementProperty,
                        NULL);
            
            for (uint32_t i=0;i<gVideoDecMap[m_format].size();i++)
            {
                if (gVideoDecMap[m_format][i] == "v4l2h264dec" ||
                    gVideoDecMap[m_format][i] == "v4l2h265dec")
                {
                    string capture_io_mode;
                    if(gVideoDecMap[m_format][i] == "v4l2h264dec" &&
                       gstElementMap["h264dec"]["property"] &&
                       gstElementMap["h264dec"]["property"]["capture-io-mode"])
                    {
                        capture_io_mode = gstElementMap["h264dec"]["property"]["capture-io-mode"].as<string>();
                        m_gstElementProperty = {{"capture-io-mode",capture_io_mode.c_str()}};
                    }

                    if(gVideoDecMap[m_format][i] == "v4l2h265dec" &&
                       gstElementMap["h265dec"]["property"] &&
                       gstElementMap["h265dec"]["property"]["capture-io-mode"])
                    {
                        capture_io_mode = gstElementMap["h265dec"]["property"]["capture-io-mode"].as<string>();
                        m_gstElementProperty = {{"capture-io-mode",capture_io_mode.c_str()}};
                    }

                    makeElement(m_inputElements,
                                gVideoDecMap[m_format][i].c_str(),
                                m_gstElementProperty,
                                NULL);

                    m_gstElementProperty = {{"pool-size","12"}};
                    string caps = "video/x-raw, format=NV12";
                    makeElement(m_inputElements,
                                "tiovxmemalloc",
                                m_gstElementProperty,
                                caps.c_str());
                }
                else {
                    makeElement(m_inputElements,
                                gVideoDecMap[m_format][i].c_str(),
                                m_gstElementProperty,
                                NULL);
                }
            }

        }
        else if (m_srcType == "rtsp")
        {
            m_gstElementProperty = {{"location",m_source.c_str()},
                                    {"latency","0"},
                                    {"buffer-mode","3"},
                                    {"name",srcName.c_str()}};
            makeElement(m_inputElements,"rtspsrc",m_gstElementProperty,NULL);

            makeElement(m_inputElements,"rtph264depay",m_gstElementProperty,NULL);

            for (uint32_t i=0;i<gVideoDecMap["h264"].size();i++)
            {
                if (gVideoDecMap["h264"][i] == "v4l2h264dec") 
                {
                    m_gstElementProperty = {{"capture-io-mode","5"}};
                    makeElement(m_inputElements,
                                gVideoDecMap["h264"][i].c_str(),
                                m_gstElementProperty,
                                NULL);

                    m_gstElementProperty = {{"pool-size","12"}};
                    string caps = "video/x-raw, format=NV12";
                    makeElement(m_inputElements,
                                "tiovxmemalloc",
                                m_gstElementProperty,
                                caps.c_str());
                }
                else 
                {
                    makeElement(m_inputElements,
                    gVideoDecMap["h264"][i].c_str(),
                    m_gstElementProperty,
                    NULL);
                }
            }
        }
        else if (m_srcType == "http")
        {
            if (gVideoDecMap.find(m_format) == gVideoDecMap.end())
            {
                m_format = "auto";
            }

            m_gstElementProperty = {{"location",m_source.c_str()},
                                    {"name",srcName.c_str()}};

            const char *proxy = std::getenv("http_proxy");
            if (proxy != NULL or proxy != string(""))
            {
                m_gstElementProperty.push_back({"proxy",proxy});
            }

            makeElement(m_inputElements,"souphttpsrc",m_gstElementProperty,NULL);

            makeElement(m_inputElements,
                        gVideoInExtMap[srcExt].c_str(),
                        m_gstElementProperty,
                        NULL);

            for (uint32_t i=0;i<gVideoDecMap[m_format].size();i++)
            {
                if (gVideoDecMap[m_format][i] == "v4l2h264dec" ||
                    gVideoDecMap[m_format][i] == "v4l2h265dec")
                {
                    m_gstElementProperty = {{"capture-io-mode","5"}};
                    makeElement(m_inputElements,
                                gVideoDecMap[m_format][i].c_str(),
                                m_gstElementProperty,
                                NULL);

                    m_gstElementProperty = {{"pool-size","12"}};
                    string caps = "video/x-raw, format=NV12";
                    makeElement(m_inputElements,
                                "tiovxmemalloc",
                                m_gstElementProperty,
                                caps.c_str());
                }
                else {
                    makeElement(m_inputElements,
                                gVideoDecMap[m_format][i].c_str(),
                                m_gstElementProperty,
                                NULL);
                }
            }
        }
        else if (m_srcType == "videotestsrc")
        {

            map<string, string> patternMap ={{"smpte", "0"},
                                            {"snow", "1"},
                                            {"black", "2"},
                                            {"white ", "3"},
                                            {"red ", "4"},
                                            {"green ", "5"},
                                            {"blue ", "6"},
                                            {"checkers-1", "7"},
                                            {"checkers-2", "8"},
                                            {"checkers-4", "9"},
                                            {"checkers-8", "10"},
                                            {"circular", "11"},
                                            {"blink", "12"},
                                            {"smpte75", "13"},
                                            {"zone-plate", "14"},
                                            {"gamut", "15"},
                                            {"chroma-zone-plate", "16"},
                                            {"solid-color", "17"},
                                            {"ball", "18"},
                                            {"smpte100", "19"},
                                            {"bar", "20"},
                                            {"pinwheel", "21"},
                                            {"spokes", "22"},
                                            {"gradient", "23"},
                                            {"colors", "24"},
                                            {"smpte-rp-219","25"}};

            if (m_format == "auto")
                m_format = "NV12";
            m_gstElementProperty = {{"pattern",patternMap[m_pattern].c_str()}};
            string caps = "video/x-raw, width=" +
                            to_string(m_width) +
                            ", height=" +
                            to_string(m_height) +
                            ", format=" +
                            m_format;
            makeElement(m_inputElements,
                        "videotestsrc",
                        m_gstElementProperty,
                        caps.c_str());
        }

        /* NOTE: The assumption of the srcElemNames vector layout is as follows:
         * - srcElemNames[0]: direct input from the sensor (ex:- camera)
         * - srcElemNames[1]: pre-processed input
         */
        for (uint64_t i = 0; i < preProcElementVec.size(); i++)
        {
            auto j = i * 2;

            //Pre-Proc
            string drop = "false";
            if (m_drop)
            {
                drop = "true";
            }

            string appSinkBuffDepth = to_string(m_appSinkBuffDepth);
            m_gstElementProperty = {{"drop",drop.c_str()},
                                    {"max-buffers",appSinkBuffDepth.c_str()},
                                    {"name",srcElemNames[j+1].c_str()}
                                    };
            makeElement(preProcElementVec[i],"appsink",m_gstElementProperty,NULL);
            m_preProcElementVec.push_back(preProcElementVec[i]);

            m_gstElementProperty = {{"drop",drop.c_str()},
                                    {"max-buffers",appSinkBuffDepth.c_str()},
                                    {"name",srcElemNames[j].c_str()}
                                    };
            //Sensor
            vector<GstElement *> sensorElements;
            makeElement(sensorElements,"appsink",m_gstElementProperty,NULL);
            m_sensorElementVec.push_back(sensorElements);

            //Scaler
            const auto    sensorDim = sensorDimVec[i];
            vector<vector<GstElement *>> subflowScalerElementVec;
            string sensorCaps = "video/x-raw,"
                                " width="
                                + to_string(sensorDim[0])
                                + ", height="
                                + to_string(sensorDim[1]);
            //Put nullptr as first element if tiovxmultiscaler is not present
            if (!m_scalerIsMulltiSrc)
            {
                subflowScalerElementVec.push_back({nullptr});
                //Scaler Part
                vector<GstElement *> sensorElement;
                makeElement(sensorElement,"queue", m_gstElementProperty, NULL);
                makeElement(sensorElement,
                            gstElementMap["scaler"]["element"].as<string>().c_str(),
                            m_gstElementProperty,
                            sensorCaps.c_str());
                subflowScalerElementVec.push_back(sensorElement);
                //Dl Part
                subflowScalerElementVec.push_back(preProcScalerElementVec[i]);
            }
            else
            {
                vector<GstElement *> scalerElement;
                const string splitName = "multiscaler_split_" +
                                         to_string(m_instId) +
                                         to_string(i);
                m_gstElementProperty = {{"name",splitName.c_str()}};
                makeElement(scalerElement,
                            gstElementMap["scaler"]["element"].as<string>().c_str(),
                            m_gstElementProperty,
                            NULL);
                m_gstElementProperty.clear();
                subflowScalerElementVec.push_back(scalerElement);

                //Scaler Part
                vector<GstElement *> sensorElement;
                makeElement(sensorElement,
                            "queue",
                            m_gstElementProperty,
                            sensorCaps.c_str());
                subflowScalerElementVec.push_back(sensorElement);
                //Dl Part
                subflowScalerElementVec.push_back(preProcScalerElementVec[i]);
            }
            m_scalerElementVec.push_back(subflowScalerElementVec);
        }
        
        //Add tee element if not multiscaler or subflow size > 1
        if (!m_scalerIsMulltiSrc || preProcElementVec.size() > 1)
        {   
            string splitStr = "input" + to_string(m_instId) + "_split";
            m_gstElementProperty = {{"name",splitStr.c_str()}};
            makeElement(m_teeElement,"tee", m_gstElementProperty, NULL);
        }

        m_srcElemNames.insert(m_srcElemNames.end(),
                              srcElemNames.begin(),
                              srcElemNames.end());
    }
    return status;
}

int32_t InputInfo::getSrcPipelines(vector<GstElement *>    &srcPipelines,
                                   vector<vector<string>>  &srcElemNames)
{
    GstElement              *pipeline;
    string                   input_format;
    GstStaticPadTemplate    *padtemplate;
    GstElementFactory       *factory;

    pipeline = gst_pipeline_new (NULL);

    factory = gst_element_get_factory(m_inputElements.back());
    padtemplate = get_pad_template(factory,GST_PAD_SRC);
    if (padtemplate->presence == GST_PAD_SOMETIMES)
    {
        makeElement(m_inputElements,"identity", m_gstElementProperty, NULL);
    }

    addAndLink(pipeline,m_inputElements);

    //Handle TIOVXISP
    for (unsigned i = 0; i < m_inputElements.size(); i++)
    {
        factory = gst_element_get_factory(m_inputElements[i]);
        gchar *factory_name = GST_OBJECT_NAME(factory);
        if (g_strcmp0("tiovxisp", factory_name) == 0)
        {
            GValue val = G_VALUE_INIT;
            g_value_init (&val, G_TYPE_STRING);

            string dcc_2a_file_path = "/opt/imaging/"+m_sen_id+"/linear/dcc_2a.bin";
            g_value_set_string (&val,dcc_2a_file_path.c_str());
            gst_child_proxy_set_property (GST_CHILD_PROXY (m_inputElements[i]),
                                          "sink_0::dcc-2a-file",
                                          &val);
            g_value_unset (&val);

            if (m_format.rfind("bggi") != 0)
            {
                //Dont do this for bggi format i.e ov2313
                g_value_init (&val, G_TYPE_STRING);
                g_value_set_string (&val,m_subdev_id.c_str());
                gst_child_proxy_set_property (GST_CHILD_PROXY(m_inputElements[i]),
                                              "sink_0::device",
                                              &val);
                g_value_unset (&val);
            }
        }
    }

    //Get Input Format
    const gchar* ip_format = get_format(pipeline, m_inputElements.back());
    if (!ip_format)
    {
        const gchar *name;
        uint32_t last_element_index = m_inputElements.size() - 1;
        factory = gst_element_get_factory(m_inputElements[last_element_index]);
        name = gst_plugin_feature_get_name(GST_PLUGIN_FEATURE(factory));
        while (last_element_index > 0 && g_strcmp0(name,"capsfilter") == 0 )
        {
            last_element_index--;
            factory = gst_element_get_factory(m_inputElements[last_element_index]);
            name = gst_plugin_feature_get_name(GST_PLUGIN_FEATURE(factory));
        }
        factory = gst_element_get_factory(m_inputElements[last_element_index]);
        input_format = get_format_list(GST_OBJECT_NAME(factory),GST_PAD_SRC)[0];
    }
    else
    {
        input_format.assign(ip_format);
    }

    vector<string> scalerFormatList;
    scalerFormatList = get_format_list(gstElementMap["scaler"]["element"].as<string>().c_str(),
                                       GST_PAD_SINK);

    //If input format isnt supported by scaler element or input format is ANY
    if (find(scalerFormatList.begin(),
             scalerFormatList.end(),
             input_format) == scalerFormatList.end())
    {
        vector<GstElement *> colorconvertElement;
        YAML::Node           colorConvertConfig;

        colorConvertConfig = getColorConvertConfig(input_format,"NV12");

        string caps = "video/x-raw, format=NV12";
        makeElement(colorconvertElement,
                    colorConvertConfig["element"].as<string>().c_str(),
                    m_gstElementProperty,
                    caps.c_str());
        addAndLink(pipeline,colorconvertElement);
        link(m_inputElements.back() , colorconvertElement.front());
        m_inputElements.insert(m_inputElements.end(),
                               colorconvertElement.begin(),
                               colorconvertElement.end());
        input_format = "NV12";
    }
    
    GstElement *lastInputElement = m_inputElements.back();

    if (m_teeElement.size() > 0)
    {
        addAndLink(pipeline,m_teeElement);
        link(lastInputElement,m_teeElement[0]);
        lastInputElement = m_teeElement.back();
    }

    //Iterate over each subflow
    for (unsigned i=0; i<m_scalerElementVec.size(); i++)
    {
        string              subflow_format = input_format;
        vector<GstElement*> dl;
        vector<GstElement*> pre_proc_elements;
        vector<string>      firstPreProcFormatList;

        dl = m_scalerElementVec[i].back();
        m_scalerElementVec[i].pop_back();
        pre_proc_elements = m_preProcElementVec[i];

        factory = gst_element_get_factory(pre_proc_elements[0]);
        firstPreProcFormatList = get_format_list(GST_OBJECT_NAME(factory),GST_PAD_SINK);

        //If caps is any (like appsik) and the input_format is not rgb
        if (firstPreProcFormatList[0] == "ANY" && subflow_format != "RGB")
        {
            YAML::Node colorConvertConfig;
            colorConvertConfig = getColorConvertConfig(subflow_format,"RGB");

            string pool_size;
            string caps = "video/x-raw, format=RGB";
            if(colorConvertConfig["property"] &&
               colorConvertConfig["property"]["out-pool-size"])
            {
                pool_size = colorConvertConfig["property"]["out-pool-size"].as<string>();
                m_gstElementProperty = {{"out-pool-size",pool_size.c_str()}};
            }
            makeElement(dl,
                        colorConvertConfig["element"].as<string>().c_str(),
                        m_gstElementProperty,
                        caps.c_str());
            subflow_format = "RGB";
        }
        //If caps is not any and the input_format is not supported by first element in pre_proc_element_list
        else if(firstPreProcFormatList[0] != "ANY" &&
                find(firstPreProcFormatList.begin(),
                     firstPreProcFormatList.end(),
                     subflow_format) == firstPreProcFormatList.end())
        {
            YAML::Node colorConvertConfig;

            vector<string> best_guess = {"RGB","NV12","NV21","I420"};
            string flag_format = "";
            for(unsigned j=0; j<best_guess.size(); j++)
            {
                if(find(firstPreProcFormatList.begin(),
                        firstPreProcFormatList.end(),
                        best_guess[j]) != firstPreProcFormatList.end())
                {
                    flag_format = best_guess[j];
                    break;
                }
            }
            if (flag_format == "")
            {
                LOG_ERROR("%s does not support any of ['RGB','NV12','NV21','I420'].\n",
                          gst_element_get_name(pre_proc_elements[0]));
                throw runtime_error("Failed to create Gstreamer Pipeline.");
            }

            colorConvertConfig = getColorConvertConfig(subflow_format,flag_format);

            string caps = "video/x-raw, format=" + flag_format;
            string out_pool_size;
            if(colorConvertConfig["property"] &&
               colorConvertConfig["property"]["out-pool-size"])
            {
                out_pool_size = colorConvertConfig["property"]["out-pool-size"].as<string>();
                m_gstElementProperty = {{"out-pool-size",out_pool_size.c_str()}};
            }
            makeElement(dl,
                        colorConvertConfig["element"].as<string>().c_str(),
                        m_gstElementProperty,
                        caps.c_str());
            subflow_format = flag_format;
        }

        dl.insert(dl.end(),pre_proc_elements.begin(),pre_proc_elements.end()-1);

        const gchar* struct_name = get_structure_name(dl.back(), "sink");
        //If name isnt "application/x-tensor-tiovx"
        if(g_strcmp0(struct_name,"application/x-tensor-tiovx") != 0 )
        {
            if(subflow_format != "RGB")
            {
                YAML::Node colorConvertConfig;
                colorConvertConfig = getColorConvertConfig(subflow_format, "RGB");

                string caps = "video/x-raw, format=RGB";
                string pool_size;
                if(colorConvertConfig["property"] &&
                   colorConvertConfig["property"]["out-pool-size"])
                {
                    pool_size = colorConvertConfig["property"]["out-pool-size"].as<string>();
                    m_gstElementProperty = {{"out-pool-size",pool_size.c_str()}};
                }
                makeElement(dl,
                            colorConvertConfig["element"].as<string>().c_str(),
                            m_gstElementProperty,
                            caps.c_str());
                subflow_format = "RGB";
            }
        }

        addAndLink(pipeline,dl);

        GstElement *DlAppsink = pre_proc_elements.back();
        pre_proc_elements.clear();
        gst_bin_add (GST_BIN(pipeline), DlAppsink);

        if (!gstElementMap["dlpreproc"]["element"])
        {
            /*Workaround for issue where dl inferer expects aligned buffer but
            * videoconvert not able to give.
            */
            /* Check if tiovxmemalloc is present. */
            GstElementFactory *tiovxmemalloc_factory;
            tiovxmemalloc_factory = gst_element_factory_find("tiovxmemalloc");
            if (tiovxmemalloc_factory != NULL)
            {
                vector<GstElement *> memAllocElement;
                m_gstElementProperty = {{"pool-size","4"}};
                makeElement(memAllocElement,"tiovxmemalloc",m_gstElementProperty,NULL);
                addAndLink(pipeline,memAllocElement);
                link(dl.back(),memAllocElement.front());
                link(memAllocElement.back(),DlAppsink);
                gst_object_unref(tiovxmemalloc_factory);
            }
            else
            {
                link(dl.back(),DlAppsink);
            }
        }
        else
        {
            link(dl.back(),DlAppsink);
        }

        vector<GstElement*> sensor;
        sensor = m_scalerElementVec[i].back();
        m_scalerElementVec[i].pop_back();
        if (input_format != "RGB")
        {
            YAML::Node colorConvertConfig;
            colorConvertConfig = getColorConvertConfig(input_format, "RGB");

            string caps = "video/x-raw, format=RGB";
            string out_pool_size;
            string target;
            if(colorConvertConfig["property"])
            {
                if (colorConvertConfig["property"]["out-pool-size"])
                {
                    out_pool_size = colorConvertConfig["property"]["out-pool-size"].as<string>();
                    m_gstElementProperty.push_back({"out-pool-size",out_pool_size.c_str()});
                }
                if (colorConvertConfig["property"]["target"])
                {
                    target = colorConvertConfig["property"]["target"].as<vector<string>>().back();
                    m_gstElementProperty.push_back({"target",target.c_str()});
                }
            }
            makeElement(sensor,
                        colorConvertConfig["element"].as<string>().c_str(),
                        m_gstElementProperty,
                        caps.c_str());
        }
        sensor.insert(sensor.end(),m_sensorElementVec[i].begin(),m_sensorElementVec[i].end());
        addAndLink(pipeline,sensor);

        if (!m_scalerIsMulltiSrc)
        {
            link(lastInputElement,dl.front());
            link(lastInputElement,sensor.front());
        }

        else
        {
            vector<GstElement*> scaler;
            scaler = m_scalerElementVec[i].back();
            m_scalerElementVec[i].pop_back();

            if(m_scalerElementVec.size()>1)
            {
                /**
                    Add queue before tiovxmultiscaler only when it connects
                    to tee before it. Tee element will only be present when
                    theres two multiscaler needed i.e when there are more
                    than 2 subflows
                */
                vector<GstElement*> queue;
                makeElement(queue,"queue", m_gstElementProperty, NULL);
                scaler.insert(scaler.begin(),queue[0]);
            }
            
            addAndLink(pipeline,scaler);

            link(lastInputElement,scaler.front());
            link(scaler.back(),dl.front());
            link(scaler.back(),sensor.front());
        }

    }

    srcPipelines.push_back(pipeline);

    /* Insert the source element names. */
    srcElemNames.push_back(m_srcElemNames);

    return 0;
}

YAML::Node InputInfo::getColorConvertConfig(string inputFmt, string outputFmt)
{
    map<string, vector<string>> tiovxdlccCombination ={
                                                        {"NV12", {"RGB","I420"}},
                                                        {"NV21", {"RGB","I420"}},
                                                        {"RGB",  {"NV12"}},
                                                        {"I420", {"NV12"}},
                                                        {"UYVY", {"NV12"}},
                                                        {"YUY2", {"NV12"}},
                                                        {"GRAY8", {"NV12"}}
                                                      };


    string dlcc_name = gstElementMap["dlcolorconvert"]["element"].as<string>();
    string cc_name = gstElementMap["colorconvert"]["element"].as<string>();

    vector<string> dlccSinkList = get_format_list(dlcc_name.c_str(),GST_PAD_SINK);
    vector<string> ccSinkList = get_format_list(cc_name.c_str(),GST_PAD_SINK);
    vector<string> vcSinkList = get_format_list("videoconvert",GST_PAD_SINK);

    vector<string> dlccSrcList = get_format_list(dlcc_name.c_str(),GST_PAD_SRC);
    vector<string> ccSrcList = get_format_list(cc_name.c_str(),GST_PAD_SRC);
    vector<string> vcSrcList = get_format_list("videoconvert",GST_PAD_SRC);


    if ((find(dlccSinkList.begin(),dlccSinkList.end(),inputFmt) != dlccSinkList.end())
        &&
        (find(dlccSrcList.begin(),dlccSrcList.end(),outputFmt) != dlccSrcList.end()))
    {
        if (dlcc_name == "tiovxdlcolorconvert")
        {
            //Check Combination
            vector<string> supported_outputs = tiovxdlccCombination[inputFmt];
            if ((find(supported_outputs.begin(),
                      supported_outputs.end(),
                      outputFmt) != supported_outputs.end()))
            {
                return gstElementMap["dlcolorconvert"];
            }
        }
        else
        {
            return gstElementMap["dlcolorconvert"];
        }
    }

    if ((find(ccSinkList.begin(), ccSinkList.end(), inputFmt) != ccSinkList.end())
        &&
        (find(ccSrcList.begin(), ccSrcList.end(), outputFmt) != ccSrcList.end()))
    {
        return gstElementMap["colorconvert"];
    }

    if (inputFmt == "ANY" ||
        ((find(vcSinkList.begin(), vcSinkList.end(), inputFmt) != vcSinkList.end())
        &&
        (find(vcSrcList.begin(), vcSrcList.end(), outputFmt) != vcSrcList.end())))
    {
        YAML::Node node = YAML::Load("element: videoconvert");
        return node;
    }

    LOG_ERROR("%s->%s not supported by available colorconvert elements.\n",
                                                          inputFmt,outputFmt);
    throw runtime_error("Failed to create Gstreamer Pipeline.");
}

InputInfo::~InputInfo()
{
    LOG_DEBUG("DESTRUCTOR\n");
}

int32_t OutputInfo::m_numInstances = 0;

OutputInfo::OutputInfo(const YAML::Node    &node,
                       const string        &title):
    m_title(title)
{
    m_instId = m_numInstances++;

    m_bkgndElemName = "background" + to_string(m_instId);
    m_mosaicElemName = "mosaic" + to_string(m_instId);

    m_sink   = node["sink"].as<string>();
    m_width  = node["width"].as<int32_t>();
    m_height = node["height"].as<int32_t>();

    if (node["connector"])
    {
        m_connector = node["connector"].as<int32_t>();
    }
    if (node["host"])
    {
        m_host = node["host"].as<string>();
    }
    if (node["port"])
    {
        m_port = node["port"].as<int32_t>();
    }
    if (node["encoding"])
    {
        m_encoding = node["encoding"].as<string>();
    }
    if (node["gop-size"])
    {
        m_gopSize = node["gop-size"].as<int32_t>();
    }
    if (node["bitrate"])
    {
        m_bitrate = node["bitrate"].as<int32_t>();
    }
    if (node["overlay-perf-type"])
    {
        m_overlayPerfType = node["overlay-perf-type"].as<string>();
    }
    LOG_DEBUG("CONSTRUCTOR\n");
}

int32_t OutputInfo::appendGstPipeline()
{
    if (m_mosaicEnabled)
    {
        string mosaic_name = gstElementMap["mosaic"]["element"].as<string>();

        string background = "/tmp/"+ m_bkgndElemName;
        m_gstElementProperty = {{"name",m_mosaicElemName.c_str()},
                                {"background",background.c_str()},
                                };
        if (mosaic_name == "tiovxmosaic")
        {
            m_gstElementProperty.push_back({"target","1"});
        }

        string caps = "video/x-raw,format=NV12,width=" +
                      to_string(m_width) +
                      ",height=" +
                      to_string(m_height);
        makeElement(m_mosaicElements,
                    gstElementMap["mosaic"]["element"].as<string>().c_str(),
                    m_gstElementProperty,
                    caps.c_str());
    }

    if (m_overlayPerfType != "")
    {
        printf("%s\n",m_overlayPerfType.c_str());
        makeElement(m_dispElements,"queue",m_gstElementProperty,NULL);
        m_gstElementProperty = {{"title",m_title.c_str()}};

        if (m_overlayPerfType == "text")
        {
            m_gstElementProperty.push_back({"overlay-type","1"});
        }
        else
        {
            m_gstElementProperty.push_back({"overlay-type","0"});
        }
        makeElement(m_dispElements,"tiperfoverlay",m_gstElementProperty,NULL);
    }

    string  sinkType;
    string  sinkExt;
    sinkExt = filesystem::path(m_sink).extension();

    if (gVideoEncMap.find(sinkExt) != gVideoEncMap.end())
    {
        sinkType = "video";
    }
    else if (sinkExt == ".jpg")
    {
        sinkType = "image";
    }
    else if (m_sink == "kmssink")
    {
        sinkType = "display";
    }
    else if (m_sink == "remote")
    {
        sinkType = "remote";
    }
    else
    {
        sinkType = "others";
    }

    string name = "sink" + to_string(m_instId);

    if (sinkType == "display")
    {
        m_gstElementProperty = {{"sync","false"},
                                {"driver-name","tidss"},
                                {"force-modesetting","true"},
                                {"name",name.c_str()}};
        if (m_connector)
        {
            string conn_id = to_string(m_connector);
            m_gstElementProperty.push_back({"connector-id",conn_id.c_str()});
        }
        makeElement(m_dispElements,"kmssink",m_gstElementProperty,NULL);
    }

    else if (sinkType == "image")
    {
        makeElement(m_dispElements,
                    gstElementMap["jpegenc"]["element"].as<string>().c_str(),
                    m_gstElementProperty,
                    NULL);

        m_gstElementProperty = {{"location",m_sink.c_str()},
                                {"name",name.c_str()}};
        makeElement(m_dispElements,"multifilesink",m_gstElementProperty,NULL);
    }

    else if (sinkType == "video")
    {
        string h264enc = gstElementMap["h264enc"]["element"].as<string>();
        string encoder_extra_ctrl = "";

        if (h264enc == "v4l2h264enc")
        {
            encoder_extra_ctrl = "controls"
                                 ",frame_level_rate_control_enable=1"
                                 ",video_bitrate=" + to_string(m_bitrate) +
                                 ",video_gop_size=" + to_string(m_gopSize);

            m_gstElementProperty = {{"extra-controls",encoder_extra_ctrl.c_str()}};
        }

        makeElement(m_dispElements,h264enc.c_str(),m_gstElementProperty,NULL);

        for(unsigned i=0;i<gVideoEncMap[sinkExt].size();i++)
        {
            makeElement(m_dispElements,
                        gVideoEncMap[sinkExt][i].c_str(),
                        m_gstElementProperty,
                        NULL);
        }

        m_gstElementProperty = {{"location",m_sink.c_str()},
                                {"name",name.c_str()}};

        makeElement(m_dispElements,"filesink",m_gstElementProperty,NULL);
    }
    else if (sinkType == "remote")
    {
        string h264enc = "";
        string encoder_extra_ctrl = "";
        string jpegenc = "";

        if (m_encoding == "mp4" || m_encoding == "h264")
        {
            h264enc = gstElementMap["h264enc"]["element"].as<string>();
            if (h264enc == "v4l2h264enc")
            {
                encoder_extra_ctrl = "controls"
                                    ",frame_level_rate_control_enable=1"
                                    ",video_bitrate=" + to_string(m_bitrate) +
                                    ",video_gop_size=" + to_string(m_gopSize);

                m_gstElementProperty = {{"extra-controls",encoder_extra_ctrl.c_str()}};
            }

            makeElement(m_dispElements,h264enc.c_str(),m_gstElementProperty,NULL);
            makeElement(m_dispElements,"h264parse",m_gstElementProperty,NULL);

            if (m_encoding == "mp4")
            {
                m_gstElementProperty = {{"fragment-duration","1"}};
                makeElement(m_dispElements,"mp4mux",m_gstElementProperty,NULL);
            }
            else if (m_encoding == "h264")
            {
                makeElement(m_dispElements,"rtph264pay",m_gstElementProperty,NULL);
            }

        }

        else if (m_encoding == "jpeg")
        {
            jpegenc = gstElementMap["jpegenc"]["element"].as<string>();
            makeElement(m_dispElements,jpegenc.c_str(),m_gstElementProperty,NULL);

            m_gstElementProperty = {{"boundary","spionisto"}};
            makeElement(m_dispElements,"multipartmux",m_gstElementProperty,NULL);

            m_gstElementProperty = {{"max","65000"}};
            makeElement(m_dispElements,"rndbuffersize",m_gstElementProperty,NULL);
        }

        else
        {
            LOG_ERROR("Wrong encoding [%s] defined for remote output.\n", m_encoding.c_str());
            throw runtime_error("Failed to create Gstreamer Pipeline.");
        }

        m_gstElementProperty = {{"sync","false"},
                                {"host",m_host.c_str()},
                                {"port",to_string(m_port).c_str()},
                                {"name",name.c_str()}};

        makeElement(m_dispElements,"udpsink",m_gstElementProperty,NULL);

    }
    else if (sinkType == "others")
    {
        m_gstElementProperty = {{"name",name.c_str()}};
        makeElement(m_dispElements,m_sink.c_str(),m_gstElementProperty,NULL);
    }

    return 0;

}

int32_t OutputInfo::getBgPipeline(GstElement*       &sinkPipeline,
                                  vector<string>    &sinkElemNames)

{
    if (sinkPipeline == nullptr)
    {
        sinkPipeline = gst_pipeline_new (NULL);
    }

    vector<GstElement *> bg_elements;

    m_gstElementProperty = {{"format","3"},
                            {"block","true"},
                            {"num-buffers","1"},
                            {"name",m_bkgndElemName.c_str()}};

    makeElement(bg_elements,"appsrc",m_gstElementProperty,NULL);

    string caps = "video/x-raw, format=NV12" ;
    makeElement(bg_elements,
                gstElementMap["dlcolorconvert"]["element"].as<string>().c_str(),
                m_gstElementProperty,
                caps.c_str());

    makeElement(bg_elements,"queue",m_gstElementProperty,NULL);

    string bg_location = "/tmp/"+m_bkgndElemName;
    m_gstElementProperty = {{"location",bg_location.c_str()}};
    makeElement(bg_elements,"filesink",m_gstElementProperty,NULL);

    addAndLink(sinkPipeline,bg_elements);

    sinkElemNames.push_back(m_bkgndElemName);

    return 0;
}

void OutputInfo::dumpInfo(const char *prefix) const
{
    LOG_INFO("%sOutputInfo::sink         = %s\n", prefix, m_sink.c_str());
    LOG_INFO("%sOutputInfo::width        = %d\n", prefix, m_width);
    LOG_INFO("%sOutputInfo::height       = %d\n", prefix, m_height);
    LOG_INFO("%sOutputInfo::connector    = %d\n", prefix, m_connector);

    LOG_INFO_RAW("\n");
}

int32_t OutputInfo::allocOutBuff(GstPipe   *gstPipe)
{
    int32_t status = 0;

    m_gstPipe = gstPipe;

    /* Allocate a RGB buffer for display */
    status = m_gstPipe->allocBuffer(m_outBuff,
                                    m_width,
                                    m_height,
                                    m_imageFmt);
    if (status < 0)
    {
        LOG_ERROR("allocBuffer() failed.\n");
    }

    if (status == 0)
    {
        m_titleFrame = Mat(m_height, m_width, CV_8UC3, m_outBuff.getAddr());

        m_titleFrame.setTo(Scalar(0,0,0));

        if (m_overlayPerfType == "")
        {
            putText(m_titleFrame,
                    "Texas Instruments - Edge Analytics",
                    Point(40, 40),
                    FONT_HERSHEY_SIMPLEX,
                    1.2,
                    Scalar(0, 0, 255),
                    2);

            putText(m_titleFrame,
                    m_title.c_str(),
                    Point(40, 80),
                    FONT_HERSHEY_SIMPLEX,
                    1,
                    Scalar(255, 0, 0),
                    2);
        }

        for(int32_t id=0; id<m_mosaicCnt; id++)
        {
            auto const &mosaicInfo = m_instIdMosaicMap.at(id);
            const string title = m_titleMap.at(id);
            int   rowSize = (40 * mosaicInfo->m_width)/POSTPROC_DEFAULT_WIDTH;
            float txtSize =
                static_cast<float>(mosaicInfo->m_width)/POSTPROC_DEFAULT_WIDTH;

            putText(m_titleFrame,
                    title.c_str(),
                    Point(mosaicInfo->m_posX + 5, mosaicInfo->m_posY - rowSize/4),
                    FONT_HERSHEY_SIMPLEX,
                    txtSize,
                    Scalar(255, 255, 255),
                    2);
        }
    }

    return status;
}

int32_t OutputInfo::registerDispParams(const MosaicInfo  *mosaicInfo,
                                       const string      &modelTitle)
{
    int32_t             status = 0;
    int32_t             id;

    if (!mosaicInfo->m_mosaicEnabled || !m_mosaicEnabled)
    {
        if (m_mosaicCnt == 0)
        {
            m_mosaicEnabled = false;
        }
        else
        {
            LOG_ERROR("Need mosaic to support multiple subflow with same output\n");
            status = -1;
        }
    }

    if (status ==0)
    {
        id = m_mosaicCnt++;

        /* Store the mosaic information in the map. */
        m_instIdMosaicMap[id] = mosaicInfo;

        m_titleMap.push_back(modelTitle);
    }
    else
    {
        id = status;
    }

    return id;
}


OutputInfo::~OutputInfo()
{
    LOG_DEBUG("DESTRUCTOR\n");

    /* Free the buffer. */
    m_gstPipe->freeBuffer(m_outBuff);
}

MosaicInfo::MosaicInfo(vector<int> data)
{
    m_posX     = data[0];
    m_posY     = data[1];
    m_width    = data[2];
    m_height   = data[3];
    m_mosaicEnabled = true;

    LOG_DEBUG("CONSTRUCTOR\n");
}

MosaicInfo::MosaicInfo()
{
    m_width  = 1;
    m_height = 1;
    m_posX   = 0;
    m_posY   = 0;
    m_mosaicEnabled = false;

    LOG_DEBUG("CONSTRUCTOR\n");
}

void MosaicInfo::dumpInfo(const char *prefix) const
{
    LOG_INFO("%sMosaicInfo::width        = %d\n", prefix, m_width);
    LOG_INFO("%sMosaicInfo::height       = %d\n", prefix, m_height);
    LOG_INFO("%sMosaicInfo::pos_x        = %d\n", prefix, m_posX);
    LOG_INFO("%sMosaicInfo::pos_y        = %d\n", prefix, m_posY);
    LOG_INFO_RAW("\n");
}

MosaicInfo::~MosaicInfo()
{
    LOG_DEBUG("DESTRUCTOR\n");
}

ModelInfo::ModelInfo(const YAML::Node &node)
{
    m_modelPath  = node["model_path"].as<string>();

    if (node["labels_path"])
    {
        m_labelsPath = node["labels_path"].as<string>();
    }

    if (node["alpha"])
    {
        m_alpha = node["alpha"].as<float>();
    }

    if (node["viz_threshold"])
    {
        m_vizThreshold = node["viz_threshold"].as<float>();
    }

    if (node["topN"])
    {
        m_topN = node["topN"].as<int32_t>();
    }

    LOG_DEBUG("CONSTRUCTOR\n");
}

int32_t ModelInfo::initialize()
{
    YAML::Node          yaml;
    InfererConfig       infConfig;
    int32_t             status = 0;
    bool                enableTidl = false;
    int                 coreId = 1;
    // Check if the specified configuration file exists
    if (!std::filesystem::exists(m_modelPath))
    {
        LOG_ERROR("Path [%s] does not exist.\n",
                  m_modelPath.c_str());
        status = -1;
    }

    if (status == 0)
    {
        string infererTarget = gstElementMap["inferer"]["target"].as<string>();
        if (infererTarget == "dsp")
        {
            enableTidl = true;
            if (gstElementMap["inferer"]["core-id"])
            {
                vector<int> coreIds = gstElementMap["inferer"]["core-id"].as<vector<int>>();
                coreId = coreIds[C7_CORE_ID_INDEX];
                C7_CORE_ID_INDEX ++;
                if(C7_CORE_ID_INDEX >= coreIds.size())
                {
                    C7_CORE_ID_INDEX = 0;
                }
            }
        }

        else if (infererTarget != "arm")
        {
            LOG_ERROR("Invalid target specified for inferer. Defaulting to ARM.\n");
        }

        // Populate infConfig
        status = infConfig.getConfig(m_modelPath, enableTidl, coreId);

        if (status < 0)
        {
            LOG_ERROR("getConfig() failed.\n");
        }
    }

    if (status == 0)
    {
        m_infererObj = DLInferer::makeInferer(infConfig);

        if (m_infererObj == nullptr)
        {
            LOG_ERROR("DLInferer::makeInferer() failed.\n");
            status = -1;
        }
    }

    // Populate pre-process config from yaml
    if (status == 0)
    {
        status = m_preProcCfg.getConfig(m_modelPath);

        if (status < 0)
        {
            LOG_ERROR("getConfig() failed.\n");
        }
    }

    // Populate post-process config from yaml
    if (status == 0)
    {
        status = m_postProcCfg.getConfig(m_modelPath);

        if (status < 0)
        {
            LOG_ERROR("getConfig() failed.\n");
        }
    }

    // Populate post-process config from yaml
    if (status == 0)
    {
        const VecDlTensor  *dlInfOutputs;
        const VecDlTensor  *dlInfInputs;
        const DlTensor     *ifInfo;

        /* Query the output information for setting up the output buffers. */
        dlInfOutputs = m_infererObj->getOutputInfo();

        /* Query the input information for setting the tensor type in pre process. */
        dlInfInputs = m_infererObj->getInputInfo();
        ifInfo = &dlInfInputs->at(0);
        m_preProcCfg.inputTensorTypes[0] = ifInfo->type;

        /* Set input data width and height based on the infererence engine
         * information. This is only used for semantic segmentation models
         * which have 4 dimensions. The logic is extended to any models that
         * have atleast three dimensions which has the following
         * - Num channels (C)
         * - Height (H)
         * - Width (W)
         *
         * The semantic segmentation model output will have one extra dimension
         * which leads to NCHW dimensions in the output.
         * - Batch (N)
         *
         * For all other cases, the default values (set in the post-process
         * obhect are used.
         */
        ifInfo = &dlInfOutputs->at(0);

        if (m_postProcCfg.taskType == "segmentation")
        {
            /* Either NCHW or CHW. Width is the last dimention and the height
             * is the previous to last.
             */
            m_postProcCfg.inDataWidth  = ifInfo->shape[ifInfo->dim - 1];
            m_postProcCfg.inDataHeight = ifInfo->shape[ifInfo->dim - 2];
            m_postProcCfg.alpha        = m_alpha;
        }
        else
        {
            // Query the output data dimension ofrom the pre-process module.
            m_postProcCfg.inDataWidth  = m_preProcCfg.outDataWidth;
            m_postProcCfg.inDataHeight = m_preProcCfg.outDataHeight;

            if (m_postProcCfg.taskType == "classification")
            {
                m_postProcCfg.topN       = m_topN;
            }
            else
            {
                m_postProcCfg.vizThreshold = m_vizThreshold;
            }
        }

        string modelName = m_modelPath;

        if (modelName.back() == '/')
        {
            modelName.pop_back();
        }

        modelName = std::filesystem::path(modelName).filename();

        m_preProcCfg.modelName  = modelName;
        m_postProcCfg.modelName = modelName;
    }

    return status;
}

int32_t ModelInfo::createPreprocCntxt(const InputInfo          &inputInfo,
                                      const DebugDumpConfig    &debugConfig,
                                      vector<GstElement *>     &preProcElements,
                                      vector<GstElement *>     &preProcScalerElements,
                                      PreprocessImage         *&preProcObj)
{

    m_preProcCfg.inDataWidth = inputInfo.m_width;
    m_preProcCfg.inDataHeight  = inputInfo.m_height;
    m_preProcCfg.getConfig(m_modelPath);

    PreprocessImageConfig   preProcCfg(m_preProcCfg);
    int32_t                 status = 0;

    getPreProcElements(&preProcCfg,preProcElements);
    getPreProcScalerElements(&preProcCfg,
                             preProcScalerElements,
                             inputInfo.m_scalerIsMulltiSrc);

    /* Instantiate pre-processing object. */
    preProcObj = PreprocessImage::makePreprocessImageObj(preProcCfg,debugConfig);

    if (preProcObj == nullptr)
    {
        LOG_ERROR("PreprocessImage::makePreprocessImageObj() failed.\n");
        status = -1;
    }

    return status;
}

int32_t ModelInfo::createPostprocCntxt(const DebugDumpConfig   &debugConfig,
                                       const int32_t           sensorWidth,
                                       const int32_t           sensorHeight,
                                       PostprocessImage       *&postProcObj)
{
    PostprocessImageConfig  postProcCfg(m_postProcCfg);
    int32_t                 status = 0;

    postProcCfg.outDataWidth  = sensorWidth;
    postProcCfg.outDataHeight = sensorHeight;

    postProcObj = PostprocessImage::makePostprocessImageObj(postProcCfg,debugConfig);

    if (postProcObj == nullptr)
    {
        LOG_ERROR("PostprocessImage::makePostprocessImageObj() failed.\n");
        status = -1;
    }

    return status;
}

void ModelInfo::dumpInfo(const char *prefix) const
{
    LOG_INFO("%sModelInfo::modelPath     = %s\n", prefix, m_modelPath.c_str());
    LOG_INFO("%sModelInfo::labelsPath    = %s\n", prefix, m_labelsPath.c_str());
    LOG_INFO("%sModelInfo::vizThreshold  = %f\n", prefix, m_vizThreshold);
    LOG_INFO("%sModelInfo::alpha         = %f\n", prefix, m_alpha);
    LOG_INFO("%sModelInfo::topN          = %d\n", prefix, m_topN);
    LOG_INFO_RAW("\n");
}

ModelInfo::~ModelInfo()
{
    LOG_DEBUG("DESTRUCTOR\n");
    delete m_infererObj;
}

SubFlowInfo::SubFlowInfo(InferencePipe     *inferPipe,
                         PreprocessImage   *preProcObj,
                         PostprocessImage  *postProcObj):
    m_preProcObj(preProcObj),
    m_inferPipe(inferPipe),
    m_postProcObj(postProcObj)
{
    LOG_DEBUG("CONSTRUCTOR\n");
}

int32_t SubFlowInfo::start(GstPipe   *gstPipe)
{
    m_inferPipe->start(gstPipe);

    return 0;
}


SubFlowInfo::~SubFlowInfo()
{
    LOG_DEBUG("DESTRUCTOR\n");

    delete m_preProcObj;
    delete m_inferPipe;
    delete m_postProcObj;
}

int32_t FlowInfo::m_numInstances = 0;

FlowInfo::FlowInfo(FlowConfig       &flowConfig)
{
    m_instId = m_numInstances++;

    m_inputId = flowConfig.input;

    m_subFlowConfigs = flowConfig.subflow_configs;

    for (auto const &s : m_subFlowConfigs)
    {
        m_modelIds.push_back(s.model);

        for (auto const &o : s.outputs)
        {
            m_outputIds.push_back(o);
        }
    }

    if (flowConfig.debugNode["enable_mask"])
    {

        m_debugEnableMask = flowConfig.debugNode["enable_mask"].as<uint32_t>();

        if (m_debugEnableMask > EDGEAI_ENABLE_DATA_DUMP_MASK)
        {
            LOG_ERROR("Invalid debug enable mask specified. "
                      "Disabling debug logging.\n");

            m_debugEnableMask = 0;
        }

        if (m_debugEnableMask)
        {
            if (flowConfig.debugNode["out_dir"])
            {
                m_debugConfig.dir =
                    flowConfig.debugNode["out_dir"].as<string>();
            }
            if (flowConfig.debugNode["start_frame"])
            {
                m_debugConfig.startFrame =
                    flowConfig.debugNode["start_frame"].as<uint32_t>();
            }

            if (flowConfig.debugNode["end_frame"])
            {
                m_debugConfig.endFrame =
                    flowConfig.debugNode["end_frame"].as<uint32_t>();
            }
        }
    }
    LOG_DEBUG("CONSTRUCTOR\n");
}

int32_t FlowInfo::initialize(map<string, ModelInfo*>   &modelMap,
                             map<string, InputInfo*>   &inputMap,
                             map<string, OutputInfo*>  &outputMap)
{
    auto                          &inputInfo = inputMap[m_inputId];
    vector<vector<GstElement *>>  preProcElementVec;
    vector<vector<GstElement *>>  preProcScalerElementVec;
    vector<string>                flowSrcElemNames;
    int32_t                       cnt = 0;
    string                        flowStr = "flow" + to_string(m_instId);
    int32_t                       status = 0;

    /* Set up the flows. */
    for (auto &s : m_subFlowConfigs)
    {

        ModelInfo          *model = modelMap[s.model];
        PreprocessImage    *preProcObj;
        PostprocessImage   *postProcObj;
        InferencePipe      *inferPipe;
        SubFlowInfo        *subFlow;
        InferencePipeConfig ipCfg;
        vector<string>      srcElemNames;
        string              sinkElemName;
        vector<GstElement*> preProcScalerElements;
        vector<GstElement*> preProcElements;
        string              inputName;
        int32_t             sensorWidth{0};
        int32_t             sensorHeight{0};

        string modelName = model->m_modelPath;

        if (modelName.back() == '/')
        {
            modelName.pop_back();
        }

        modelName = std::filesystem::path(modelName).filename();

        /* Set the degug/test control parameters. */
        DebugDumpConfig debugConfig(m_debugConfig);

        debugConfig.dir += "/cpp/" + inputInfo->m_name + "/" + modelName;
        debugConfig.file = "pre";

        debugConfig.startFrameIndex = inputInfo->m_index;

        if (m_debugEnableMask & EDGEAI_ENABLE_PREPROC_DUMP)
        {
            debugConfig.enable = true;
        }
        else
        {
            debugConfig.enable = false;
        }

        /* Create pre-process context. */
        status = model->createPreprocCntxt(*inputInfo,
                                           debugConfig,
                                           preProcElements,
                                           preProcScalerElements,
                                           preProcObj);

        if (status < 0)
        {
            LOG_ERROR("createPreprocCntxt() failed.\n");
            break;
        }

        m_mosaicVec.clear();
        for (auto const &m : s.mosaic_infos)
        {
            if (m.size() <= 0 || !gstElementMap["mosaic"]["element"])
            {
                m_mosaicVec.push_back(new MosaicInfo());
            }
            else
            {
                m_mosaicVec.push_back(new MosaicInfo(m));
            }
        }

        for (unsigned i = 0; i < s.outputs.size(); i++)
        {
            auto &output     =  s.outputs[i];
            auto &outputInfo =  outputMap[output];
            auto &mosaicInfo =  m_mosaicVec[i];
            /* Create the instanceId to Mosaic info mapping. */
            mosaicInfo->m_outputInfo = outputInfo;
            if (!mosaicInfo->m_mosaicEnabled)
            {
                mosaicInfo->m_width = outputInfo->m_width;
                mosaicInfo->m_height = outputInfo->m_height;
            }

            /* Add some necessary checks. */
            if (mosaicInfo->m_width <= 0)
            {
                LOG_ERROR("Invalid mosaic width [%d].\n", mosaicInfo->m_width);
                status = -1;
                break;
            }

            if (mosaicInfo->m_height <= 0)
            {
                LOG_ERROR("Invalid mosaic height [%d].\n", mosaicInfo->m_height);
                status = -1;
                break;
            }

            if (mosaicInfo->m_width > inputInfo->m_width ||
                mosaicInfo->m_height > inputInfo->m_height)
            {
                LOG_ERROR("Flow output resolution cannot be"
                          "greater than input resolution.\n");
                status = -1;
                break;
            }

            if (mosaicInfo->m_mosaicEnabled)
            {
                if ((mosaicInfo->m_posX + mosaicInfo->m_width) > outputInfo->m_width)
                {
                    LOG_ERROR("Mosaic (posX + width) [%d + %d] exceeds "
                              "Output width [%d] .\n",
                              mosaicInfo->m_width,
                              mosaicInfo->m_posX,
                              outputInfo->m_width);
                    status = -1;
                    break;
                }
                if((mosaicInfo->m_posY + mosaicInfo->m_height) > outputInfo->m_height)
                {
                    LOG_ERROR("Mosaic (posY + height) [%d + %d] exceeds "
                              "Output height [%d] .\n",
                              mosaicInfo->m_height,
                              mosaicInfo->m_posY,
                              outputInfo->m_height);
                    status = -1;
                    break;
                }
            }
            /* Check ends here. */

            if (mosaicInfo->m_width > sensorWidth)
            {
                sensorWidth = mosaicInfo->m_width;
            }
            if (mosaicInfo->m_height > sensorHeight)
            {
                sensorHeight = mosaicInfo->m_height;
            }
        }

        if (status == -1)
        {
            break;
        }
        
        m_sensorDimVec.push_back({sensorWidth,sensorHeight});

        debugConfig.file = "post";

        if (m_debugEnableMask & EDGEAI_ENABLE_POSTPROC_DUMP)
        {
            debugConfig.enable = true;
        }
        else
        {
            debugConfig.enable = false;
        }

        /* Create post-process context. */
        status = model->createPostprocCntxt(debugConfig,
                                            sensorWidth,
                                            sensorHeight,
                                            postProcObj);

        if (status < 0)
        {
            LOG_ERROR("createPostprocCntxt() failed.\n");
            break;
        }

        /* Store the contexts. */
        preProcElementVec.push_back(preProcElements);
        preProcScalerElementVec.push_back(preProcScalerElements);

        /* Construct source command strings. */
        auto const &srcStr1 = flowStr + "_sensor" + to_string(cnt);
        auto const &srcStr2 = flowStr + "_pre_proc" + to_string(cnt);
        srcElemNames.push_back(srcStr1);
        srcElemNames.push_back(srcStr2);
        sinkElemName = flowStr + "_post_proc" + to_string(cnt);

        /* Append the source element names into the global vector. */
        flowSrcElemNames.insert(flowSrcElemNames.end(),
                                srcElemNames.begin(),
                                srcElemNames.end());

        debugConfig.file = "infer";

        if (m_debugEnableMask & EDGEAI_ENABLE_INFERENCE_DUMP)
        {
            debugConfig.enable = true;
        }
        else
        {
            debugConfig.enable = false;
        }

        ipCfg.zeroCopyEnable = false;

        /* Check if tiovxmemalloc exists. */
        GstElementFactory *tiovxmemalloc_factory;
        tiovxmemalloc_factory = gst_element_factory_find("tiovxmemalloc");
        if (tiovxmemalloc_factory != NULL)
        {
            ipCfg.zeroCopyEnable = true;
            gst_object_unref(tiovxmemalloc_factory);
        }

        /* if tiovxmemalloc doesnt exist, check if the lase
        * element before appsink (except capsfilter) is a tiovx.
        */
        else if (preProcElements.size() > 0)
        {
            string       name;
            gchar       *factory_name;
            int32_t      index = preProcElements.size() - 1;
            factory_name = GST_OBJECT_NAME(gst_element_get_factory(preProcElements[index]));
            while (g_strcmp0("capsfilter", factory_name) == 0)
            {
                index--;
                if (index < 0)
                {
                    break;
                }
                factory_name = GST_OBJECT_NAME(gst_element_get_factory(preProcElements[index]));
            }
            name.assign(factory_name);
            if (name.rfind("tiovx", 0) == 0)
            {
            ipCfg.zeroCopyEnable = true;
            }
        }

        ipCfg.modelBasePath = model->m_modelPath;
        ipCfg.inDataWidth   = inputInfo->m_width;
        ipCfg.inDataHeight  = inputInfo->m_height;
        ipCfg.loop          = inputInfo->m_loop;
        ipCfg.frameRate     = inputInfo->m_framerate;
        ipCfg.debugConfig   = debugConfig;

        inferPipe = new InferencePipe(ipCfg,
                                      model->m_infererObj,
                                      preProcObj,
                                      postProcObj,
                                      srcElemNames,
                                      sinkElemName);

        subFlow = new SubFlowInfo(inferPipe,
                                  preProcObj,
                                  postProcObj);

        vector <OutputInfo *> outputs;
        for (unsigned i = 0; i < s.outputs.size(); i++)
        {
            auto    &mosaicInfo =  m_mosaicVec[i];
            auto    out = mosaicInfo->m_outputInfo;
            subFlow->m_dispId = out->registerDispParams(mosaicInfo,
                                                        postProcObj->m_title);
            outputs.push_back(out);
        }
 
        m_outputMap[sinkElemName] = outputs;
        m_subFlowVec.push_back(subFlow);

        if (subFlow->m_dispId < 0)
        {
            status = subFlow->m_dispId;
            break;
        }

        /* Register a statistics entry for this instance. */
        const string &taskType = postProcObj->getTaskType();
        int32_t instId = inferPipe->getInstId();
        Statistics::addEntry(instId,
                             inputInfo->m_source,
                             taskType,
                             model->m_modelPath);
        /* Increment the model count. */
        cnt++;
    }

    if (status == 0)
    {
        /* Create the GST source command string. */
        status = inputInfo->addGstPipeline(preProcElementVec,
                                           preProcScalerElementVec,
                                           flowSrcElemNames,
                                           m_sensorDimVec);
        if (status < 0)
        {
            LOG_ERROR("addGstPipeline() failed.\n");
        }
    }

    return status;
}

int32_t FlowInfo::getSinkPipeline(GstElement*       &sinkPipeline,
                                  vector<string>    &sinkElemNames)
{
    int32_t status = 0;
    int32_t cnt = 0;
    vector<vector<const gchar*>> m_gstElementProperty;

    if (sinkPipeline == nullptr)
    {
        sinkPipeline = gst_pipeline_new (NULL);
    }

    for (auto &[name,outputs] : m_outputMap)
    {
        int32_t sensorWidth = m_sensorDimVec[cnt][0];
        int32_t sensorHeight = m_sensorDimVec[cnt][1];
        int32_t numSink = outputs.size();
        vector<GstElement *> post_proc_elements;
        sinkElemNames.push_back(name);

        m_gstElementProperty = {{"format","3"},
                                //{"is-live","true"},
                                {"block","true"},
                                {"do-timestamp","true"},
                                {"name",name.c_str()}};

        makeElement(post_proc_elements,"appsrc",m_gstElementProperty,NULL);
        string caps = "video/x-raw"
                      ", width=" +
                      to_string(sensorWidth) +
                      ", height=" +
                      to_string(sensorHeight) +
                     ", format=NV12";
        makeElement(post_proc_elements,
                    gstElementMap["dlcolorconvert"]["element"].as<string>().c_str(),
                    m_gstElementProperty,
                    caps.c_str());

        if (numSink > 1)
        {
            makeElement(post_proc_elements,"tee",m_gstElementProperty,NULL);
        }

        addAndLink(sinkPipeline,post_proc_elements);

        for (auto &output : outputs)
        {
            if (output->m_mosaicEnabled)
            {
                vector<GstElement *> queue_element;
                makeElement(queue_element,"queue",m_gstElementProperty,NULL);
                addAndLink(sinkPipeline,queue_element);
                link(post_proc_elements.back(),queue_element.front());

                if (!output->m_mosaicAdded)
                {
                    output->m_mosaicAdded = true;
                    addAndLink(sinkPipeline,output->m_mosaicElements);
                }

                GstElement *mosaic = output->m_mosaicElements.front();
                link(queue_element.back(),mosaic);

                auto const &mosaicInfo = output->m_instIdMosaicMap.at(output->m_numMosaicSink);
                string mosaicSinkPad = "sink_" + to_string(output->m_numMosaicSink);
                string mosaic_name = GST_OBJECT_NAME(gst_element_get_factory(mosaic));

                string prop_name;
                prop_name = mosaicSinkPad+"::startx";
                setMosaicProperty(mosaic,prop_name,mosaicInfo->m_posX);
                prop_name = mosaicSinkPad+"::starty";
                setMosaicProperty(mosaic,prop_name,mosaicInfo->m_posY);

                if (mosaic_name == "tiovxmosaic")
                {
                    prop_name = mosaicSinkPad+"::widths";
                    setMosaicProperty(mosaic,prop_name,mosaicInfo->m_width);
                    prop_name = mosaicSinkPad+"::heights";
                    setMosaicProperty(mosaic,prop_name,mosaicInfo->m_height);
                }
                else
                {
                    prop_name = mosaicSinkPad+"::width";
                    setMosaicProperty(mosaic,prop_name,mosaicInfo->m_width);
                    prop_name = mosaicSinkPad+"::height";
                    setMosaicProperty(mosaic,prop_name,mosaicInfo->m_height);
                }

                output->m_numMosaicSink += 1;

                if (!output->m_dispElementAdded)
                {
                    output->m_dispElementAdded = true;
                    addAndLink(sinkPipeline,output->m_dispElements);
                }
                link(output->m_mosaicElements.back(),output->m_dispElements.front());

                if (output->m_overlayPerfType != ""
                    &&
                    mosaic_name == "tiovxmosaic")
                {
                    GValue val = G_VALUE_INIT;
                    g_value_init (&val, G_TYPE_INT);
                    g_value_set_int (&val,4);
                    gst_child_proxy_set_property (GST_CHILD_PROXY (mosaic),
                                                  "src::pool-size",
                                                  &val);
                    g_value_unset (&val);
                }

            }
            else
            {
                GstElement *lastElement = post_proc_elements.back();

                if (numSink > 1)
                {
                    vector<GstElement *> queue_element;
                    makeElement(queue_element,"queue",m_gstElementProperty,NULL);
                    addAndLink(sinkPipeline,queue_element);
                    link(lastElement,queue_element.front());
                    lastElement = queue_element.back();
                }

                if (output->m_width != sensorWidth || output->m_height != sensorHeight)
                {
                    vector<GstElement *>    scaler_element;
                    GstStaticPadTemplate*   padtemplate;
                    GstElementFactory*      factory;
                    string scaler_caps = "video/x-raw,width=" +
                                         to_string(output->m_width) +
                                         ",height=" +
                                         to_string(output->m_height);

                    factory = gst_element_factory_find(gstElementMap["scaler"]["element"].as<string>().c_str());
                    padtemplate = get_pad_template(factory, GST_PAD_SRC);
                    if (padtemplate->presence == GST_PAD_REQUEST) //Multiscaler
                    {
                        m_gstElementProperty = {{"target","1"}};
                        if ((sensorWidth/output->m_width) > 4 ||
                            (sensorHeight/output->m_height) > 4)
                        {
                            int width = (sensorWidth + output->m_width)/2;
                            int height = (sensorHeight + output->m_height)/2;
                            if (width % 2 != 0)
                                width += 1;
                            if (height % 2 != 0)
                                height += 1;
                            string intm_scaler_caps = "video/x-raw,width=" +
                                                      to_string(width) +
                                                      ",height=" +
                                                      to_string(height);
                            makeElement(scaler_element,
                                        gstElementMap["scaler"]["element"].as<string>().c_str(),
                                        m_gstElementProperty,
                                        intm_scaler_caps.c_str());
                        }
                        makeElement(scaler_element,
                                    gstElementMap["scaler"]["element"].as<string>().c_str(),
                                    m_gstElementProperty,
                                    scaler_caps.c_str());
                    }
                    else
                    {
                        makeElement(scaler_element,
                                    gstElementMap["scaler"]["element"].as<string>().c_str(),
                                    m_gstElementProperty,
                                    scaler_caps.c_str());
                    }
                    addAndLink(sinkPipeline,scaler_element);
                    link(lastElement,scaler_element.front());
                    lastElement = scaler_element.back();
                }

                addAndLink(sinkPipeline,output->m_dispElements);
                link(lastElement,output->m_dispElements.front());
            }
        }
        cnt++;
    }

    return status;
}

int32_t FlowInfo::start(GstPipe   *gstPipe)
{
    int32_t status = 0;

    for (auto const &s: m_subFlowVec)
    {
        status = s->start(gstPipe);

        if (status < 0)
        {
            break;
        }
    }

    return status;
}

void FlowInfo::waitForExit()
{
    for (auto const &s: m_subFlowVec)
    {
        s->m_inferPipe->waitForExit();
    }
}

void FlowInfo::sendExitSignal()
{
    for (auto const &s: m_subFlowVec)
    {
        s->m_inferPipe->sendExitSignal();
    }
}

void FlowInfo::dumpInfo(const char *prefix) const
{
    LOG_INFO("%sFlowInfo::input          = %s\n", prefix, m_inputId.c_str());

    LOG_INFO("%sFlowInfo::modelIds       = [ ", prefix);

    for (auto const &m : m_modelIds)
    {
        LOG_INFO_RAW("%s ", m.c_str());
    }

    LOG_INFO_RAW("]\n");

    LOG_INFO("%sFlowInfo::outputIds      = [ ", prefix);

    for (auto const &o : m_outputIds)
    {
        LOG_INFO_RAW("%s ", o.c_str());
    }

    LOG_INFO_RAW("]\n");

    LOG_INFO("%sFlowInfo::mosaic        =\n", prefix);
    for (auto const &d: m_mosaicVec)
    {
        d->dumpInfo("\t\t");
    }
}

FlowInfo::~FlowInfo()
{
    LOG_DEBUG("DESTRUCTOR\n");
    DeleteVec(m_mosaicVec);
    DeleteVec(m_subFlowVec);
}

int32_t DemoConfig::parse(const YAML::Node &yaml)
{
    int32_t status = 0;
    auto const &title = yaml["title"].as<string>();

    for (auto &n : yaml["flows"])
    {
        const string &flow_name = n.first.as<string>();
        auto         &subflow = n.second;

        /* Parse input information. */
        const string &input = subflow[0].as<string>();
        if (m_inputMap.find(input) == m_inputMap.end())
        {
            /* Validate Input */
            if (!yaml["inputs"][input])
            {
                LOG_ERROR("[%s] Invalid input [%s] specified.\n",
                          flow_name.c_str(), input.c_str());
                status = -1;
                break;
            }
            m_inputMap[input] = new InputInfo(yaml["inputs"][input]);
            m_inputMap[input]->m_name = input;
            m_inputOrder.push_back(input);
        }

        /* Parse model information. */
        const string &model = subflow[1].as<string>();
        if (m_modelMap.find(model) == m_modelMap.end())
        {
            /* Validate Model */
            if (!yaml["models"][model])
            {
                LOG_ERROR("[%s] Invalid Model [%s] specified.\n",
                          flow_name.c_str(), model.c_str());
                status = -1;
                break;
            }
            m_modelMap[model] = new ModelInfo(yaml["models"][model]);
        }

        /* Parse output information. */
        const string &output = subflow[2].as<string>();
        if (m_outputMap.find(output) == m_outputMap.end())
        {
            /* Validate Output */
            if (!yaml["outputs"][output])
            {
                LOG_ERROR("[%s] Invalid Output [%s] specified.\n",
                          flow_name.c_str(), output.c_str());
                status = -1;
                break;
            }

            m_outputMap[output] = new OutputInfo(yaml["outputs"][output],title);

            /* Validate Dimension */
            if (m_outputMap[output]->m_width <= 0)
            {
                LOG_ERROR("Invalid Output width [%d].\n",
                          m_outputMap[output]->m_width);
                status = -1;
                break;
            }

            if (m_outputMap[output]->m_height <= 0)
            {
                LOG_ERROR("Invalid Output height [%d].\n",
                          m_outputMap[output]->m_height);
                status = -1;
                break;
            }
        }
    }
    if (status == 0)
    {
        /* Parse flow information. */
        status = parseFlowInfo(yaml);
    }

    return status;
}

DemoConfig::DemoConfig()
{
    LOG_DEBUG("CONSTRUCTOR\n");
}

void DemoConfig::dumpInfo() const
{
    LOG_INFO_RAW("\n");

    LOG_INFO("DemoConfig::Inputs:\n");
    for (auto &[name, obj]: m_inputMap)
    {
        obj->dumpInfo("\t");
    }

    LOG_INFO("DemoConfig::Models:\n");
    for (auto &[name, obj]: m_modelMap)
    {
        obj->dumpInfo("\t");
    }

    LOG_INFO("DemoConfig::Outputs:\n");
    for (auto &[name, obj]: m_outputMap)
    {
        obj->dumpInfo("\t");
    }

    LOG_INFO("DemoConfig::Flows:\n");
    for (auto &[name, obj]: m_flowMap)
    {
        obj->dumpInfo("\t");
    }

    LOG_INFO_RAW("\n");
}

int32_t DemoConfig::parseFlowInfo(const YAML::Node &config)
{
    int32_t status = 0;
    vector<string> visited;
    const YAML::Node &flows = config["flows"];

    for (auto &input_name: m_inputOrder)
    {
        FlowConfig flowConfig;
        if (config["debug"])
        {
            if(!config["debug"]["enable_mask"])
            {
                LOG_ERROR("enable_mask needs to be set if debug is enabled.\n");
                status = -1;
                break;
            }
            else
            {
                flowConfig.debugNode = config["debug"];
            }
        }

        flowConfig.input = input_name;
        string flow_name = "";
        for (auto &i : flows)
        {
            const string &s = i.first.as<string>();
            if (find(visited.begin(), visited.end(), s) != visited.end())
            {
                continue;
            }

            string input = flows[s][0].as<string>();
            if (input_name != input)
            {
                continue;
            }

            if (flow_name == "")
            {
               flow_name = s;
            }

            string model_name = flows[s][1].as<string>();
            SubFlowConfig subFlowConfig;
            subFlowConfig.model = model_name;

            for (auto &j : flows)
            {
                const string   &t = j.first.as<string>();
                if (find(visited.begin(), visited.end(), t) != visited.end())
                {
                    continue;
                }
                string          input = flows[t][0].as<string>();
                string          model = flows[t][1].as<string>();
                if (input != input_name || model_name != model)
                {
                    continue;
                }
                visited.push_back(t);

                string      output = flows[t][2].as<string>();
                vector<int> mosaic_info{};
                string      debug = "";
                if (flows[t].size() > 3)
                {
                    mosaic_info = flows[t][3].as<vector<int>>();
                }
                if (flows[t].size() > 4)
                {
                    debug = flows[t][4].as<string>();
                }

                subFlowConfig.outputs.push_back(output);
                subFlowConfig.mosaic_infos.push_back(mosaic_info);
                subFlowConfig.debug_infos.push_back(debug);
            }

            flowConfig.subflow_configs.push_back(subFlowConfig);
        }

        auto const     &f = new FlowInfo(flowConfig);
        m_flowMap[flow_name] = f;
    }

    return status;
}

DemoConfig::~DemoConfig()
{
    LOG_DEBUG("DESTRUCTOR\n");
    DeleteMap(m_inputMap);
    DeleteMap(m_modelMap);
    DeleteMap(m_outputMap);
    DeleteMap(m_flowMap);
}

} // namespace ti::edgeai::common

