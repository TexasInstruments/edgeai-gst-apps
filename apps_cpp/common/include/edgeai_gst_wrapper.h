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

#ifndef _TI_EDGEAI_GST_WRAPPER_H_
#define _TI_EDGEAI_GST_WRAPPER_H_

#define EOS 1

/* Standard headers. */
#include <string>
#include <vector>
#include <map>
#include <mutex>

/* Third-party headers. */
#include <gst/gst.h>
#include <gst/app/gstappsink.h>
#include <gst/app/gstappsrc.h>
#include <utils/include/ti_logger.h>

namespace ti::edgeai::common
{
    using namespace ti::utils;
    using namespace std;

    /**
     * \brief Class that wraps the gstreamer memory buffers.
     *
     * \ingroup group_edgeai_common
     */
    class GstWrapperBuffer
    {
        public:
            GstWrapperBuffer()
            {
                LOG_DEBUG("CONSTRUCTOR\n");
            }

            /** Helper function to get the address.
             *
             * @returns Address of the buffer.
             */
            uint8_t *getAddr()
            {
                return addr;
            }

            void reset()
            {
                if (gbuf)
                {
                    gst_buffer_unmap(gbuf, &mapinfo);
                    gst_buffer_unref(gbuf);
                    gbuf = nullptr;
                }

                if (sample)
                {
                    gst_sample_unref(sample);
                    sample = nullptr;
                }

                addr   = nullptr;
                width  = 0;
                height = 0;
            }

            ~GstWrapperBuffer()
            {
                LOG_DEBUG("DESTRUCTOR\n");
                reset();
            }

            /**
             * Reference to the Gstreamer sample which host a GstBuffer and the
             * corresponding caps / capabilities which describe width, height, etc
             */
            GstSample  *sample{nullptr};

            /**
             * Reference to the Gstreamer buffer. Required when recycling the buffer
             */
            GstBuffer  *gbuf{nullptr};

            /**
             * Describes the mapping information of the buffer. Used while unmap
             */
            GstMapInfo  mapinfo{};

            /**
             * Holds the CPU accessible pointer to the mapped memory
             * corresponding to the GstMemory
             */
            uint8_t    *addr{nullptr};

            /** width of the video frame held by GstBuffer */
            int32_t     width{0};

            /** width of the video frame held by GstBuffer */
            int32_t     height{0};
    };

    /**
     * \brief Main class that wraps the gstreamer functionality.
     *
     * \ingroup group_edgeai_common
     */
    class GstPipe
    {
        public:
            /** Constructor.
             *
             * @param srcPipelines Vector of source Gst Pipelines
             * @param sinkPipeline Sink Pipeline
             * @param srcElemNames A vector of names to create a map of GST
             *        elements based on the information in the srcCmd string.
             *        It is the responsibility of the caller to make sure that
             *        the information in srcCmd and srcElemNames is consistent.
             * @param sinkElemNames A vector of names to create a map of GST
             *        elements based on the information in the sinkCmd string.
             *        It is the responsibility of the caller to make sure that
             *        the information in sinkCmd and sinkElemNames is consistent.
             */
            GstPipe(vector<GstElement*>      &srcPipelines,
                    GstElement*              &sinkPipeline,
                    vector<vector<string>>   &srcElemNames,
                    vector<string>           &sinkElemNames);

            /**
             * Start all the GST pipelines by setting the state to playing
             */
            int startPipeline();

            /**
             * Try to pull a buffer from an appsink element and populate the parameters
             * of the received buffer. This function only works for appsink elements.
             * 
             * @param name Name of the appsink element
             * @param buff Pointer to GstWrapperBuffer which holds the address at which the
             *          buffer is mapped, widh, height and reference to Gstreamer objects.
             * @param loop Seek the input to start after receiving EOS
             * @param readonly Map the buffer as readonly
             * @returns 0 if successful
             */
            int32_t getBuffer(const string     &name,
                              GstWrapperBuffer &buff,
                              bool             loop,
                              bool             readonly);

            /**
             * Try to push a buffer to the appsrc element
             * @param name Name of the appsrc element
             * @param buff Pointer to GstWrapperBuffer which holds the address at which the
             *          buffer is mapped, widh, height and reference to Gstreamer objects.
             * @returns 0 if element name lookup successful
             */
            int32_t putBuffer(const string     &name,
                              GstWrapperBuffer &buff);

            /**
             * Try to send EOS signal to the appsrc element
             * @param name Name of the appsrc element
             * @returns 0 if element name lookup successful
             */
            int32_t sendEOS(const string     &name);

            /**
             * Create a new GstBuffer with backing memory allocation as well.
             * This will calculate the memory size in bytes and allocate storage for it.
             * Then it wraps this memory into GstBuffer and GstSample which can be
             * used for sending the buffer to Gstreamer elements.
             * It also maps the buffer and saves the CPU accessible address of the memory.
             * 
             * @param buf Pointer to the GstWrapperBuffer where all the details will be saved
             * @param width Width of the video buffer
             * @param height Height of the video buffer
             * @param format Image format for determining the type and size of buffer to allocate.
             *               Currently, only the following types supported:
             *               - RGB
             *               - NV12
             *               - UYVY
             */
            int32_t allocBuffer(GstWrapperBuffer   &buf,
                                uint32_t            width,
                                uint32_t            height,
                                const string        format);
            /**
             * Cleanup the buffer returned by getGstBuffer or allocGstBuffer
             * This will unmap the memory so the pointer may not be valid
             * Also it will unref the Gstreamer objects so that the buffer is
             * properly recycled and memory leaks are avoided
             */
            void freeBuffer(GstWrapperBuffer &buf);

            /* Print m_srcPipe and m_sinkPipe */
            void printPipelines();

            /* Dump m_srcPipe and m_sinkPipe as dot files */
            void dumpDot();

            /** Destructor. */
            ~GstPipe();

        private:
            /**
             * Assignment operator.
             *
             * Assignment is not required and allowed and hence prevent
             * the compiler from generating a default assignment operator.
             */
            GstPipe & operator=(const GstPipe& rhs) = delete;

        private:
            /** A map of source element names to GST elements. */
            map<string,GstElement*> m_srcElemMap;

            /** A map of sink element names to GST elements. */
            map<string,GstElement*> m_sinkElemMap;

            /** Reference to the gstreamer pipeline responsible for the input
             * (ex:- sensor, file).
             */
            vector<GstElement *>    m_srcPipe;

            /** Reference to the gstreamer pipeline responsible for the output
             * (ex:- display).
             */
            GstElement             *m_sinkPipe{nullptr};

        private:
            /**
             * From an Gstreamer pipeline, find a reference to a named element
             * Note that the pipeline should have specified a name for the desired element
             * for it to be found using this method. The name passed is not the name of
             * the element, but the name of the instance of that element.
             *
             * @param pipeline Pointer to the already created Gstreamer pipeline element
             * @param name string representing the name of the element instance
             * @returns Retrieved GstElement pointer or NULL in case of failure
             */
            GstElement *findElementByName(GstElement   *pipeline,
                                          const string &name);
        protected:
            /** Mutex for multi-thread seek control. */
            std::mutex  m_mutex;
    };
    
#define GST_PIPE_LOCK_SEEK_ACCESS    std::unique_lock<std::mutex> lock(this->m_mutex)
} // namespace ti::edgeai::common

#endif /* _TI_EDGEAI_GST_WRAPPER_H_ */

