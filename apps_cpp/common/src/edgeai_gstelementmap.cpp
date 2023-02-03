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

/* Module headers. */
#include <common/include/edgeai_gstelementmap.h>

namespace ti::edgeai::common
{
    using namespace ti::utils;
    using namespace std;

    const YAML::Node getGstElementMap()
    {
        const string  &GST_ELEMENT_MAP_PATH = "/opt/edgeai-gst-apps/configs/gst_plugins_map.yaml";
        if (!std::filesystem::exists(GST_ELEMENT_MAP_PATH))
        {
            LOG_ERROR("The file [%s] does'nt exist.\n" , GST_ELEMENT_MAP_PATH.c_str());
            throw runtime_error("Failed to parse Gst Element Map.");
        }

        const char *target = std::getenv("SOC");
        if (target == NULL or target==string(""))
        {
            string default_target = "arm";
            target = default_target.c_str();
            LOG_WARN("SOC env var not specified.Defaulting target to arm.\n");
        }

        const YAML::Node yaml = YAML::LoadFile(GST_ELEMENT_MAP_PATH.c_str());
        if (!yaml[string(target)])
        {
            LOG_ERROR("[%s] not defined in [%s].\n", target, GST_ELEMENT_MAP_PATH.c_str());
            throw runtime_error("Failed to parse Gst Element Map.");
        }
        const YAML::Node n = yaml[target];
        return n;
    }

    const YAML::Node &gstElementMap = getGstElementMap();
}
