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
#include <iostream>

/* Module headers. */
#include <common/include/edgeai_utils.h>
#include <common/include/edgeai_demo_config.h>
#include <common/include/edgeai_demo.h>

/**
 * \defgroup group_edgeai_common Master demo code
 *
 * \brief Common code used across all EdgeAI applications.
 *
 * \ingroup group_edgeai_cpp_apps
 */

namespace ti::edgeai::common
{
class EdgeAIDemoImpl
{
    public:
        /** Constructor.
         * @param yaml Parsed yaml data to extract the parameters from.
         */
        EdgeAIDemoImpl(const YAML::Node    &yaml);

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
        ~EdgeAIDemoImpl();

    private:
        /** Setup the data flows. */
        int32_t setupFlows();

        /**
         * Copy Constructor.
         *
         * Copy Constructor is not required and allowed and hence prevent
         * the compiler from generating a default Copy Constructor.
         */
        EdgeAIDemoImpl(const EdgeAIDemoImpl& ) = delete;

        /**
         * Assignment operator.
         *
         * Assignment is not required and allowed and hence prevent
         * the compiler from generating a default assignment operator.
         */
        EdgeAIDemoImpl & operator=(const EdgeAIDemoImpl& rhs) = delete;

    private:
        /** Gstreamer pipe object. */
        GstPipe                            *m_gstPipe{nullptr};

        /** Demo configuration. */
        DemoConfig                          m_config;

};

EdgeAIDemoImpl::EdgeAIDemoImpl(const YAML::Node    &yaml)
{
    int32_t status;

    /* Parse the configuration information and build the objects. */
    status = m_config.parse(yaml);

    if (status == 0)
    {
        /* Setup the flows and run the pipes. */
        status = setupFlows();
    }

    if (status < 0)
    {
        throw runtime_error("EdgeAIDemoImpl object creation failed.");
    }
    
}

int32_t EdgeAIDemoImpl::setupFlows()
{
    int32_t status = 0;

    /* Create a set of models to instantiate from the flows. */
    set<string> modelSet;

    for (auto const &[name,flow] : m_config.m_flowMap)
    {
        auto const &modelIds = flow->m_modelIds;

        modelSet.insert(modelIds.begin(), modelIds.end());
    }

    /* Create the instances of the set of models. */
    for (auto const &mId: modelSet)
    {
        ModelInfo  *model = m_config.m_modelMap[mId];

        model->initialize();
    }

    /* Setup the flows. By this time all the relavant model contexts have been
     * setup.
     */
    vector<GstElement *>    srcPipelines;
    GstElement *            sinkPipeline{nullptr};
    vector<vector<string>>  srcElemNames;
    vector<string>          sinkElemNames;
    set<string>             outputSet;

    for (auto &[name,flow] : m_config.m_flowMap)
    {
        flow->initialize(m_config.m_modelMap,
                         m_config.m_inputMap,
                         m_config.m_outputMap);

        /* Collect the GST strings from each flow, concatenate them, and create
         * the toplevel GST string.
         */
        auto const &input = m_config.m_inputMap[flow->m_inputId];
        input->getSrcPipelines(srcPipelines, srcElemNames);

        /* Update the output set. */
        auto const &outputIds = flow->m_outputIds;

        auto const begin = outputIds.begin();
        auto const end = outputIds.end();
        outputSet.insert(begin, end);
    }

    /* Collect the sink commands by scanning all the outputs. */
    /* Also send out the background image buffers. */
    for (auto const &oId: outputSet)
    {
        auto const &output = m_config.m_outputMap[oId];
        vector<GstElement *>    bgSrcPipelines;
        GstElement *            bgSinkPipeline{nullptr};
        vector<vector<string>>  bgSrcElemNames;
        vector<string>          bgSinkElemNames;

        if (output->m_mosaicEnabled)
        {
            output->getBgPipeline(bgSinkPipeline, bgSinkElemNames);
            m_gstPipe = new GstPipe(bgSrcPipelines, bgSinkPipeline, bgSrcElemNames, bgSinkElemNames);
            status = m_gstPipe->startPipeline();

            if (status < 0)
            {
                LOG_ERROR("Failed to start GST pipelines.\n");
            }
            else
            {
                status = output->allocOutBuff(m_gstPipe);

                if (status < 0)
                {
                    LOG_ERROR("allocating background buffer failed.\n");
                    break;
                }
                else
                {
                    status = m_gstPipe->putBuffer(output->m_bkgndElemName,output->m_outBuff);

                    if (status < 0)
                    {
                        LOG_ERROR("pushing background buffer failed.\n");
                        break;
                    }
                }
            }

            m_gstPipe->freeBuffer(output->m_outBuff);
            delete m_gstPipe;
        }
    }

    for (auto const &oId: outputSet)
    {
        auto const &output = m_config.m_outputMap[oId];
        output->appendGstPipeline();
    }

    for (auto &[name,flow] : m_config.m_flowMap)
    {
        flow->getSinkPipeline(sinkPipeline, sinkElemNames);
    }
         
    /* Instantiate the GST pipe. */
    m_gstPipe = new GstPipe(srcPipelines, sinkPipeline, srcElemNames, sinkElemNames);

    /* Start GST Pipelines. */
    status = m_gstPipe->startPipeline();

    if (status < 0)
    {
         LOG_ERROR("Failed to start GST pipelines.\n");
    }
    else
    {
        /* Loop through each flow, and start the inference pipes. */
        for (auto &[name, flow] : m_config.m_flowMap)
        {
            status = flow->start(m_gstPipe);

            if (status < 0)
            {
                LOG_ERROR("Flow start failed.\n");
                break;
            }
        }
    }
    return status;
}

void EdgeAIDemoImpl::printPipelines()
{
    m_gstPipe->printPipelines();
}

/**
 * Dumps GStreamer pipeline as dot file
 */
void EdgeAIDemoImpl::dumpPipelineAsDot()
{
    const char *dump_dir = std::getenv("GST_DEBUG_DUMP_DOT_DIR");
    if (dump_dir == NULL or dump_dir==string(""))
    {
        LOG_WARN("Dumping dot file skipped. GST_DEBUG_DUMP_DOT_DIR env var needs to be set for dumping the dot file.\n");
        return;
    }

    const std::filesystem::path dump_dir_path{string(dump_dir)};
    if (!std::filesystem::exists(dump_dir_path))
    {
        LOG_WARN("[%s] directory does not exits. Creating it...\n" , dump_dir);
        if(!std::filesystem::create_directory(dump_dir_path))
        {
            LOG_WARN("Creation of [%s] directory failed. Set GST_DEBUG_DUMP_DOT_DIR env var properly.\n");
            return;
        }
    }
    m_gstPipe->dumpDot();
}

/**
 * Sets a flag for the threads to exit at the next opportunity.
 * This controls the stopping all threads, stop the Gstreamer pipelines
 * and other cleanup.
 */
void EdgeAIDemoImpl::sendExitSignal()
{
    for (auto &[name, flow] : m_config.m_flowMap)
    {
        flow->sendExitSignal();
    }
}

/**
 * This is a blocking call that waits for all the internal threads to exit.
 */
void EdgeAIDemoImpl::waitForExit()
{
    for (auto &[name, flow] : m_config.m_flowMap)
    {
        flow->waitForExit();
    }
}

/** Destructor. */
EdgeAIDemoImpl::~EdgeAIDemoImpl()
{
    delete m_gstPipe;
}

EdgeAIDemo::EdgeAIDemo(const YAML::Node    &yaml)
{
    m_impl = new EdgeAIDemoImpl(yaml);
}

EdgeAIDemo::~EdgeAIDemo()
{
    delete m_impl;
}

void EdgeAIDemo::printPipelines()
{
    m_impl->printPipelines();
}

/**
 * Dumps GStreamer pipeline as dot file
 */
void EdgeAIDemo::dumpPipelineAsDot()
{
    m_impl->dumpPipelineAsDot();
}

/**
 * Sets a flag for the threads to exit at the next opportunity.
 * This controls the stopping all threads, stop the Gstreamer pipelines
 * and other cleanup.
 */
void EdgeAIDemo::sendExitSignal()
{
    m_impl->sendExitSignal();
}

/**
 * This is a blocking call that waits for all the internal threads to exit.
 */
void EdgeAIDemo::waitForExit()
{
    m_impl->waitForExit();
}

} // namespace ti::edgeai::common

