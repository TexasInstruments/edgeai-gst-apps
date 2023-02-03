cmake_minimum_required(VERSION 3.10.0)

project(app_config_checker)

include(${CMAKE_CURRENT_SOURCE_DIR}/../cmake/common.cmake)

set(APP_CONFIG_CHECKER_SRCS
    src/app_config_checker_main.cpp)

build_app(${PROJECT_NAME} APP_CONFIG_CHECKER_SRCS)
