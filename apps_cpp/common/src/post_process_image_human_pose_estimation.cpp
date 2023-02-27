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

/* Third-party headers. */
#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>

/* Module headers. */
#include <common/include/post_process_image_human_pose_estimation.h>

/**
 * \defgroup group_edgeai_cpp_apps_human_pose_estimation Human Pose Estimation post-processing
 *
 * \brief Class implementing the image based human pose estimation post-processing
 *        logic.
 *
 * \ingroup group_edgeai_cpp_apps_post_proc
 */

namespace ti::edgeai::common
{
using namespace cv;
using namespace std;

vector<vector<int>> CLASS_COLOR_MAP = {{0, 0, 255}, {255, 0, 0},
                                       {0, 255, 0}, {255, 0, 255},
                                       {0, 255, 255}, {255, 255, 0}};

vector<vector<int>> palette = {{255, 128, 0}, {255, 153, 51},
                               {255, 178, 102}, {230, 230, 0},
                               {255, 153, 255}, {153, 204, 255},
                               {255, 102, 255}, {255, 51, 255},
                               {102, 178, 255}, {51, 153, 255},
                               {255, 153, 153}, {255, 102, 102},
                               {255, 51, 51}, {153, 255, 153},
                               {102, 255, 102}, {51, 255, 51},
                               {0, 255, 0}, {0, 0, 255},
                               {255, 0, 0}, {255, 255, 255}};

vector<vector<int>> skeleton = {{16, 14}, {14, 12}, {17, 15}, {15, 13},
                                {12, 13}, {6, 12}, {7, 13}, {6, 7}, {6, 8},
                                {7, 9}, {8, 10}, {9, 11}, {2, 3}, {1, 2},
                                {1, 3}, {2, 4}, {3, 5}, {4, 6}, {5, 7}};

vector<vector<int>> pose_limb_color = {palette[9], palette[9], palette[9],
                                       palette[9], palette[7], palette[7],
                                       palette[7], palette[0], palette[0],
                                       palette[0], palette[0], palette[0],
                                       palette[16], palette[16], palette[16],
                                       palette[16], palette[16], palette[16],
                                       palette[16]};

vector<vector<int>> pose_kpt_color = {palette[16], palette[16], palette[16],
                                      palette[16], palette[16], palette[0],
                                      palette[0], palette[0], palette[0],
                                      palette[0], palette[0], palette[9],
                                      palette[9], palette[9], palette[9],
                                      palette[9], palette[9]};

int radius = 5;

PostprocessImageHumanPoseEstimation::PostprocessImageHumanPoseEstimation(const PostprocessImageConfig   &config,
                                                                         const DebugDumpConfig          &debugConfig):
    PostprocessImage(config,debugConfig)
{
    m_scaleX = static_cast<float>(m_config.outDataWidth)/m_config.inDataWidth;
    m_scaleY = static_cast<float>(m_config.outDataHeight)/m_config.inDataHeight;
}

/**
 * Use OpenCV to do in-place update of a buffer with post processing content like
 * drawing bounding box around a detected object, drawing circles at keypoints
 * and connecting appropriate keypoints with lines in the frame.
 * It can detect the poses of multiple persons.
 * Co-ordinates will be resized according to the output frame size.
 *
 * @param frameData Original Data buffer where in-place updates will happen.
 * @param results
 * @returns Original frame where some in-place post processing done.
 */

void *PostprocessImageHumanPoseEstimation::operator()(void           *frameData,
                                                      VecDlTensorPtr &results)
{
    Mat img = Mat(m_config.outDataHeight, m_config.outDataWidth, CV_8UC3, frameData);
    void *ret = frameData;
    auto *result = results[0];
    float* data = (float*)result->data;

    for(int i = 0; i < result->shape[2] ; i++)
    {
        vector<int> det_bbox;
        float det_score;
        int det_label;
        vector<float> kpt;

        det_score = data[i * 57 + 4];
        det_label = int(data[i * 57 + 5]);

        if(det_score > m_config.vizThreshold) {
            vector<int> color_map = CLASS_COLOR_MAP[det_label];

            for(int j = 6; j < 57; j++)
            {
                kpt.push_back(data[i * 57 + j]);
            }

            det_bbox.push_back(data[i * 57 + 0] * m_scaleX);
            det_bbox.push_back(data[i * 57 + 1] * m_scaleY);
            det_bbox.push_back(data[i * 57 + 2] * m_scaleX);
            det_bbox.push_back(data[i * 57 + 3] * m_scaleY);

            Point p1(det_bbox[0], det_bbox[1]);
            Point p2(det_bbox[2], det_bbox[3]);

            float scale = abs((det_bbox[2] - det_bbox[0]) * (det_bbox[3] - det_bbox[1]))\
                         / float((m_config.outDataWidth * m_config.outDataHeight));
            rectangle(img, p1, p2, Scalar(color_map[0], color_map[1], color_map[2]), 2);
            string id = "Id : " + to_string(det_label);
            putText(img, id, Point(det_bbox[0] + 5, det_bbox[1] + 15),
                    FONT_HERSHEY_DUPLEX, 2.5 * scale, Scalar(color_map[0], color_map[1],
                    color_map[2]), 2);
            stringstream ss;
            ss << fixed << setprecision(1) << det_score;
            string score = "Score : " + ss.str();
            putText(img, score.c_str(), Point(det_bbox[0] + 5,det_bbox[1] + 30),
                    FONT_HERSHEY_DUPLEX, 2.5 * scale, Scalar(color_map[0], color_map[1],
                    color_map[2]), 2);
            int steps = 3;
            int num_kpts = kpt.size()/steps;
            for(int kid = 0; kid < num_kpts; kid++){
                int r = pose_kpt_color[kid][0];
                int g = pose_kpt_color[kid][1];
                int b = pose_kpt_color[kid][2];

                int x_coord = kpt[steps * kid] * m_scaleX;
                int y_coord = kpt[steps * kid + 1] * m_scaleY;
                float conf = kpt[steps * kid + 2];

                if(conf > 0.5){
                    circle(img, Point(x_coord, y_coord), radius, Scalar(r, g, b), -1);
                }
            }

            for(uint64_t sk_id = 0; sk_id < skeleton.size(); sk_id++){
                int r = pose_limb_color[sk_id][0];
                int g = pose_limb_color[sk_id][1];
                int b = pose_limb_color[sk_id][2];

                int p11 = kpt[(skeleton[sk_id][0] - 1) * steps] * m_scaleX;
                int p12 = kpt[(skeleton[sk_id][0] - 1) * steps + 1] * m_scaleY;
                Point pos1 = Point(p11, p12);

                int p21 = kpt[(skeleton[sk_id][1] - 1) * steps] * m_scaleX;
                int p22 = kpt[(skeleton[sk_id][1] - 1) * steps + 1] * m_scaleY;
                Point pos2 = Point(p21, p22);

                float conf1 = kpt[(skeleton[sk_id][0] - 1) * steps + 2];
                float conf2 = kpt[(skeleton[sk_id][1] - 1) * steps + 2];

                if(conf1 > 0.5 && conf2 > 0.5){
                    line(img, pos1, pos2, Scalar(r, g, b), 2, LINE_AA);
                }
            }
        }
    }
    return ret;
}

PostprocessImageHumanPoseEstimation::~PostprocessImageHumanPoseEstimation()
{
}

} // namespace ti::edgeai::common
