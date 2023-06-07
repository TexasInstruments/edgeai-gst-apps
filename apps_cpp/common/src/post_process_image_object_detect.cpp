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
#include <opencv2/imgcodecs.hpp>

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

    scanner.set_config(zbar::ZBAR_NONE, zbar::ZBAR_CFG_ENABLE, 1);
}

/**
 * Use OpenCV to do in-place update of a buffer with post processing content like
 * drawing bounding box around a detected object in the frame. Typically used for
 * object classification models.
 * Although OpenCV expects BGR data, this function adjusts the color values so that
 * the post processing can be done on a RGB buffer without extra performance impact.
 * 
 * Custom barcode decoding logic/library calls are addedd here
 *
 * @param frame Original RGB data buffer, where the in-place updates will happen
 * @param box bounding box co-ordinates.
 * @param outDataWidth width of the output buffer.
 * @param outDataHeight Height of the output buffer.
 * @param scanner Reference to a zbar scanner instance for decoding codes within the image
 *
 * @returns original frame with some in-place post processing done
 */
static void *overlayBoundingBox(void                         *frame,
                                int                          *box,
                                int32_t                      outDataWidth,
                                int32_t                      outDataHeight,
                                const std::string            objectname,
                                zbar::ImageScanner*           scanner)
{
    const int EXTRA_SPACE = 20;
    const int MAX_LEN = 32;
    
    int x1,y1,x2,y2;
    int baseline_y;
    Size text_size;
    Point topleft, bottomright, t_topleft, t_text, t_bottomright;
    
    Scalar text_color(0, 0, 0);
    Scalar text_box_color(20, 220, 20);
    Scalar bounding_box_color(220, 20, 20);
    Mat img = Mat(outDataHeight, outDataWidth, CV_8UC3, frame);
    Mat grayImage;

    x1=std::max(0,box[0] - EXTRA_SPACE);
    x2=std::min(outDataWidth-1, box[2] + EXTRA_SPACE);
    y1=std::max(0,box[1] - EXTRA_SPACE);
    y2=std::min(outDataHeight-1, box[3] + EXTRA_SPACE);

    topleft = Point(x1, y1);
    bottomright = Point(x2, y2);

    // Draw bounding box for the detected object
    rectangle(img, topleft, bottomright, bounding_box_color, 3);

    //Crop the image and convert to grayscale for decoding 1-d/2-d barcodes
    Rect cropRect = Rect(topleft, bottomright);
    Mat croppedImage = img(cropRect);
    cvtColor(croppedImage, grayImage, COLOR_BGR2GRAY);

    //Scan the image with ZBar library
    zbar::Image zbarImage(grayImage.cols, grayImage.rows, "Y800", grayImage.data, grayImage.cols * grayImage.rows);
    int numSymbols = scanner->scan(zbarImage);
    
    std::string code_data;
    if (numSymbols > 0) {

        for (zbar::Image::SymbolIterator symbol = zbarImage.symbol_begin(); symbol != zbarImage.symbol_end(); ++symbol) {
            code_data = symbol->get_data();
        }
    } else { 
       code_data = std::string("NA");
    }

    if (code_data.length() > MAX_LEN) {
        code_data.erase(MAX_LEN, std::string::npos);
        code_data.append("...");
    }

    text_size = getTextSize(code_data, FONT_HERSHEY_SIMPLEX, 0.5, 1, &baseline_y);

    // Create points for background box around shown text
    t_topleft = Point(x1,y1);
    t_bottomright = Point((box[0] + text_size.width), y1+text_size.height);
    t_text = Point(x1,y1+text_size.height);

    // Draw text with detected code string on a solid background box
    rectangle(img, t_topleft, t_bottomright, text_box_color, -1);
    putText(img, code_data, t_text,
            FONT_HERSHEY_SIMPLEX, 0.5, text_color);

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

        int32_t adj_class_id = m_config.labelOffsetMap.at(label);
        const std::string objectname = m_config.classnames.at(adj_class_id);
        /** Do zbar decoding on however bounding box there are **/


        overlayBoundingBox(frameData, box, m_config.outDataWidth,
                            m_config.outDataHeight, objectname, &scanner);


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

