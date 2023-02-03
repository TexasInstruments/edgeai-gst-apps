cmake_minimum_required(VERSION 3.10.0)

project(app_edgeai)

include(${CMAKE_CURRENT_SOURCE_DIR}/../cmake/common.cmake)

set(APP_EDGEAI_SRCS
    src/app_edgeai_main.cpp)

build_app(${PROJECT_NAME} APP_EDGEAI_SRCS)
