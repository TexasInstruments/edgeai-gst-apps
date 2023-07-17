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
#ifndef _TI_EDGEAI_DEMO_CONFIG_H_
#define _TI_EDGEAI_DEMO_CONFIG_H_

/* Standard headers. */
#include <map>
#include <set>

/* Third-party headers. */
#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>
#include <yaml-cpp/yaml.h>

/* Module headers. */
#include <edgeai_dl_inferer/ti_dl_inferer.h>
#include <common/include/pre_process_image.h>
#include <common/include/post_process_image.h>
#include <common/include/edgeai_gst_helper.h>
#include <common/include/edgeai_gstelementmap.h>
#include <common/include/edgeai_inference_pipe.h>
/**
 * \defgroup group_edgeai_demo_config Demo configuration processing.
 *
 * \brief Core demo configuration logic for parsing the configuration
 *        YAML file and setting up complex data flows.
 *
 * \ingroup group_edgeai_common
 */

namespace ti::edgeai::common
{
#define DEMO_CONFIG_APPSINK_BUFF_DEPTH  (2)

    using namespace std;
    using namespace ti::edgeai::common;
    using namespace ti::dl_inferer;

    struct SubFlowConfig
    {
        string                 model;
        vector<string>         outputs;
        vector<vector<int>>    mosaic_infos;
        vector<string>         debug_infos;
    };

    struct FlowConfig
    {
        string                input;
        vector<SubFlowConfig> subflow_configs;
        YAML::Node            debugNode;
    };

    /* Forward declaration. */
    class OutputInfo;

    /**
     * \brief Class for holding mosaic parameters for constructing the output.
     *
     * \ingroup group_edgeai_demo_config
     */
    class MosaicInfo
    {
        public:
            /** Default constructor. Use the compiler generated default one. */
            MosaicInfo();

            /** Constructor.
             *
             * @param data Integer Vector containing posX,posY,width,height
             */
            MosaicInfo(vector<int> data);

            /** Destructor. */
            ~MosaicInfo();

        public:
            void dumpInfo(const char *prefix="") const;

            /** Post-process output width. */
            int32_t     m_width{};

            /** Post-process output height. */
            int32_t     m_height{};

            /** X-coordinate to place the window. */
            int32_t     m_posX{};

            /** Y-coordinate to place the window. */
            int32_t     m_posY{};

            /** True if mosaic is enabled, False if this need full output. */
            bool        m_mosaicEnabled{true};

            /** Output context this mosaic is tied to. */
            OutputInfo *m_outputInfo{nullptr};
    };

    /**
     * \brief Class for holding input parameters for setting up a gstreamer
     *        pipeline.
     *
     * \ingroup group_edgeai_demo_config
     */
    class InputInfo
    {
        public:
            /** Default constructor. Use the compiler generated default one. */
            InputInfo() = default;

            /** Constructor.
             *
             * @param node Parsed YAML configuration with input information.
             */
            InputInfo(const YAML::Node &node);

            /** Destructor. */
            ~InputInfo();

            /**
             * Generates and stores portions of the GST pipelines used to
             * construct the full set of pipelines matching the input
             * configuration. The user would call this once, passing a vector
             * of pre-process pipeline elements, a vector of scaler pipeline
             * elements a vector of source element names, and a vector of
             * dimensions for sensor path.
             *
             * @param preProcElementVec  A vector of GST pre-process elements.
             * @param preProcScalerElementVec A vector GST scaler elements.
             * @param srcElemNames GST element names used in the source command
             * @param sensorDimVec A vector of dimension for constructing
             *                     the gst resize operation.
             *
             * @returns 0, if successful. A negative value, otherwise.
             */
            int32_t addGstPipeline(vector<vector<GstElement*>>    &preProcElementVec,
                                   vector<vector<GstElement*>>    &preProcScalerElementVec,
                                   const vector<string>           &srcElemNames,
                                   const vector<vector<int32_t>>  &sensorDimVec);

            /** Construct and return a full pipeline specification for input.
             *
             * @param srcPipelines A vector of Generated GST input pipeline per flow
             * @param srcElemNames A vector of appsrc element names used in the
             *        pipeline construction. These names are needed to refer to
             *        the named elements in the pipeline.
             *
             * @returns 0, if successful. A negative value, otherwise.
             */
            int32_t getSrcPipelines(vector<GstElement *>    &srcPipelines,
                                    vector<vector<string>>  &srcElemNames);

            /**
             * Helper function to dump the configuration information.
             *
             * @param prefix Prefix to be added to the log outputs.
             */
            void dumpInfo(const char *prefix="") const;

        private:
            /**
            * Helper function to give appropriate colorconvert element
            * based on plugins available and inputs and outputs can
            * be supported.
            * @param inputFmt Input Format
            * @param outputFmt Output Format
            */
            YAML::Node getColorConvertConfig(string inputFmt, string outputFmt);

        public:
            /** Allowed sources of the input data. Allowed values
             * - /dev/videoX             [Camera]
             * - *%Nd*.jpg   [Image]
             * - *%Nd*.png   [Image]
             * - *.mp4       [Video]
             * - *.avi       [Video]
             *
             *ex:- ../c/d/input_image%02d.jpg
             *     /a/b/c/d/input_image%02d.png
             *     /a/b/c/d/input_video.mp4
             *     /a/b/c/d/input_video.avi
             *
             * The paths to images and videos can be absolute or relative to the directoty
             * the application is launched from.
             *
             * Default is /dev/video2
             */
            string                              m_source;

            /* Unique name assigned to input in config file. */
            string                              m_name;

            /** Source type derived from m_source. This is used for various
             * purposes including debug logging so to avoid deriving it
             * multiple times, it is done once during initialization and
             * stored for later use.
             */
            string                              m_srcType{"camera"};

            /** Vector of Input GstElements. */
            vector<GstElement *>                m_inputElements;

            /** Vector of Sensor GstElements. */
            vector<vector<GstElement*>>         m_sensorElementVec;

            /** Vector of PreProc GstElements. */
            vector<vector<GstElement*>>         m_preProcElementVec;

            /** Vector of Scaler GstElements. */
            vector<vector<vector<GstElement*>>> m_scalerElementVec;

            /** Tee element for flow with this input. */
            vector<GstElement*>                 m_teeElement;

            /** Vector to hold property of Gst Element. */
            vector<vector<const gchar*>>        m_gstElementProperty;

            /** Vector to hold property of Gst Element. */
            bool                                m_scalerIsMulltiSrc{false};

            /** Vector of names for gstreamer appsink on the source side. */
            vector<string>                      m_srcElemNames;

            /** Input data width. */
            int32_t                             m_width{};

            /** Input data height. */
            int32_t                             m_height{};

            /** Start index for multiple file input. */
            int32_t                             m_index{};

            /** Data format for camera input. */
            string                              m_format{"auto"};

            /** Drop frames at appsink if true. */
            bool                                m_drop{true};

            /** Loop file input after EOS. */
            bool                                m_loop{true};

            /** Pattern for GST videotestsrc. */
            string                              m_pattern{"ball"};

            /** v4l subdev id of sensor. */
            string                              m_subdev_id{"/dev/v4l-subdev2"};

            /** Frame rate. */
            string                              m_framerate{};

            int32_t                             m_appSinkBuffDepth{DEMO_CONFIG_APPSINK_BUFF_DEPTH};

            /** Instance Id for a specific instance. */
            int32_t                             m_instId;

            /** member for tracking the instances of this class. */
            static int32_t                      m_numInstances;

            /** if ldc required. */
            bool                                m_ldc{false};

            /** Sensor ID for raw sensor. */
            string                              m_sen_id{"imx219"};
    };

    /**
     * \brief Class for holding output parameters for setting up a gstreamer
     *        pipeline.
     *
     * \ingroup group_edgeai_demo_config
     */
    class OutputInfo
    {
        using MosaicInfoMap = map<int32_t, const MosaicInfo*>;

        public:
            /** Default constructor. Use the compiler generated default one. */
            OutputInfo() = default;

            /** Constructor.
             *
             * @param node Parsed YAML configuration with output information.
             * @param title String to be overlaid over the output buffer.
             */
            OutputInfo(const YAML::Node    &node,
                       const string        &title);

            /** Destructor. */
            ~OutputInfo();

            /** 
             * Generates and stores portions of the GST pipeline used to
             * construct the full pipeline matching the output
             * configuration. This portion includes mosaic (if required)
             * and other necessary elements for final sink.
             *
             * @returns 0, if successful. A negative value, otherwise.
             */
            int32_t appendGstPipeline();

            /** Construct and return pipeline for creating background buffer.
             *
             * @param sinkPipeline Generated GST pipeline
             * @param sinkElemNames A vector of appsrc element names used in the
             *        pipeline construction. These names are needed to refer to
             *        the named elements in the pipeline.
             *
             * @returns 0, if successful. A negative value, otherwise.
             */
            int32_t getBgPipeline(GstElement*       &sinkPipeline,
                                  vector<string>    &sinkElemNames);

            /** Allocates an output buffer for display.
             *
             * @param gstPipe GST pipe context fully constructed and ready to
             *        be used by the inference pipes for starting the flow
             *        execution.
             */
            int32_t allocOutBuff(GstPipe   *gstPipe);

            /** Function for registering the streams generating the display
             * mosaics.
             *
             * This function stores the mosaic information and returns an
             * identifier to be used later by the caller when pushing the
             * data to display, using the process() function.
             *
             * @param mosaicInfo Mosaic parameters
             * @param modelTitle The title to be displayed for this inference 
             * output
             */
            int32_t registerDispParams(const MosaicInfo    *mosaicInfo, 
                                       const string        &modelTitle);

            /**
             * Helper function to dump the configuration information.
             *
             * @param prefix Prefix to be added to the log outputs.
             */
            void dumpInfo(const char *prefix="") const;

        public:
            /** GST pipe instance. */
            GstPipe            *m_gstPipe{nullptr};

            /** Title to be overlaid in the output buffer. */
            string              m_title;

            /** Allowed sink for the output. Allowed values
             * - kmssink                 [Display]
             * - *%Nd*.jpg   [Image]
             * - *%Nd*.png   [Image]
             * - *.mp4       [Video]
             * - *.avi       [Video]
             *
             *ex:- ../c/d/output_image%02d.jpg
             *      /a/b/c/d/output_image%02d.png
             *      /a/b/c/d/output_video.mp4
             *      /a/b/c/d/output_video.avi
             *
             * The paths to images and videos can be absolute or relative to the directoty
             * the application is launched from.
             *
             * Default is kmssink
             */
            string                          m_sink;

            /** Sink element name.*/
            vector<string>                  m_sinkElemNames;

            /** Background sink element name. */
            string                          m_bkgndElemName;

            /** Mosaic element name. */
            string                          m_mosaicElemName;

            /** GST from appsrc to mosaic
             * for all subflows with this output
             */
            vector<vector<GstElement*>>     m_postProcElements;

            /** Mosaic for this output if applicable. */
            vector<GstElement *>            m_mosaicElements;

            /** If the Mosaic element has been added to pipeline. */
            bool                            m_mosaicAdded{false};

            /** Mosaic Sink num whose property is to be set. */
            int32_t                         m_numMosaicSink{0};

            /** Final Display element for this output. */
            vector<GstElement *>            m_dispElements;

            /** If the Display element has been added to pipeline. */
            bool                            m_dispElementAdded{false};

            /** Vector to hold property of Gst Element. */
            vector<vector<const gchar*>>    m_gstElementProperty;

            /** Output display width. */
            int32_t                         m_width{};

            /** Output display height. */
            int32_t                         m_height{};

            /** Connector id to select output display.
             * This field is ignored for sinks other than kmssink
             */
            int32_t                         m_connector{};

            /** Host ip for udp sink.
             * This field is ignored for sinks other than remote
             */
            string                          m_host{"0.0.0.0"};

            /** Port for udp sink.
             * This field is ignored for sinks other than remote
             */
            int32_t                         m_port{8081};

            /** Encoding type for remote sink.
             * This field is ignored for sinks other than remote
             */
            string                          m_encoding{"h264"};

            /** gop size for encoder.
             */
            int32_t                         m_gopSize{30};

            /** bitrate for encoder.
             */
            int32_t                         m_bitrate{10000000};

            /** Use tiperfoverlay.
             */
            string                          m_overlayPerfType{""};

            /** Output buffer. */
            GstWrapperBuffer                m_outBuff;

            /** Instance Id for a specific instance. */
            int32_t                         m_instId;

            /** member for tracking the instances of this class. */
            static int32_t                  m_numInstances;

            /* Map of the infereence pipe to the associated mosaic information
             * for output handling.
             */
            MosaicInfoMap                   m_instIdMosaicMap;

            /* Map of the inference pipe to the associated model title string
             */
            vector<string>                  m_titleMap;

            /** Id for referencing entries in the mosaic info map. */
            int32_t                         m_mosaicCnt{0};

            /** Set if mosaic is enabled */
            bool                            m_mosaicEnabled{true};

            /** Title frame. */
            cv::Mat                         m_titleFrame;

            /** Output image format. */
            string                          m_imageFmt{"RGB"};
    };

    /**
     * \brief Class for holding DL inference model parameters for setting up 
     *        inference pipeline flow.
     *
     * \ingroup group_edgeai_demo_config
     */
    class ModelInfo
    {
        public:
            /** Default constructor. Use the compiler generated default one. */
            ModelInfo() = default;

            /** Constructor.
             *
             * @param node Parsed YAML configuration with model information.
             */
            ModelInfo(const YAML::Node &node);

            /** Destructor. */
            ~ModelInfo();

            /** Initializes the object. The following is done during
             * initialization:
             * - Parse the model specific param.yaml file and extract the
             *   model parameters.
             * - Instantiate an inference object
             * - Create the pre-processing 
             */
            int32_t initialize();

            /** Function for creating and returning a pre-processor object
             *  and a gst pre-process command string, from the given input
             *  information object.
             *
             *  @param inputInfo Input information object
             *  @param debugConfig Debug output generation control
             *  @param preProcElements Generated GST pre-process element vector
             *  @param preProcScalerElements Generated GST scaler element vector
             *  @param preProcObj Fully constructed pre-process object
             *
             * @returns 0, if successful. A negative value, otherwise.
             */
            int32_t createPreprocCntxt(const InputInfo         &inputInfo,
                                       const DebugDumpConfig   &debugConfig,
                                       vector<GstElement *>    &preProcElements,
                                       vector<GstElement *>    &preProcScalerElements,
                                       PreprocessImage        *&preProcObj);

            /** Function for creating and returning a post-processor object
             *  from the given output and mosaic information objects.
             *
             *  @param debugConfig Debug output generation control
             *  @param sensorWidth Width of frame in sensor path
             *  @param sensorHeight Height of frame in sensor path
             *  @param postProcObj Fully constructed post-process object
             *
             * @returns 0, if successful. A negative value, otherwise.
             */
            int32_t createPostprocCntxt(const DebugDumpConfig  &debugConfig,
                                       const int32_t           sensorWidth,
                                       const int32_t           sensorHeight,
                                       PostprocessImage       *&postProcObj);

            /**
             * Helper function to dump the configuration information.
             *
             * @param prefix Prefix to be added to the log outputs.
             */
            void dumpInfo(const char *prefix="") const;

        public:
            /** Inference context. */
            DLInferer              *m_infererObj{nullptr};

            /* Pre-process configuration. */
            PreprocessImageConfig   m_preProcCfg;

            /* Post-processing configuration.*/
            PostprocessImageConfig  m_postProcCfg;

            /** Path to the model. */
            string                  m_modelPath;

            /** Path to the filename with classnames. */
            string                  m_labelsPath;

            /** Alpha value used for blending the sementic segmentation output. */
            float                   m_alpha{0.5f};

            /** Threshold for visualizing the output from the detection models. */
            float                   m_vizThreshold{0.5f};

            /** Number of classification results to pick from the top of the model output. */
            int32_t                 m_topN{5};
    };

    /**
     * \brief Class for holding parameters for specifying pipeline flows. This
     *        class can handle more than one data flow, where a flow is defined
     *        as data flowing through {pre-processing, inference,
     *        post-processing}.
     *
     * \ingroup group_edgeai_demo_config
     */
    class SubFlowInfo
    {
        public:
            /** Default constructor. Use the compiler generated default one. */
            SubFlowInfo() = default;

            /** Constructor.
             *
             * @param inferPipe InferencePipe object.
             * @param preProcObj Pre-process object
             * @param postProcObj Post-process object
             */
            SubFlowInfo(InferencePipe      *inferPipe,
                        PreprocessImage    *preProcObj,
                        PostprocessImage   *postProcObj);

            /** Destructor. */
            ~SubFlowInfo();

            /** Function to start executing wach of the inference pipes created
             * during the initialization phase.
             *
             * @param gstPipe GST pipe context fully constructed and ready to
             *        be used by the inference pipes for starting the flow
             *        execution.
             *
             * @returns 0, if successful. A negative value, otherwise.
             */
            int32_t start(GstPipe   *gstPipe);

            /**
             * Helper function to dump the configuration information.
             *
             * @param prefix Prefix to be added to the log outputs.
             */
            void dumpInfo(const char *prefix="") const;

        public:
            /** Pre-processing context. */
            PreprocessImage            *m_preProcObj{nullptr};

            /** Inference pipe context. */
            InferencePipe              *m_inferPipe{nullptr};

            /** Post-processing context. */
            PostprocessImage           *m_postProcObj{nullptr};

            /** List of display information. */
            MosaicInfo                 *m_mosaicInfo{nullptr};

            /** Id for display. */
            int32_t                     m_dispId{0};
    };

    /**
     * \brief Class for holding parameters for specifying pipeline flows. This
     *        class can handle more than one data flow, where a flow is defined
     *        as data flowing through {pre-processing, inference,
     *        post-processing}.
     *
     * \ingroup group_edgeai_demo_config
     */
    class FlowInfo
    {
        public:
            /** Default constructor. Use the compiler generated default one. */
            FlowInfo() = default;

            /** Constructor.
             *
             * @param flowConfig FlowConfig Structure.
             */
            FlowInfo(FlowConfig &flowConfig);

            /** Destructor. */
            ~FlowInfo();

            /** Initializes the object. The following is done during
             * initialization:
             * - Create the pre-processing, post-processing objects
             * - Update the GST pipelines on the input and output sides
             * - Create inference pipes and register the pre-processing,
             *   model inference, and post-processing objects.
             *
             * At the end of the initialization, the flow will have updated
             * the associated input and output(s) with the flow specific
             * pipeline information. Once all flows go through this, the input
             * and output pipelines will be fully specified.
             *
             * Once the input pipeline, output pipeline, and the flow setups are
             * complete, the calling application can invoke start() on each flow
             * with the fully constructed GST object to start each flow
             * execution.
             *
             * @param modelMap Map of the models initialized prior to this call
             * @param inputMap Map of the inputs initialized prior to this call
             * @param outputMap Map of the outputs initialized prior to this call
             *
             * @returns 0, if successful. A negative value, otherwise.
             */
            int32_t initialize(map<string, ModelInfo*>   &modelMap,
                               map<string, InputInfo*>   &inputMap,
                               map<string, OutputInfo*>  &outputMap);

            /** Construct and return a output pipeline associated with all the
             *  outputs in this flow.
             *
             * @param sinkPipeline Generated GST pipeline
             * @param sinkElemNames A vector of appsrc element names used in the
             *        pipeline construction. These names are needed to refer to
             *        the named elements in the pipeline.
             *
             * @returns 0, if successful. A negative value, otherwise.
             */
            int32_t getSinkPipeline(GstElement*       &sinkPipeline,
                                    vector<string>    &sinkElemNames);

            /** Function to start executing wach of the inference pipes created
             * during the initialization phase.
             *
             * @param gstPipe GST pipe context fully constructed and ready to
             *        be used by the inference pipes for starting the flow
             *        execution.
             *
             * @returns 0, if successful. A negative value, otherwise.
             */
            int32_t start(GstPipe   *gstPipe);

            /** Function for waiting on the exit of all the inference pipes
             * created as a part of this flow.
             */
            void waitForExit();

            /** Function for seding exit signal to each of the inference pipes
             * created as a part of this flow.
             */
            void sendExitSignal();

            /**
             * Helper function to dump the configuration information.
             *
             * @param prefix Prefix to be added to the log outputs.
             */
            void dumpInfo(const char *prefix="") const;

        public:
            /** Source. */
            string                              m_inputId;

            /** List of display information. */
            vector<SubFlowInfo*>                m_subFlowVec;
            
            /** List of all SubFlow Configs. */
            vector<SubFlowConfig>               m_subFlowConfigs;

            /** List of models using this input source. */
            vector<string>                      m_modelIds;

            /** List of outputs. */
            vector<string>                      m_outputIds;

            /** List of display information. */
            vector<MosaicInfo*>                 m_mosaicVec;

            /** List of output information. */
            map<string,vector<OutputInfo*>>     m_outputMap;

            /** List of Dimension for sensor paths of flow. */
            vector<vector<int32_t>>             m_sensorDimVec;

            /** Input frame rate. */
            string                              m_framerate{0};

            /** Instance Id for a specific instance. */
            int32_t                             m_instId;

            /** Debug enable mask. */
            uint32_t                            m_debugEnableMask{0};

            /** Flow level debug control. */
            DebugDumpConfig                     m_debugConfig{};

            /** member for tracking the instances of this class. */
            static int32_t                      m_numInstances;
    };

    /**
     * \brief Demo configuration information. This information does not come
     *        from the YAML specification used for providing critical
     *        parameters for the pre/inference/post processing stages. The
     *        fields provided through this is very application specific.
     *
     * \ingroup group_edgeai_demo_config
     */
    class DemoConfig
    {
        public:
            /** Constructor. */
            DemoConfig();

            /** Function for parsing the demo configuration
             *
             * @param yaml Parsed YAML configuration with configuration information.
             */
            int32_t parse(const YAML::Node &yaml);

            /** Destructor. */
            ~DemoConfig();

            /** Dump configuration. */
            void dumpInfo() const;

        public:
            /** Map of all inputs defined. */
            map<string, InputInfo*>     m_inputMap;

            /** Map of all models defined. */
            map<string, ModelInfo*>     m_modelMap;

            /** Map of all outputs defined. */
            map<string, OutputInfo*>    m_outputMap;

            /** Map of all flows defined. */
            map<string, FlowInfo*>      m_flowMap;

        private:
            /** Vector of input order. */
            vector<string>              m_inputOrder;
            /** Function for parsing the flow information.
             */
            int32_t parseFlowInfo(const YAML::Node &config);
    };

} //namespace ti::edgeai::common

#endif // _TI_EDGEAI_DEMO_CONFIG_H_

