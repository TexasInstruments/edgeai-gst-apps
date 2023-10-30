/*
 *  Copyright (C) 2023 Texas Instruments Incorporated - http://www.ti.com/
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
#include <string>
#include <vector>

/* Third-party headers. */
#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>

/* Module headers. */
#include <common/include/post_process_image_keypoint_detect.h>

/**
 * \defgroup group_edgeai_cpp_apps_keypoint_detect Keypoint Detection post-processing
 *
 * \brief Class implementing the image based keypoint detection post-processing
 *        logic.
 *
 * \ingroup group_edgeai_cpp_apps_post_proc
 */

namespace ti::edgeai::common
{
using namespace cv;
using namespace std;

PostprocessImageKeypointDetect::PostprocessImageKeypointDetect(const PostprocessImageConfig   &config,
                                                               const DebugDumpConfig          &debugConfig):
    PostprocessImage(config,debugConfig)
{
    if (m_config.normDetect)
    {
        m_scaleX = static_cast<float>(m_config.outDataWidth);
        m_scaleY = static_cast<float>(m_config.outDataHeight);
    }
    else
    {
        m_scaleX = static_cast<float>(m_config.outDataWidth)/m_config.inDataWidth;
        m_scaleY = static_cast<float>(m_config.outDataHeight)/m_config.inDataHeight;
    }
}


void *PostprocessImageKeypointDetect::operator()(void           *frameData,
                                                 VecDlTensorPtr &results)
{
    
    Mat img = Mat(m_config.outDataHeight, m_config.outDataWidth, CV_8UC3, frameData);
    void *ret = frameData;
    auto *result = results[0];
    float* data = (float*)result->data;
    int tensorHeight = result->shape[result->dim - 2];
    int tensorWidth = result->shape[result->dim - 1];

    for(int i = 0; i < tensorHeight ; i++)
    {
        vector<int> det_bbox;
        float det_score;
        int det_label;
        int adj_class_id;
        string objectname = "UNDEFINED";
        vector<float> kpt;
        vector<vector<int8_t>> skeleton = {};


        det_score = data[i * tensorWidth + 4];
        det_label = int(data[i * tensorWidth + 5]);

        if(det_score > m_config.vizThreshold) {

            // Get the keypoint
            for(int j = 6; j < tensorWidth; j++)
            {
                kpt.push_back(data[i * tensorWidth + j]);
            }

            // Draw bounding box
            det_bbox.push_back(data[i * tensorWidth + 0] * m_scaleX);
            det_bbox.push_back(data[i * tensorWidth + 1] * m_scaleY);
            det_bbox.push_back(data[i * tensorWidth + 2] * m_scaleX);
            det_bbox.push_back(data[i * tensorWidth + 3] * m_scaleY);

            Point p1(det_bbox[0], det_bbox[1]);
            Point p2(det_bbox[2], det_bbox[3]);

            rectangle(img, p1, p2, Scalar(0,255,0), 2);
            
            // Draw label
            if (m_config.labelOffsetMap.find(det_label) != m_config.labelOffsetMap.end())
            {
                adj_class_id = m_config.labelOffsetMap.at(det_label);
            }
            else
            {
                adj_class_id = m_config.labelOffsetMap.at(0) + det_label;
            }

            if (m_config.datasetInfo.find(adj_class_id) != m_config.datasetInfo.end())
            {
                objectname = m_config.datasetInfo.at(adj_class_id).name;
                if ("" != m_config.datasetInfo.at(adj_class_id).superCategory)
                {
                    objectname = m_config.datasetInfo.at(adj_class_id).superCategory +
                                "/" +
                                objectname;
                }
                skeleton = m_config.datasetInfo.at(adj_class_id).skeleton;
            }

            putText(img, objectname, Point(det_bbox[0], det_bbox[1] + 15),
                    FONT_HERSHEY_SIMPLEX, 0.5, Scalar(255,0,0), 2);

            // Draw Keypoints
            int num_kpts = kpt.size()/3;
            for(int kidx = 0; kidx < num_kpts; kidx++){
                int x_coord = kpt[3 * kidx] * m_scaleX;
                int y_coord = kpt[3 * kidx + 1] * m_scaleY;
                float conf = kpt[3 * kidx + 2];

                if(conf > 0.5){
                    circle(img, Point(x_coord, y_coord), 3, Scalar(255,0,0), -1);
                }
            }

            // Draw Skeleton
            for(uint64_t sk_id = 0; sk_id < skeleton.size(); sk_id++){

                int p11 = kpt[(skeleton[sk_id][0] - 1) * 3] * m_scaleX;
                int p12 = kpt[(skeleton[sk_id][0] - 1) * 3 + 1] * m_scaleY;
                Point pos1 = Point(p11, p12);

                int p21 = kpt[(skeleton[sk_id][1] - 1) * 3] * m_scaleX;
                int p22 = kpt[(skeleton[sk_id][1] - 1) * 3 + 1] * m_scaleY;
                Point pos2 = Point(p21, p22);

                float conf1 = kpt[(skeleton[sk_id][0] - 1) * 3 + 2];
                float conf2 = kpt[(skeleton[sk_id][1] - 1) * 3 + 2];

                if(conf1 > 0.5 && conf2 > 0.5){
                    line(img, pos1, pos2, Scalar(255,0,0), 1, LINE_AA);
                }
            }
        }
    }

    return ret;
}

PostprocessImageKeypointDetect::~PostprocessImageKeypointDetect()
{
}

} // namespace ti::edgeai::common

