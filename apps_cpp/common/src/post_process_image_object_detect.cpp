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

/* Module headers. */
#include <common/include/post_process_image_object_detect.h>

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

PostprocessImageObjDetect::PostprocessImageObjDetect(const PostprocessImageConfig   &config,
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
static void *overlayBoundingBox(void                         *frame,
                                int                          *box,
                                int32_t                      outDataWidth,
                                int32_t                      outDataHeight,
                                const std::string            objectname,
                                uint8_t                      *color)
{
    Mat img = Mat(outDataHeight, outDataWidth, CV_8UC3, frame);
    Scalar box_color(color[0], color[1], color[2]);

    int32_t luma = ((66*(color[0])+129*(color[1])+25*(color[2])+128)>>8)+16;

    Point topleft = Point(box[0], box[1]);
    Point bottomright = Point(box[2], box[3]);

    // Draw bounding box for the detected object
    rectangle(img, topleft, bottomright, box_color, 3);

    Point t_topleft = Point((box[0] + box[2])/2 - 5, (box[1] + box[3])/2 + 5);
    Point t_bottomright = Point((box[0] + box[2])/2 + 120, (box[1] + box[3])/2 - 15);
    Point t_text = Point((box[0] + box[2])/2, (box[1] + box[3])/2);

    // Draw text with detected class with a background box
    rectangle(img, t_topleft, t_bottomright, box_color, -1);

    if(luma >= 128)
    {
        putText(img, objectname, t_text,
            FONT_HERSHEY_SIMPLEX, 0.5, Scalar(0, 0, 0));
    }
    else
    {
        putText(img, objectname, t_text,
            FONT_HERSHEY_SIMPLEX, 0.5, Scalar(255, 255, 255));
    }

    return frame;
}

void *PostprocessImageObjDetect::operator()(void           *frameData,
                                            VecDlTensorPtr &results)
{
    /* The results has three vectors. We assume that the type
     * of all these is the same.
     */
    std::vector<int64_t>    lastDims;
    VecDlTensorPtr          resultRo;
    int32_t                 ignoreIndex;
    void                   *ret     = frameData;

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

    for (auto i = 0; i < numEntries; i++)
    {
        float score;
        int label, adj_class_id, box[4];
        uint8_t color[3];
        std::string objectname;

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

        if (m_config.labelOffsetMap.find(label) != m_config.labelOffsetMap.end())
        {
            adj_class_id = m_config.labelOffsetMap.at(label);
        }
        else
        {
            adj_class_id = m_config.labelOffsetMap.at(0) + label;
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

            color[0] = m_config.datasetInfo.at(adj_class_id).rgbColor[0];
            color[1] = m_config.datasetInfo.at(adj_class_id).rgbColor[1];
            color[2] = m_config.datasetInfo.at(adj_class_id).rgbColor[2];
        }
        else
        {
            objectname = "UNDEFINED";
            color[0] = 20;
            color[1] = 220;
            color[2] = 20;
        }

        overlayBoundingBox(frameData, box, m_config.outDataWidth,
                            m_config.outDataHeight, objectname, color);

#if defined(EDGEAI_ENABLE_OUTPUT_FOR_TEST)
        output.append(objectname + "[ ");

        for(int32_t j = 0; j < 4; j++)
        {
            output.append(std::to_string(box[j]) + ", ");
        }

        output.append("]\n");
#endif // defined(EDGEAI_ENABLE_OUTPUT_FOR_TEST)
    }

#if defined(EDGEAI_ENABLE_OUTPUT_FOR_TEST)
    /* Dump the output object and then increment the frame number. */
    debugObj.logAndAdvanceFrameNum("%s", output.c_str());
#endif // defined(EDGEAI_ENABLE_OUTPUT_FOR_TEST)

    return ret;
}

PostprocessImageObjDetect::~PostprocessImageObjDetect()
{
}

} // namespace ti::edgeai::common

