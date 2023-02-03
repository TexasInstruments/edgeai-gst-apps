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
#include <utils/include/ti_logger.h>
#include <common/include/edgeai_debug.h>

using namespace ti::utils;

namespace ti::edgeai::common
{
DebugDump::DebugDump(const DebugDumpConfig  &config):
    m_config(config)
{
    if (m_config.enable)
    {
        /* Creates the directory path if it does not exist.
         * Otherwise no harm done.
         */
        fs::create_directories(m_config.dir);
    }
}

uint32_t DebugDump::currentFrameNum() const
{
    return m_curFrame;
}

/** Function to increment the current frame number by 1. */
void DebugDump::advanceFrameNum()
{
    /* Advance the current frame count irrespective of the enable
     * flag.
     */
    m_curFrame++;
}

/** Destructor. */
DebugDump::~DebugDump()
{
    if (m_fp != nullptr)
    {
        fclose(m_fp);
    }
}

void DebugDumpConfig::dumpInfo(const char *prefix) const
{
    LOG_INFO("%sDebugDumpConfig::enable     = %d\n", prefix, enable);
    LOG_INFO("%sDebugDumpConfig::dir        = %s\n", prefix, dir.c_str());
    LOG_INFO("%sDebugDumpConfig::file       = %s\n", prefix, file.c_str());
    LOG_INFO("%sDebugDumpConfig::startFrame = %d\n", prefix, startFrame);
    LOG_INFO("%sDebugDumpConfig::endFrame   = %d\n", prefix, endFrame);
    LOG_INFO_RAW("\n");
}
} // namespace ti::edgeai::common

