cmake_minimum_required(VERSION 3.10.0)

project(edgeai_common)

include(${CMAKE_CURRENT_SOURCE_DIR}/../cmake/common.cmake)

set(EDGEAI_COMMON_SRCS
    src/pre_process_image.cpp
    src/post_process_image.cpp
    src/post_process_image_classify.cpp
    src/post_process_image_object_detect.cpp
    src/post_process_image_segmentation.cpp
    src/post_process_image_human_pose_estimation.cpp
    src/edgeai_inference_pipe.cpp
    src/edgeai_demo.cpp
    src/edgeai_cmd_line_parse.cpp
    src/edgeai_gst_wrapper.cpp
    src/edgeai_gst_helper.cpp
    src/edgeai_gstelementmap.cpp
    src/edgeai_demo_config.cpp
    src/edgeai_utils.cpp
    src/edgeai_debug.cpp)

build_lib(${PROJECT_NAME} EDGEAI_COMMON_SRCS STATIC)
