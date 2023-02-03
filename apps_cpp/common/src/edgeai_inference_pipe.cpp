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
#include <utils/include/ti_stl_helpers.h>
#include <common/include/edgeai_utils.h>
#include <common/include/edgeai_inference_pipe.h>
#include <utils/include/edgeai_perfstats.h>

#define TI_EDGEAI_GET_TIME() chrono::system_clock::now()

#define TI_EDGEAI_GET_DIFF(_START, _END) \
chrono::duration_cast<chrono::milliseconds>(_END - _START).count()

namespace ti::edgeai::common
{
using namespace ti::utils;

/* Alias for time point type */
using TimePoint = std::chrono::time_point<std::chrono::system_clock>;

uint32_t InferencePipe::m_instCnt = 0;

InferencePipe::InferencePipe(const InferencePipeConfig &config,
                             DLInferer                 *infererObj,
                             PreprocessImage           *preProcObj,
                             PostprocessImage          *postProcObj,
                             const vector<string>      &srcElemNames,
                             const string              &sinkElemName):
    m_inferer(infererObj),
    m_preProcObj(preProcObj),
    m_postProcObj(postProcObj),
    m_config(config),
    m_srcElemNames(srcElemNames),
    m_sinkElemName(sinkElemName),
    m_debugObj(config.debugConfig)
{
    const VecDlTensor  *dlInfOutputs;
    int32_t             status;

    /* Set the instance Id. */
    m_instId = m_instCnt++;

    // Query the output information for setting up the output buffers
    dlInfOutputs = m_inferer->getOutputInfo();
    m_numOutputs = dlInfOutputs->size();

    status = createBuffers(dlInfOutputs, m_inferOutputBuff, true);

    if (status < 0)
    {
        LOG_ERROR("createBuffers(m_inferOutputBuff) failed.\n");
    }

    if (status == 0)
    {
        const VecDlTensor  *dlInfInputs;

        /* Query the input information for setting up the output buffers for
         * the pre-processing stage.
         */
        dlInfInputs = m_inferer->getInputInfo();
        m_numInputs = dlInfInputs->size();

        status = createBuffers(dlInfInputs,
                               m_inferInputBuff,
                               !m_config.zeroCopyEnable);

        if (status < 0)
        {
            LOG_ERROR("createBuffers(m_inferInputBuff) failed.\n");
        }
    }

    if (status < 0)
    {
        throw runtime_error("InferencePipe object creation failed.");
    }

    LOG_DEBUG("CONSTRUCTOR\n");
}

int32_t InferencePipe::getInstId()
{
    return m_instId;
}

void InferencePipe::start(GstPipe   *gstPipe)
{
    m_gstPipe = gstPipe;

    /* Launch processing threads. */
    launchThreads();
}

/**
 * Connect the capture and display pipelines from Gstreamer, start the threads
 * for running the pipeline and inference
 *
 * @returns zero on succcess, non zero on failure
 */
int32_t InferencePipe::launchThreads()
{
    int32_t status = 0;

    m_running = true;

    /* Launch the inference thread using a lambda function.
     * The usage "[=]" or [this] captures entire class context.
     */
    m_inferThreadId = std::thread([this]{inferenceThread();});

    return status;
}

/**
 * Sets a flag for the threads to exit at the next opportunity.
 * This controls the stopping all threads, stop the Gstreamer pipelines
 * and other cleanup.
 */
void InferencePipe::sendExitSignal()
{
    m_running = false;
}

/**
 * This is a blocking call that waits for all the internal threads to exit.
 */
void InferencePipe::waitForExit()
{
    if (m_inferThreadId.joinable())
    {
        m_inferThreadId.join();
    }
}

int32_t InferencePipe::createBuffers(const VecDlTensor    *ifInfoList,
                                     VecDlTensorPtr       &vecVar,
                                     bool                 allocate)
{
    vecVar.reserve(ifInfoList->size());

    for (uint64_t i = 0; i < ifInfoList->size(); i++)
    {
        const DlTensor *ifInfo = &ifInfoList->at(i);
        DlTensor   *obj = new DlTensor(*ifInfo);

        /* Allocate data buffer. */
        if (allocate)
            obj->allocateDataBuffer(*m_inferer);

        vecVar.push_back(obj);
    }

    return 0;
}

/**
 * Run the inference model with provided input data as float array and save the
 * results in the referenced vector of vector
 *
 * @param inVecVar A vector of input buffers.
 * @param outVecVar vector of output buffers.
 * @returns zero on success, non-zero on failure
 */
int InferencePipe::runModel(const VecDlTensorPtr    &inVecVar,
                            VecDlTensorPtr          &outVecVar)
{
    int32_t status;

    // Run the model
    status = m_inferer->run(inVecVar, outVecVar);

    if (status < 0)
    {
        throw runtime_error("Inference failed.\n");
    }

    return status;
}

/**
 * Function which runs the inference step in a loop
 * Get the preprocessed buffer from Gstreamer, perform additional preprocessing,
 * pass it to DLR for inference and save the results.
 */
void InferencePipe::inferenceThread()
{
    const uint8_t      *frame;
    GstWrapperBuffer    inputBuff;
    GstWrapperBuffer    cameraBuff;
    TimePoint           start;
    TimePoint           end;
    TimePoint           prev_frame;
    TimePoint           curr_frame;
    bool                first_frame = true;
    float               diff;
    int32_t             status;

    LOG_INFO("Starting inference thread.\n");

    while (m_running)
    {
        /* Get a new frame. This function blocks until a new frame
         * is available from the sensor.
         */

        // Starting point to capture performance metrics
        ti::utils::startRec();

        // Run pre-processing
        status = m_gstPipe->getBuffer(m_srcElemNames[1],
                                      inputBuff,
                                      m_config.loop,
                                      true);
        if (status != 0)
        {
            if (status != EOS)
            {
                LOG_ERROR("Could not get 'input' buffer from Gstreamer");
            }

            break;
        }

        frame = inputBuff.getAddr();

        status = (*m_preProcObj)(frame,
                     m_inferInputBuff,
                 m_config.zeroCopyEnable);

        if (status != 0)
        {
            LOG_ERROR("Pre-processing execution failed.\n");
            break;
        }

        // Run inference
        start = TI_EDGEAI_GET_TIME();
        status = runModel(m_inferInputBuff, m_inferOutputBuff);
        end = TI_EDGEAI_GET_TIME();

        diff = TI_EDGEAI_GET_DIFF(start, end);
        Statistics::reportProcTime(m_instId, "dl-inference", diff);

        if (status)
        {
            LOG_ERROR("Failed to run the model.\n");
            break;
        }

        m_gstPipe->freeBuffer(inputBuff);

        // Run post-process logic
        status = m_gstPipe->getBuffer(m_srcElemNames[0],
                                      cameraBuff,
                                      m_config.loop,
                                      false);

        if (status != 0)
        {
            if (status != EOS)
            {
                LOG_ERROR("Could not get 'camera' buffer from Gstreamer");
            }
            break;
        }

        (*m_postProcObj)(cameraBuff.getAddr(),
                         m_inferOutputBuff);

        /* Send the buffer to the output pipeline. */
        status = m_gstPipe->putBuffer(m_sinkElemName, cameraBuff);

        if (status != 0)
        {
            LOG_ERROR("Could not put 'post-processed' buffer to Gstreamer");
            break;
        }

        /* Free the buffer. */
        m_gstPipe->freeBuffer(cameraBuff);

        /* End point for capturing performance metrics. 
           Capturing metrics paused until startRec() is called again. */
        ti::utils::endRec();

        /* Mesuring total time taken to process a frame by saving the previous
           timestamp in prev_frame and calculating the difference with current
           timestamp */
        if (!first_frame)
        {
            curr_frame = TI_EDGEAI_GET_TIME();
            diff = TI_EDGEAI_GET_DIFF(prev_frame, curr_frame);
            prev_frame = curr_frame;

            Statistics::reportMetric(m_instId, "total time", "ms", diff);
            Statistics::reportMetric(m_instId, "framerate", "fps", 1000/diff);
        }
        else
        {
            prev_frame = TI_EDGEAI_GET_TIME();
            first_frame = false;
        }

    } // while (m_running)

    /* Send EOS to gst sink element*/
    m_gstPipe->sendEOS(m_sinkElemName);

    LOG_INFO("Exiting inference thread.\n");

    return;
}

/** Destructor. */
InferencePipe::~InferencePipe()
{
    LOG_DEBUG("DESTRUCTOR\n");
    DeleteVec(m_inferInputBuff);
    DeleteVec(m_inferOutputBuff);
}

void InferencePipeConfig::dumpInfo() const
{
    LOG_INFO_RAW("\n");
    LOG_INFO("InferencePipeConfig::modelBasePath  = %s\n", modelBasePath.c_str());
    LOG_INFO("InferencePipeConfig::inDataWidth    = %d\n", inDataWidth);
    LOG_INFO("InferencePipeConfig::inDataHeight   = %d\n", inDataHeight);
    LOG_INFO("InferencePipeConfig::frameRate      = %s\n", frameRate.c_str());
    LOG_INFO("InferencePipeConfig::zeroCopyEnable = %d\n", zeroCopyEnable);
}

} // namespace ti::edgeai::common

