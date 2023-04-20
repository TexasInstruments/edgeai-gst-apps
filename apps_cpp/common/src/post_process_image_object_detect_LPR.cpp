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

/* Third-party headers. */
#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>
#include <vector>
#include <map>
#include <utility>
#include <iostream>

/* Module headers. */
#include <common/include/post_process_image_object_detect_lpr.h>

/**
 * \defgroup group_edgeai_cpp_apps_obj_detect Object Detection post-processing
 *
 * \brief Class implementing the image based object detection post-processing
 *        logic.
 *
 * \ingroup group_edgeai_cpp_apps_post_proc
 */

namespace ti::edgeai::common
{
using namespace cv;

PostprocessImageObjDetectLPR::PostprocessImageObjDetectLPR(const PostprocessImageConfig   &config,
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

/**
 * Use OpenCV to do in-place update of a buffer with post processing content like
 * drawing bounding box around a detected object in the frame. Typically used for
 * object classification models.
 * Although OpenCV expects BGR data, this function adjusts the color values so that
 * the post processing can be done on a RGB buffer without extra performance impact.
 *
 * @param frame Original RGB data buffer, where the in-place updates will happen
 * @param box bounding box co-ordinates.
 * @param outDataWidth width of the output buffer.
 * @param outDataHeight Height of the output buffer.
 *
 * @returns original frame with some in-place post processing done
 */

class Wrapper
{
    public:
        void * framePtr;
        float lp_conf;
        Point lp_cord;
};

static  Wrapper& overlayBoundingBox_lpr(void                 *frame,
                                int                          *box,
                                int32_t                      outDataWidth,
                                int32_t                      outDataHeight,
                                const std::string            objectname,
                                float score)
{
    Mat img = Mat(outDataHeight, outDataWidth, CV_8UC3, frame);
    Scalar box_color(20, 220, 20);
    Scalar text_color(0, 0, 0);

    Point topleft = Point(box[0], box[1]);
    Point bottomright = Point(box[2], box[3]);

    // Draw bounding box for the detected object
    rectangle(img, topleft, bottomright, box_color, 3);
    
    float lp_conf = score;
    Point lp_cord;
    if(objectname == "number_plate")
    {
        lp_cord = Point(box[0], box[1]);
    } 
    else
    {
        lp_cord = Point(0, 0);
    }

    Wrapper *obj = new Wrapper();
    obj->framePtr = frame;
    obj->lp_cord = lp_cord;
    obj->lp_conf = lp_conf;

    return *obj;
}

static void * overlay_lp (void * frame,
                          std::vector<std::string> lp_list,
                          Point lp_coordinates_highest_conf,
                          int32_t outDataHeight,
                          int32_t outDataWidth)
{

    Mat img = Mat(outDataHeight, outDataWidth, CV_8UC3, frame);
    Scalar box_color(20, 220, 20);
    Scalar text_color(0, 0, 0);

    // Create a string, name to be overlayed on display for detected classes
    std::string lp_name;
    for(auto ch : lp_list)
    {
        lp_name += ch;
    }

    const int32_t cordFirst = lp_coordinates_highest_conf.x;
    const int32_t cordSecond = lp_coordinates_highest_conf.y;    

    Point topleft = Point(cordFirst, cordSecond - 50);
    Point bottomright = Point(cordFirst + 400, cordSecond);
    Point t_text = Point(cordFirst, cordSecond);

    // Draw text with detected class with a background box
    rectangle(img, topleft, bottomright, box_color, -1);
    putText(img, lp_name, t_text, FONT_HERSHEY_SIMPLEX, 2, text_color, 5, false);
    return frame;
}

std::vector<std::string> PostprocessImageObjDetectLPR::get_lp_list (VecDlTensorPtr &results)
{
    std::vector<int64_t>    lastDims;
    VecDlTensorPtr          resultRo;
    int32_t                 ignoreIndex;
    std::vector<std::string> lp_list;

#if defined(EDGEAI_ENABLE_OUTPUT_FOR_TEST)
    DebugDump              &debugObj = getDebugObj();
    string output;
#endif // defined(EDGEAI_ENABLE_OUTPUT_FOR_TEST)

    for (uint64_t i = 0; i < results.size(); i++)
    {
        auto   *result = results[m_config.resultIndices[i]];
        auto   &shape = result->shape;
        auto    nDims = result->dim;

        resultRo.push_back(result);

        for (auto s: shape)
        {
           if (s == 1)
           {
               nDims--;
           }
        }

        if (nDims == 1)
        {
            lastDims.push_back(1);
        }
        else
        {
            lastDims.push_back(result->shape[result->dim - 1]);
        }
    }

    ignoreIndex = m_config.ignoreIndex;

    auto getVal = [&ignoreIndex, &lastDims, &resultRo] (int32_t iter, int32_t pos)
    {
        int64_t cumuDims = 0;

        for (uint64_t i=0; i < lastDims.size(); i++)
        {
            cumuDims += lastDims[i];
            if (ignoreIndex != -1 && pos >= ignoreIndex)
                pos++;
            auto offset = iter * lastDims[i] + pos - cumuDims + lastDims[i];

            if (pos < cumuDims)
            {
                if (resultRo[i]->type == DlInferType_Int8)
                {
                    return (float)reinterpret_cast<int8_t*>(resultRo[i]->data)[offset];
                }
                else if (resultRo[i]->type == DlInferType_UInt8)
                {
                    return (float)reinterpret_cast<uint8_t*>(resultRo[i]->data)[offset];
                }
                else if (resultRo[i]->type == DlInferType_Int16)
                {
                    return (float)reinterpret_cast<int16_t*>(resultRo[i]->data)[offset];
                }
                else if (resultRo[i]->type == DlInferType_UInt16)
                {
                    return (float)reinterpret_cast<uint16_t*>(resultRo[i]->data)[offset];
                }
                else if (resultRo[i]->type == DlInferType_Int32)
                {
                    return (float)reinterpret_cast<int32_t*>(resultRo[i]->data)[offset];
                }
                else if (resultRo[i]->type == DlInferType_UInt32)
                {
                    return (float)reinterpret_cast<uint32_t*>(resultRo[i]->data)[offset];
                }
                else if (resultRo[i]->type == DlInferType_Int64)
                {
                    return (float)reinterpret_cast<int64_t*>(resultRo[i]->data)[offset];
                }
                else if (resultRo[i]->type == DlInferType_Float32)
                {
                    return (float)reinterpret_cast<float*>(resultRo[i]->data)[offset];
                }
            }
        }
        return (float)0;
    };

    std::map<float, std::string> lp_map;
    
    int32_t numEntries = resultRo[0]->numElem/lastDims[0];

    for(auto i = 0; i < numEntries; i++)
    {
        float score;
        score = getVal(i, m_config.formatter[5]);
        
        if(score > m_config.vizThreshold)
        {
            int box[4];
            int label = getVal(i, m_config.formatter[4]);
            const std::string objectname = m_config.classnames.at(label);

            box[0] = getVal(i, m_config.formatter[0]) * m_scaleX;
            box[1] = getVal(i, m_config.formatter[1]) * m_scaleY;
            box[2] = getVal(i, m_config.formatter[2]) * m_scaleX;
            box[3] = getVal(i, m_config.formatter[3]) * m_scaleY;

            if(objectname != "number_plate")
            {
                // Considering x coordinate for each bounding box
                float box_center_x = (float) box[0];
                // Making map of x-cordinate and predicated class
                lp_map[box_center_x] = objectname;
            }
        } 
    }

    // Create list of predicted class, as map is sorted by box_center_x 
    for(auto p : lp_map) 
    {
        lp_list.push_back(p.second);
    }

    return lp_list;
}
void *PostprocessImageObjDetectLPR::operator()(void           *frameData,
                                               VecDlTensorPtr &results)
{
    /* The results has three vectors. We assume that the type
     * of all these is the same.
     */

    std::vector<int64_t>    lastDims;
    VecDlTensorPtr          resultRo;
    int32_t                 ignoreIndex;

#if defined(EDGEAI_ENABLE_OUTPUT_FOR_TEST)
    DebugDump              &debugObj = getDebugObj();
    string output;
#endif // defined(EDGEAI_ENABLE_OUTPUT_FOR_TEST)

    /* Extract the last dimension from each of the output
     * tensors.
     * last dimension will give the number of values present
     * in given tensor
     * Ex: if shape of a tensor is
     *  [1][1][100][4] -> there are 4 values in the given tensor and 100 entries
     *  [100]          -> 1 value in given tensor and 100 entries, should not
     *                    consider last dim when number of dim is 1
     * Need to ignore all dimensions with value 1 since it does not actually add
     * a dimension (this is similar to squeeze operation in numpy)
     */
    for (uint64_t i = 0; i < results.size(); i++)
    {
        auto   *result = results[m_config.resultIndices[i]];
        auto   &shape = result->shape;
        auto    nDims = result->dim;

        resultRo.push_back(result);

        for (auto s: shape)
        {
           if (s == 1)
           {
               nDims--;
           }
        }

        if (nDims == 1)
        {
            lastDims.push_back(1);
        }
        else
        {
            lastDims.push_back(result->shape[result->dim - 1]);
        }
    }

    ignoreIndex = m_config.ignoreIndex;

    auto getVal = [&ignoreIndex, &lastDims, &resultRo] (int32_t iter, int32_t pos)
    {
        int64_t cumuDims = 0;

        for (uint64_t i=0; i < lastDims.size(); i++)
        {
            cumuDims += lastDims[i];
            if (ignoreIndex != -1 && pos >= ignoreIndex)
                pos++;
            auto offset = iter * lastDims[i] + pos - cumuDims + lastDims[i];

            if (pos < cumuDims)
            {
                if (resultRo[i]->type == DlInferType_Int8)
                {
                    return (float)reinterpret_cast<int8_t*>(resultRo[i]->data)[offset];
                }
                else if (resultRo[i]->type == DlInferType_UInt8)
                {
                    return (float)reinterpret_cast<uint8_t*>(resultRo[i]->data)[offset];
                }
                else if (resultRo[i]->type == DlInferType_Int16)
                {
                    return (float)reinterpret_cast<int16_t*>(resultRo[i]->data)[offset];
                }
                else if (resultRo[i]->type == DlInferType_UInt16)
                {
                    return (float)reinterpret_cast<uint16_t*>(resultRo[i]->data)[offset];
                }
                else if (resultRo[i]->type == DlInferType_Int32)
                {
                    return (float)reinterpret_cast<int32_t*>(resultRo[i]->data)[offset];
                }
                else if (resultRo[i]->type == DlInferType_UInt32)
                {
                    return (float)reinterpret_cast<uint32_t*>(resultRo[i]->data)[offset];
                }
                else if (resultRo[i]->type == DlInferType_Int64)
                {
                    return (float)reinterpret_cast<int64_t*>(resultRo[i]->data)[offset];
                }
                else if (resultRo[i]->type == DlInferType_Float32)
                {
                    return (float)reinterpret_cast<float*>(resultRo[i]->data)[offset];
                }
            }
        }
        return (float)0;
    };
    
    int32_t numEntries = resultRo[0]->numElem/lastDims[0];
    
    std::vector<std::string> lp_list = get_lp_list(results);

    float lp_highest_conf = 0;
    Point lp_coordinates_highest_conf = Point(0, 0);
   
    for (auto i = 0; i < numEntries; i++)
    {
        float score;
        int label, box[4];
        score = getVal(i, m_config.formatter[5]);

        if (score < m_config.vizThreshold)
        {
            continue;
        }
        
        box[0] = getVal(i, m_config.formatter[0]) * m_scaleX;
        box[1] = getVal(i, m_config.formatter[1]) * m_scaleY;
        box[2] = getVal(i, m_config.formatter[2]) * m_scaleX;
        box[3] = getVal(i, m_config.formatter[3]) * m_scaleY;
         
        label = getVal(i, m_config.formatter[4]);
        const std::string objectname = m_config.classnames.at(label);

        Wrapper obj = overlayBoundingBox_lpr(frameData, box, m_config.outDataWidth, m_config.outDataHeight, objectname, score);
        
        frameData = obj.framePtr;
        score = obj.lp_conf;
        Point lp_coordinates = obj.lp_cord;

        if(lp_coordinates.x != 0 && lp_coordinates.y != 0)
        {
            if (score > lp_highest_conf)
            {
                lp_coordinates_highest_conf = lp_coordinates;
                lp_highest_conf = score;
            }
        }

#if defined(EDGEAI_ENABLE_OUTPUT_FOR_TEST)
        output.append(objectname + "[ ");

        for(int32_t j = 0; j < 4; j++)
        {
            output.append(std::to_string(box[j]) + ", ");
        }

        output.append("]\n");
#endif // defined(EDGEAI_ENABLE_OUTPUT_FOR_TEST)
    }

    if(lp_coordinates_highest_conf. x != 0 && lp_coordinates_highest_conf.y != 0 &&  lp_list.size() != 0)
    {
        overlay_lp(frameData, lp_list, lp_coordinates_highest_conf, m_config.outDataHeight, m_config.outDataWidth);
    }

#if defined(EDGEAI_ENABLE_OUTPUT_FOR_TEST)
    /* Dump the output object and then increment the frame number. */
    debugObj.logAndAdvanceFrameNum("%s", output.c_str());
#endif // defined(EDGEAI_ENABLE_OUTPUT_FOR_TEST)

    // return ret;
    return frameData;
}

PostprocessImageObjDetectLPR::~PostprocessImageObjDetectLPR()
{
}

} // namespace ti::edgeai::common