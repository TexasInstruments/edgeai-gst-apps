cmake_minimum_required(VERSION 3.10.0)

include(GNUInstallDirs)

project(perf_stats)

if (NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

message(STATUS "CMAKE_BUILD_TYPE = ${CMAKE_BUILD_TYPE} PROJECT_NAME = ${PROJECT_NAME}")

set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -std=c++17")

include_directories(/usr/include/processor_sdk/vision_apps
                    ../../apps_cpp)

set(APP_PERF_STATS_SRCS
    ti_perfstats.cpp
    ../../apps_cpp/utils/src/edgeai_perfstats.cpp)

set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${PROJECT_SOURCE_DIR}/lib/${CMAKE_BUILD_TYPE})
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${PROJECT_SOURCE_DIR}/bin/${CMAKE_BUILD_TYPE})

add_executable(${PROJECT_NAME} ${APP_PERF_STATS_SRCS})
target_link_libraries(${PROJECT_NAME} tivision_apps pthread)
