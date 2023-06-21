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
#include <common/include/post_process_image_classify.h>

/**
 * \defgroup group_edgeai_cpp_apps_img_classify Image Classification post-processing
 *
 * \brief Class implementing the image classification post-processing logic.
 *
 * \ingroup group_edgeai_cpp_apps_post_proc
 */

namespace ti::edgeai::common
{
using namespace std;
using namespace cv;

#if defined(EDGEAI_ENABLE_OUTPUT_FOR_TEST)
#define INVOKE_OVERLAY_CLASS_LOGIC(T)                    \
    overlayTopNClasses(frameData,                        \
                       reinterpret_cast<T*>(buff->data), \
                       m_config.classnames,              \
                       getDebugObj(),                    \
                       m_config.outDataWidth,            \
                       m_config.outDataHeight,           \
                       labelOffset,                      \
                       m_config.topN,                    \
                       buff->numElem)
#else
#define INVOKE_OVERLAY_CLASS_LOGIC(T)                    \
    overlayTopNClasses(frameData,                        \
                       reinterpret_cast<T*>(buff->data), \
                       m_config.classnames,              \
                       m_config.outDataWidth,            \
                       m_config.outDataHeight,           \
                       labelOffset,                      \
                       m_config.topN,                    \
                       buff->numElem)
#endif // defined(EDGEAI_ENABLE_OUTPUT_FOR_TEST)

PostprocessImageClassify::PostprocessImageClassify(const PostprocessImageConfig &config,
                                                   const DebugDumpConfig        &debugConfig):
    PostprocessImage(config,debugConfig)
{
}

/**
 * Extract the top classes in decreasing order, from the data, 
 * in order to create an argmax tuple
 * A normal sort would have destroyed the original information regarding the
 * index of a certain value. This function returns a vector of a tuple containing
 * both the value and index respectively.
 *
 * @param data An array of data to sort.
 * @param size Number of elements in the input array.
 * @returns Top  values sorted vector containing a tuple of the value and
 *          original index
 */
template <typename T>
static vector<tuple<T, int32_t>> get_argmax_sorted(T       *data,
                                                   int32_t  size)
{
    vector<tuple<T, int32_t>> argmax;

    for (int i = 0; i < size; i++)
    {
        argmax.push_back(make_tuple(data[i], i));
    }

    sort(argmax.rbegin(), argmax.rend());
    return argmax;
}

/**
 * Extract the top N classes in decreasing order, from the data, 
 * in order to create an argmax tuple
 * A normal sort would have destroyed the original information regarding the
 * index of a certain value. This function returns a vector of a tuple containing
 * both the value and index respectively.
 *
 * @param data An array of data to sort.
 * @param size Number of elements in the input array.
 * @returns Top N values sorted vector containing a tuple of the value and
 *          original index
 *          if N > the size of the results vector then an empty vector
 *          is returned.
 */
template <typename T>
static vector<tuple<T, int32_t>> get_topN(T        *data,
                                          int32_t   N,
                                          int32_t   size)
{
    vector<tuple<T, int32_t>> argmax;

    if (N == size)
    {
        return get_argmax_sorted<T>(data, size);
    }
    else if (N < size)
    {
        for (int32_t i = 0; i < N; i++)
        {
            argmax.push_back(make_tuple(data[i], i));
        }

        sort(argmax.rbegin(), argmax.rend());

        for (int32_t i = N; i < size; i++)
        {
            if (get<0>(argmax[N-1]) < data[i])
            {
                argmax[N-1] = make_tuple(data[i], i);
                sort(argmax.rbegin(), argmax.rend());
            }
        }
    }

    return argmax;
}

/**
  * Use OpenCV to do in-place update of a buffer with post processing content like
  * a black rectangle at the top-left corner and text lines describing the
  * detected class names. Typically used for image classification models
  * Although OpenCV expects BGR data, this function adjusts the color values so that
  * the post processing can be done on a RGB buffer without extra performance impact.
  *
  * @param frame Original RGB data buffer, where the in-place updates will happen
  * @param results Reference to a vector of vector of floats representing the output
  *          from an inference API. It should contain 1 vector representing the
  *          probability with which that class is detected in this image.
  * @param size Number of elements in the input array 'results'.
  * @returns original frame with some in-place post processing done
  */
template <typename T1, typename T2>
static T1 *overlayTopNClasses(T1                   *frame,
                              T2                   *results,
                              map<int32_t,string>   classnames,
#if defined(EDGEAI_ENABLE_OUTPUT_FOR_TEST)
                              DebugDump            &debugObj,
#endif // defined(EDGEAI_ENABLE_OUTPUT_FOR_TEST)
                              int32_t               outDataWidth,
                              int32_t               outDataHeight,
                              int32_t               labelOffset,
                              int32_t               N,
                              int32_t               size)
{
    vector<tuple<T2,int32_t>> argmax;
    float txtSize = static_cast<float>(outDataWidth)/POSTPROC_DEFAULT_WIDTH;
    int   rowSize = 40 * outDataWidth/POSTPROC_DEFAULT_WIDTH;
    Scalar text_color(255, 255, 0);
    Scalar text_bg_color(5, 11, 120);

    argmax = get_topN<T2>(results, N, size);
    Mat img = Mat(outDataHeight, outDataWidth, CV_8UC3, frame);

    std::string title = "Recognized Classes (Top " + std::to_string(N) + "):";

    Size totalTextSize = getTextSize(title, FONT_HERSHEY_SIMPLEX, txtSize, 2, nullptr);

    Point bgTopleft = Point(0, (2 * rowSize) - totalTextSize.height - 5);
    Point bgBottomRight = Point(totalTextSize.width + 10, (2 * rowSize) + 3 + 5);
    Point fontCoord = Point(5, 2 * rowSize);

    rectangle(img, bgTopleft, bgBottomRight, text_bg_color, -1);
    putText(img, title.c_str(), fontCoord, FONT_HERSHEY_SIMPLEX, txtSize,
            Scalar(0, 255, 0), 2);

#if defined(EDGEAI_ENABLE_OUTPUT_FOR_TEST)
    string output;
#endif // defined(EDGEAI_ENABLE_OUTPUT_FOR_TEST)

    for (int i = 0; i < N; i++)
    {
        int32_t index = get<1>(argmax[i]) + labelOffset;

        if (index >= 0)
        {
            string str = classnames.at(index);
            int32_t row = i + 3;

#if defined(EDGEAI_ENABLE_OUTPUT_FOR_TEST)
            output.append(str + "\n");
#endif // defined(EDGEAI_ENABLE_OUTPUT_FOR_TEST)

            totalTextSize = getTextSize(str, FONT_HERSHEY_SIMPLEX, txtSize, 2, nullptr);

            bgTopleft = Point(0, (rowSize * row) - totalTextSize.height - 5);
            bgBottomRight = Point(totalTextSize.width + 10, (rowSize * row) + 3 + 5);
            fontCoord = Point(5, rowSize * row);

            rectangle(img, bgTopleft, bgBottomRight, text_bg_color, -1);
            putText(img, str, fontCoord, FONT_HERSHEY_SIMPLEX, txtSize,
                    text_color, 2);
        }
    }

#if defined(EDGEAI_ENABLE_OUTPUT_FOR_TEST)
    /* Dump the current frame number, output object and then
     * increment the frame number.
     */
    debugObj.logAndAdvanceFrameNum("%s", output.c_str());
#endif // defined(EDGEAI_ENABLE_OUTPUT_FOR_TEST)

    return frame;
}

void *PostprocessImageClassify::operator()(void            *frameData,
                                           VecDlTensorPtr  &results)
{
    /* Even though a vector of variants is passed only the first
     * entry is valid.
     */
    auto       *buff = results[0];
    void       *ret = frameData;
    int32_t     labelOffset = m_config.labelOffsetMap.at(0);

    if (buff->type == DlInferType_Int8)
    {
        ret = INVOKE_OVERLAY_CLASS_LOGIC(int8_t);
    }
    else if (buff->type == DlInferType_UInt8)
    {
        ret = INVOKE_OVERLAY_CLASS_LOGIC(uint8_t);
    }
    else if (buff->type == DlInferType_Int16)
    {
        ret = INVOKE_OVERLAY_CLASS_LOGIC(int16_t);
    }
    else if (buff->type == DlInferType_UInt16)
    {
        ret = INVOKE_OVERLAY_CLASS_LOGIC(uint16_t);
    }
    else if (buff->type == DlInferType_Int32)
    {
        ret = INVOKE_OVERLAY_CLASS_LOGIC(int32_t);
    }
    else if (buff->type == DlInferType_UInt32)
    {
        ret = INVOKE_OVERLAY_CLASS_LOGIC(uint32_t);
    }
    else if (buff->type == DlInferType_Int64)
    {
        ret = INVOKE_OVERLAY_CLASS_LOGIC(int64_t);
    }
    else if (buff->type == DlInferType_Float32)
    {
        ret = INVOKE_OVERLAY_CLASS_LOGIC(float);
    }

    return ret;
}

PostprocessImageClassify::~PostprocessImageClassify()
{
}

} // namespace ti::edgeai::common

