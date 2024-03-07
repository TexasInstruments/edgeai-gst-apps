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

/* Module headers. */
#include <common/include/post_process_image_segmentation.h>

namespace ti::edgeai::common
{
#define CLIP(X) ( (X) > 255 ? 255 : (X) < 0 ? 0 : X)

// RGB -> YUV
#define RGB2Y(R, G, B) CLIP(( (  66 * (R) + 129 * (G) +  25 * (B) + 128) >> 8) +  16)
#define RGB2U(R, G, B) CLIP(( ( -38 * (R) -  74 * (G) + 112 * (B) + 128) >> 8) + 128)
#define RGB2V(R, G, B) CLIP(( ( 112 * (R) -  94 * (G) -  18 * (B) + 128) >> 8) + 128)

// YUV -> RGB
#define C(Y) ( (Y) - 16  )
#define D(U) ( (U) - 128 )
#define E(V) ( (V) - 128 )

#define YUV2R(Y, U, V) CLIP(( 298 * C(Y)              + 409 * E(V) + 128) >> 8)
#define YUV2G(Y, U, V) CLIP(( 298 * C(Y) - 100 * D(U) - 208 * E(V) + 128) >> 8)
#define YUV2B(Y, U, V) CLIP(( 298 * C(Y) + 516 * D(U)              + 128) >> 8)

#if defined(EDGEAI_ENABLE_OUTPUT_FOR_TEST)
#define INVOKE_BLEND_LOGIC(T)                           \
    blendSegMask(reinterpret_cast<uint8_t*>(frameData), \
                 reinterpret_cast<T*>(buff->data),      \
                 getDebugObj(),                         \
                 m_config.inDataWidth,                  \
                 m_config.inDataHeight,                 \
                 m_config.outDataWidth,                 \
                 m_config.outDataHeight,                \
                 m_config.alpha,                        \
                 m_config.datasetInfo)
#else
#define INVOKE_BLEND_LOGIC(T)                           \
    blendSegMask(reinterpret_cast<uint8_t*>(frameData), \
                 reinterpret_cast<T*>(buff->data),      \
                 m_config.inDataWidth,                  \
                 m_config.inDataHeight,                 \
                 m_config.outDataWidth,                 \
                 m_config.outDataHeight,                \
                 m_config.alpha,                        \
                 m_config.datasetInfo)
#endif // defined(EDGEAI_ENABLE_OUTPUT_FOR_TEST)

PostprocessImageSemanticSeg::PostprocessImageSemanticSeg(const PostprocessImageConfig   &config,
                                                         const DebugDumpConfig          &debugConfig):
    PostprocessImage(config,debugConfig)
{
}

/**
 * Use OpenCV to do in-place update of a buffer with post processing content like
 * alpha blending a specific color for each classified pixel. Typically used for
 * semantic segmentation models.
 * Although OpenCV expects BGR data, this function adjusts the color values so that
 * the post processing can be done on a RGB buffer without extra performance impact.
 * For every pixel in input frame, this will find the scaled co-ordinates for a
 * downscaled result and use the color associated with detected class ID.
 *
 * @param frame Original RGB data buffer, where the in-place updates will happen
 * @param classes Reference to a vector of vector of floats representing the output
 *          from an inference API. It should contain 1 vector describing the class ID
 *          detected for that pixel.
 * @returns original frame with some in-place post processing done
 */
template <typename T1, typename T2>
static T1 *blendSegMask(T1                              *frame,
                        T2                              *classes,
#if defined(EDGEAI_ENABLE_OUTPUT_FOR_TEST)
                        DebugDump                       &debugObj,
#endif // defined(EDGEAI_ENABLE_OUTPUT_FOR_TEST)
                        int32_t                         inDataWidth,
                        int32_t                         inDataHeight,
                        int32_t                         outDataWidth,
                        int32_t                         outDataHeight,
                        float                           alpha,
                        std::map<int32_t, DatasetInfo>  datasetInfo)
{
    uint8_t    *ptr;
    uint8_t     a;
    uint8_t     sa;
    uint8_t     r;
    uint8_t     g;
    uint8_t     b;
    uint8_t     r_m;
    uint8_t     g_m;
    uint8_t     b_m;
    int32_t     w;
    int32_t     h;
    int32_t     sw;
    int32_t     sh;
    int32_t     class_id;

    a  = alpha * 256;
    sa = (1 - alpha ) * 256;

#if defined(EDGEAI_ENABLE_OUTPUT_FOR_TEST)
    string output;
#endif // defined(EDGEAI_ENABLE_OUTPUT_FOR_TEST)

    // Here, (w, h) iterate over frame and (sw, sh) iterate over classes
    for (h = 0; h < outDataHeight; h++)
    {
        sh = (int32_t)(h * inDataHeight / outDataHeight);
        ptr = frame + h * (outDataWidth * 3);

        for (w = 0; w < outDataWidth; w++)
        {
            int32_t index;

            sw = (int32_t)(w * inDataWidth / outDataWidth);

            // Get the RGB values from original image
            r = *(ptr + 0);
            g = *(ptr + 1);
            b = *(ptr + 2);

            // sw and sh are scaled co-ordiates over the results[0] vector
            // Get the color corresponding to class detected at this co-ordinate
            index = (int32_t)(sh * inDataWidth + sw);
            class_id =  classes[index];

            if (datasetInfo.find(class_id) != datasetInfo.end())
            {
                // get color from dataset information
                r_m = datasetInfo.at(class_id).rgbColor[0];
                g_m = datasetInfo.at(class_id).rgbColor[1];
                b_m = datasetInfo.at(class_id).rgbColor[2];
            }
            else
            {
                // random color assignment based on class-id's
                r_m = 10 * class_id;
                g_m = 20 * class_id;
                b_m = 30 * class_id;
            }

            // Blend the original image with mask value
            *(ptr + 0) = ((r * a) + (r_m * sa)) / 255;
            *(ptr + 1) = ((g * a) + (g_m * sa)) / 255;
            *(ptr + 2) = ((b * a) + (b_m * sa)) / 255;

            ptr += 3;
        }
    }

#if defined(EDGEAI_ENABLE_OUTPUT_FOR_TEST)
    output.append("[ ");
    for (h = 0; h < inDataHeight; h++)
    {
        for (w = 0; w < inDataWidth; w++)
        {
            int32_t index;

            index = (int32_t)(h * inDataHeight + w);
            class_id =  classes[index];
            output.append(std::to_string(class_id) + "  ");
        }
    }
    output.append(" ]");

    /* Dump the output object and then increment the frame number. */
    debugObj.logAndAdvanceFrameNum("%s", output.c_str());
#endif // defined(EDGEAI_ENABLE_OUTPUT_FOR_TEST)

    return frame;
}

void *PostprocessImageSemanticSeg::operator()(void             *frameData,
                                              VecDlTensorPtr   &results)
{
    /* Even though a vector of variants is passed only the first
     * entry is valid.
     */
    auto *buff = results[0];
    void *ret  = frameData;

    if (buff->type == DlInferType_Int8)
    {
        ret = INVOKE_BLEND_LOGIC(int8_t);
    }
    else if (buff->type == DlInferType_UInt8)
    {
        ret = INVOKE_BLEND_LOGIC(uint8_t);
    }
    else if (buff->type == DlInferType_Int16)
    {
        ret = INVOKE_BLEND_LOGIC(int16_t);
    }
    else if (buff->type == DlInferType_UInt16)
    {
        ret = INVOKE_BLEND_LOGIC(uint16_t);
    }
    else if (buff->type == DlInferType_Int32)
    {
        ret = INVOKE_BLEND_LOGIC(int32_t);
    }
    else if (buff->type == DlInferType_UInt32)
    {
        ret = INVOKE_BLEND_LOGIC(uint32_t);
    }
    else if (buff->type == DlInferType_Int64)
    {
        ret = INVOKE_BLEND_LOGIC(int64_t);
    }
    else if (buff->type == DlInferType_Float32)
    {
        ret = INVOKE_BLEND_LOGIC(float);
    }

    return ret;
}

PostprocessImageSemanticSeg::~PostprocessImageSemanticSeg()
{
}

} // namespace ti::edgeai::common

