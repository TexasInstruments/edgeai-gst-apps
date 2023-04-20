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

#ifndef _POST_PROCESS_IMAGE_OBJECT_DETECT_LPR_H_
#define _POST_PROCESS_IMAGE_OBJECT_DETECT_LPR_H_

/* Module headers. */
#include <common/include/post_process_image.h>
#include <vector>
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
    /** Post-processing for image based object detection.
     *
     * \ingroup group_edgeai_cpp_apps_obj_detect
     */
    class PostprocessImageObjDetectLPR : public PostprocessImage
    {
        public:
            /** Constructor.
             *
             * @param config Configuration information not present in YAML
             * @param debugConfig Debug Configuration for passing to post process class
             */
            PostprocessImageObjDetectLPR(const PostprocessImageConfig  &config,
                                      const DebugDumpConfig         &debugConfig);

            /** Function operator
             *
             * This is the heart of the class. The application uses this
             * interface to execute the functionality provided by this class.
             *
             * @param frameData Input data frame on which results are overlaid
             * @param results Detection output results from the inference
             */
            void *operator()(void              *frameData,
                             VecDlTensorPtr    &results);
            
            std::vector<std::string> get_lp_list (VecDlTensorPtr &results);

            /** Destructor. */
            ~PostprocessImageObjDetectLPR();

        private:
            /** Multiplicative factor to be applied to X co-ordinates. */
            float                   m_scaleX{1.0f};

            /** Multiplicative factor to be applied to Y co-ordinates. */
            float                   m_scaleY{1.0f};

        private:
            /**
             * Assignment operator.
             *
             * Assignment is not required and allowed and hence prevent
             * the compiler from generating a default assignment operator.
             */
            PostprocessImageObjDetectLPR &
                operator=(const PostprocessImageObjDetectLPR& rhs) = delete;
    };

} // namespace ti::edgeai::common

#endif /* _POST_PROCESS_IMAGE_OBJECT_DETECT_LPR_H_ */
