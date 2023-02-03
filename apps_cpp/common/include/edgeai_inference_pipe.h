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

#ifndef _TI_EDGEAI_INFERENCE_PIPE_H_
#define _TI_EDGEAI_INFERENCE_PIPE_H_

/* Standard headers. */
#include <thread>

/* Module headers. */
#include <common/include/edgeai_debug.h>
#include <common/include/pre_process_image.h>
#include <common/include/post_process_image.h>
#include <common/include/edgeai_gst_wrapper.h>

/**
 * \defgroup group_edgeai_common Master demo code
 *
 * \brief Common code used across all EdgeAI applications.
 *
 * \ingroup group_edgeai_cpp_apps
 */

namespace ti::edgeai::common
{

    /**
     * \brief Demo configuration information. This information does not come
     *        from the YAML specification used for providing critical
     *        parameters for the pre/inference/post processing stages. The
     *        fields provided through this is very application specific.
     *
     * \ingroup group_edgeai_common
     */
    struct InferencePipeConfig
    {
        /** Path to directory where model artifacts are located. */
        string              modelBasePath;

        /** Width of the input data to pre-processing. The units are very
         * sensor specific (ex:- it will be pixels for an image).
         */
        int32_t             inDataWidth;

        /** Height of the input data to pre-processing. The units are very
         * sensor specific (ex:- it will be pixels for an image).
         */
        int32_t             inDataHeight;

        /** loop input after receiving EOS */
        bool                loop;

        /** Width of the output to display. */
        int32_t             dispWidth;

        /** Height of the output to display. */
        int32_t             dispHeight;

        /** Frame rate. */
        string              frameRate;

        /** Flag to enable Zero Copy. */
        bool                zeroCopyEnable;

        /** Optional debugging control configuration. */
        DebugDumpConfig     debugConfig;

        /**
         * Helper function to dump the configuration information.
         */
        void dumpInfo() const;
    };

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
    class InferencePipe
    {
        public:
            /** Constructor.
             *
             * @param config Configuration for the setup.
             * @param infererObj Inference context
             * @param preProcObj Pre-processing object
             * @param postProcObj Post-processing object
             * @param srcElemNames A vector of GST appsrc element names
             */
            InferencePipe(const InferencePipeConfig    &config,
                          DLInferer                    *infererObj,
                          PreprocessImage              *preProcObj,
                          PostprocessImage             *postProcObj,
                          const vector<string>         &srcElemNames,
                          const string                 &sinkElemName);

            /** Function to register the gstPipe with the inference pipe and
             * start the execution.
             *
             * @param gstPipe GST pipe context containing the full set of the
             *        source and sink command string completely specified.
             */
            void start(GstPipe   *gstPipe);

            /**
             * Sets a flag for the threads to exit at the next opportunity.
             * This controls the stopping all threads, stop the Gstreamer
             * pipelines and other cleanup.
             */
            void sendExitSignal();

            /**
             * This is a blocking call that waits for all the internal threads
             * to exit.
             */
            void waitForExit();

            /** Returns the unique If of this instance. A unique Id is assigned
             * to an instance when it is created.
             *
             * One use of this function is to get the Id to be used when
             * setting up statistics instance for tracking inference specific
             * data.
             */
            int32_t getInstId();

            /** Destructor. */
            ~InferencePipe();

        private:
            /**
             * Assignment operator.
             *
             * Assignment is not required and allowed and hence prevent
             * the compiler from generating a default assignment operator.
             */
            InferencePipe & operator=(const InferencePipe& rhs) = delete;

            /**
             * Connect the capture and display pipelines from Gstreamer, start the threads
             * for running the pipeline and inference
             *
             * @returns zero on succcess, non zero on failure
             */
            int32_t launchThreads();

            /**
             * Creates the descriptor based on the information from the
             * inference model interface information.
             *
             * @param ifInfoList Vector of inference model interface parameters
             * @param vecVar     Vector of descriptors created by this function
             * @param allocate   Allocate memory if True
             */
            int32_t createBuffers(const VecDlTensor    *ifInfoList,
                                  VecDlTensorPtr        &vecVar,
                                  bool                  allocate);

            /**
             * Run the inference model with provided input data as float array and save the
             * results in the referenced vector of vector
             *
             * @param inVecVar A vector of input buffers.
             * @param outVecVar vector of output buffers.
             * @returns zero on success, non-zero on failure
             */
            int runModel(const VecDlTensorPtr &inVecVar, VecDlTensorPtr &outVecVar);

            /**
             * Function which runs the inference step in a loop
             * Get the preprocessed buffer from Gstreamer, perform additional preprocessing,
             * pass it to DLR for inference and save the results.
             */
            void inferenceThread();

            /**
             * Function which runs the capture -> display pipeline in a loop
             * Get the original camera buffer from Gstreamer, perform post processing with
             * last inference data (if availalble) and send it to display
             * This allows the capture -> display to run as fast as possible and not get
             * slowed down if the inference processing takes time, thus enhancing the user
             * experience
             */
            void pipelineThread();

            /** Debug object. */
            DebugDump &getDebugObj()
            {
                return m_debugObj;
            }

        private:
            /** gstreamer pipe object. */
            GstPipe                *m_gstPipe{nullptr};

            /** Inference context. */
            DLInferer              *m_inferer{nullptr};

            /** Pre-processing context. */
            PreprocessImage        *m_preProcObj{nullptr};

            /** Post-processing context. */
            PostprocessImage       *m_postProcObj{nullptr};

            /** Demo configuration. */
            InferencePipeConfig     m_config;

            /** Vector of names for gstreamer appsink on the source side. */
            const vector<string>    m_srcElemNames;

            /** Name for gstreamer appsrc on the sink side. */
            const string            m_sinkElemName;

            /** Number of inputs from the inference processing. */
            int32_t                 m_numInputs;

            /** Number of outputs from the inference processing. */
            int32_t                 m_numOutputs;

            /** Inference thread identifier. */
            thread                  m_inferThreadId;

            /** Input buffers to the inference. */
            VecDlTensorPtr          m_inferInputBuff;

            /** Output buffers to the inference. */
            VecDlTensorPtr          m_inferOutputBuff;

            /** Frame rate of the input data. */
            uint32_t                m_frameRate;

            /** Instance Id. */
            uint32_t                m_instId{};

            /** Instance count. */
            static uint32_t         m_instCnt;

            /** Flag to control the execution. */
            bool                    m_running;

            /** Support for debugging and testing. */
            DebugDump               m_debugObj;
    };

} // namespace ti::edgeai::common

#endif /* _TI_EDGEAI_INFERENCE_PIPE_H_ */
