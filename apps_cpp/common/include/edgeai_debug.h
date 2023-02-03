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
#ifndef _TI_EDGEAI_DEBUG_H_
#define _TI_EDGEAI_DEBUG_H_

#include <stdint.h>
#include <stdio.h>
#include <stdarg.h>
#include <filesystem>

namespace ti::edgeai::common
{
#define EDGEAI_ENABLE_PREPROC_DUMP      (0x1)
#define EDGEAI_ENABLE_INFERENCE_DUMP    (0x2)
#define EDGEAI_ENABLE_POSTPROC_DUMP     (0x4)
#define EDGEAI_ENABLE_DATA_DUMP_MASK    (EDGEAI_ENABLE_PREPROC_DUMP | \
                                         EDGEAI_ENABLE_INFERENCE_DUMP| \
                                         EDGEAI_ENABLE_POSTPROC_DUMP)

    using std::string;
    namespace fs = std::filesystem;

    class DebugDumpConfig
    {
        public:
            void dumpInfo(const char *prefix="") const;

        public:
            /** Mask to control dumping. */
            bool        enable{false};

            /** Name of the output directory. */
            string      dir{"debug_out"};

            /** Name of the output file. */
            string      file;

            /** Optional start frame number. */
            uint32_t    startFrame{1};

            /** Optional start frame offset. When using the images as input,
             *  the file numbering may start at a specific value. This field
             *  will help take care of that.
             */
            uint32_t    startFrameIndex{0};

            /** Optional end frame number. */
            uint32_t    endFrame{std::numeric_limits<int32_t>::max()};
    };

    class DebugDump
    {
        public:
            // Do not allow copying
            DebugDump(const DebugDump&) = delete;

            // Disable assignment
            DebugDump & operator=(const DebugDump&) = delete;

            DebugDump(const DebugDumpConfig  &config);

            uint32_t currentFrameNum() const;

            /** Function to increment the current frame number by 1. */
            void advanceFrameNum();

            /** Function to log the content to a previously opened file.
             *  The content is written if the current frame number is
             *  between the configured start and end frame numbers.
             */
            template <typename... Args>
            void log(const char *format, Args... args)
            {
                if (m_config.enable)
                {
                    if ((m_curFrame >= m_config.startFrame) &&
                        (m_curFrame <= m_config.endFrame))
                    {
                        if (m_fp == nullptr)
                        {
                            uint32_t    frameNum = m_curFrame +
                                                   m_config.startFrameIndex;
                            string name = m_config.dir + "/" +
                                          m_config.file + "_" +
                                          std::to_string(frameNum) +
                                          ".txt";

                            m_fp = fopen(name.c_str(), "w");

                            if (m_fp == nullptr)
                            {
                                string errStr = "Error opening file " + m_config.file;

                                throw std::runtime_error(errStr);
                            }
                        }

                        fprintf(m_fp, format, args...);
                    }
                }
            }

            template <typename... Args>
            void logAndAdvanceFrameNum(const char *format, Args... args)
            {
                log(format, args...);
                advanceFrameNum();

                if (m_fp != nullptr)
                {
                    fclose(m_fp);
                    m_fp = nullptr;
                }
            }

            /** Destructor. */
            ~DebugDump();

        private:
            /** Configuration. */
            const DebugDumpConfig   m_config;

            /** file stream object. */
            FILE                   *m_fp{nullptr};

            /** Current frame number. */
            uint32_t                m_curFrame{1};
    };

} // namespace ti::edgeai::common

#endif //_TI_EDGEAI_DEBUG_H_

