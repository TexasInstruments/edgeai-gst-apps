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
#include <stdint.h>
#include <vector>
#include <map>
#include <filesystem>

/* Third-party headers. */
#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>

/* Module headers. */
#include <utils/include/ti_logger.h>
#include <common/include/post_process_image.h>
#include <common/include/post_process_image_classify.h>
#include <common/include/post_process_image_object_detect.h>
#include <common/include/post_process_image_segmentation.h>
#include <common/include/post_process_image_human_pose_estimation.h>


namespace ti::edgeai::common
{
using namespace cv;
using namespace ti::utils;
using namespace ti::dl_inferer;

PostprocessImage::PostprocessImage(const PostprocessImageConfig &config,
                                   const DebugDumpConfig        &debugConfig):
    m_config(config),
    m_debugObj(debugConfig)
{
    m_title = std::string("Model: ") + m_config.modelName;
}

PostprocessImage* PostprocessImage::makePostprocessImageObj(const PostprocessImageConfig    &config,
                                                            const DebugDumpConfig           &debugConfig)
{
    PostprocessImage   *cntxt = nullptr;

    if (config.taskType == "classification")
    {
        cntxt = new PostprocessImageClassify(config,debugConfig);
    }
    else if (config.taskType == "detection")
    {
        cntxt = new PostprocessImageObjDetect(config,debugConfig);
    }
    else if (config.taskType == "segmentation")
    {
        cntxt = new PostprocessImageSemanticSeg(config,debugConfig);
    }
    else if (config.taskType == "human_pose_estimation")
    {
        cntxt = new PostprocessImageHumanPoseEstimation(config,debugConfig);
    }
    else
    {
        LOG_ERROR("Invalid post-processing task type.\n");
    }

    return cntxt;
}

const std::string &PostprocessImage::getTaskType()
{
    return m_config.taskType;
}

PostprocessImage::~PostprocessImage()
{
}

} // namespace ti::edgeai::common

