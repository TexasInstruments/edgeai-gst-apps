cmake_minimum_required(VERSION 3.10.0)

project(edgeai_utils)

include(${CMAKE_CURRENT_SOURCE_DIR}/../cmake/common.cmake)

set(EDGEAI_UTILS_SRCS
    src/edgeai_perfstats.cpp
    src/ti_logger.cpp)

build_lib(${PROJECT_NAME} EDGEAI_UTILS_SRCS STATIC)
