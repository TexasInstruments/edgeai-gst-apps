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
#include <common/include/pre_process_image.h>
#include <string.h> // for memcpy()

namespace ti::edgeai::common
{
using namespace ti::dl_inferer;

PreprocessImage::PreprocessImage(const PreprocessImageConfig    &config,
                                 const DebugDumpConfig          &debugConfig):
    m_config(config),
    m_debugObj(debugConfig)
{
}

int32_t PreprocessImage::operator()(const void *inData,
                                    VecDlTensorPtr &outData,
                                    bool zeroCopyEnable)
{
    void       *inBuff = const_cast<void*>(inData);
    auto       *buff = outData[0];
    int32_t     ret = 0;

    if (zeroCopyEnable)
    {
        buff->data = inBuff;
    }
    else
    {
        memcpy(buff->data, inBuff, buff->size);
    }

    return ret;
}

PreprocessImage* PreprocessImage::makePreprocessImageObj(const PreprocessImageConfig   &config,
                                                         const DebugDumpConfig         &debugConfig)
{
    PreprocessImage   *cntxt;

    cntxt = new PreprocessImage(config,debugConfig);

    return cntxt;
}

PreprocessImage::~PreprocessImage()
{
}

} // namespace ti::edgeai::common

