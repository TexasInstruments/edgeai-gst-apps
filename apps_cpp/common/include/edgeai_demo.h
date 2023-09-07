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

#ifndef _TI_EDGEAI_DEMO_H_
#define _TI_EDGEAI_DEMO_H_

/* Module headers. */
#include <yaml-cpp/yaml.h>

/**
 * \defgroup group_edgeai_common Master demo code
 *
 * \brief Common code used across all EdgeAI applications.
 *
 * \ingroup group_edgeai_cpp_apps
 */

namespace ti::edgeai::common
{
    // Forward declaration
    class EdgeAIDemoImpl;

    /**
     * \brief Main class that integrates the pre-processing, DL inferencing, and
     *        post-processing operations.
     *
     *        It consumes the input coming from a gstreamer pipeline setup outside
     *        the scope of the class and feeds another gstreamer pipeline for
     *        consuming the results of the post-processing.
     *
     * \ingroup group_edgeai_common
     */
    class EdgeAIDemo
    {
        public:
            /** Constructor.
             * @param yaml Parsed yaml data to extract the parameters from.
             */
            EdgeAIDemo(const YAML::Node    &yaml);

            /**
             * Print srcPipe and sinkPipe
             */
            void printPipelines();

            /**
            * Dumps GStreamer pipeline as dot file
            */
            void dumpPipelineAsDot();

            /**
             * Sets a flag for the threads to exit at the next opportunity.
             * This controls the stopping all threads, stop the Gstreamer pipelines
             * and other cleanup.
             */
            void sendExitSignal();

            /**
             * This is a blocking call that waits for all the internal threads to exit.
             */
            void waitForExit();

            /** Destructor. */
            ~EdgeAIDemo();

        private:
            /**
             * Copy Constructor.
             *
             * Copy Constructor is not required and allowed and hence prevent
             * the compiler from generating a default Copy Constructor.
             */
            EdgeAIDemo(const EdgeAIDemo& ) = delete;

            /**
             * Assignment operator.
             *
             * Assignment is not required and allowed and hence prevent
             * the compiler from generating a default assignment operator.
             */
            EdgeAIDemo & operator=(const EdgeAIDemo& rhs) = delete;

        private:
            /** Gstreamer pipe object. */
            EdgeAIDemoImpl                     *m_impl{nullptr};
    };

} // namespace ti::edgeai::common

#endif /* _TI_EDGEAI_DEMO_H_ */
