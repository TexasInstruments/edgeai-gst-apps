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
#include <signal.h>
#include <getopt.h>
/* Module headers. */
#include <common/include/edgeai_demo_config.h>

using namespace std;
using namespace ti::edgeai::common;

static void showUsage(const char *name)
{
    printf(" \n");
    printf("# \n");
    printf("# %s PARAMETERS [OPTIONAL PARAMETERS]\n", name);
    printf("# OPTIONS:\n");
    printf("#  --config      |-c Path to the config file.\n");
    printf("#  [--help       |-h]\n");
    printf("# \n");
    printf("# \n");
    printf("# (c) Texas Instruments 2021\n");
    printf("# \n");
    printf("# \n");
    exit(0);
}

static void ParseCmdlineArgs(int32_t    argc,
                             char      *argv[],
                             string    &configFile)
{
    int32_t longIndex;
    int32_t opt;
    static struct option long_options[] = {
        {"help",    no_argument,       0, 'h' },
        {"config",  required_argument, 0, 'c' },
        {0,         0,                 0,  0  }
    };

    while ((opt = getopt_long(argc, argv,"hc:", 
                   long_options, &longIndex )) != -1)
    {
        switch (opt)
        {
            case 'c' :
                configFile = optarg;
                break;

            case 'h' :
            default:
                showUsage(argv[0]);
                exit(-1);

        } // switch (opt)

    } // while ((opt = getopt_long(argc, argv

    // Validate the parameters
    if (configFile.empty())
    {
        showUsage(argv[0]);
        exit(-1);
    }

    logSetLevel(INFO);

    return;

} // End of ParseCmdLineArgs()

class Demo
{
    public:
        Demo(const YAML::Node  &yaml);

        int32_t setupFlows();

    public:
        /** Demo configuration. */
        DemoConfig  m_config;
};

Demo::Demo(const YAML::Node  &yaml)
{
    int32_t status;

    status = m_config.parse(yaml);

    if (status < 0)
    {
        LOG_ERROR("Demo configuration parsing failed.\n");
        throw runtime_error("Failed to construct demo object.");
    }
}

int32_t Demo::setupFlows()
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
    vector<string>          srcCmd;
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

        /* Collect the input GST pipeline from each flow, and add them to a
         * vector of pipelines i.e srcPipelines.
         */
        auto const &input = m_config.m_inputMap[flow->m_inputId];
        input->getSrcPipelines(srcPipelines, srcElemNames);

        /* Update the output set. */
        auto const &outputIds = flow->m_outputIds;
        auto const begin = outputIds.begin();
        auto const end = outputIds.end();
        outputSet.insert(begin, end);
    }

    /* Collect the sink pipeline. */
    for (auto const &oId: outputSet)
    {
        auto const &output = m_config.m_outputMap[oId];
        output->appendGstPipeline();
    }
    for (auto &[name,flow] : m_config.m_flowMap)
    {
        flow->getSinkPipeline(sinkPipeline, sinkElemNames);
    }

    /* Unref Src and Sink pipelines to deinit. */
    for (auto const &p : srcPipelines)
    {
        gst_element_set_state(p, GST_STATE_NULL);
        gst_object_unref(p);
    }

    gst_element_set_state(sinkPipeline, GST_STATE_NULL);
    gst_object_unref(sinkPipeline);

    /* Dump config info. */
    m_config.dumpInfo();

    /* Print Src and Sink Elements in Pipeline. */
    for (auto const &name: srcElemNames)
    {
        for (auto const &s: name)
        {
            LOG_INFO("\t%s\n", s.c_str());
        }
    }

    for (auto const &s: sinkElemNames)
    {
        LOG_INFO("\t%s\n", s.c_str());
    }

    return status;
}

int main(int argc, char * argv[])
{
    Demo       *demoObj;
    string      configFile;
    int32_t     status = 0;

    gst_init(&argc, &argv);

    // Parse the command line options
    ParseCmdlineArgs(argc, argv, configFile);

    // Parse the input configuration file
    YAML::Node yaml = YAML::LoadFile(configFile);

    demoObj = new Demo(yaml);

    demoObj->setupFlows();

    delete demoObj;

    return status;
}

