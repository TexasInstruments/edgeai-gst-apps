cmake_minimum_required(VERSION 3.10.0)

include(GNUInstallDirs)

project(perf_stats)

if (NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

message(STATUS "CMAKE_BUILD_TYPE = ${CMAKE_BUILD_TYPE} PROJECT_NAME = ${PROJECT_NAME}")

set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -std=c++17")

if (NOT DEFINED ENV{SOC})
    message(FATAL_ERROR "SOC not defined.")
endif()

set(TARGET_SOC_LOWER $ENV{SOC})

if ("${TARGET_SOC_LOWER}" STREQUAL "j721e")
    set(TARGET_PLATFORM     J7)
    set(TARGET_CPU          A72)
    set(TARGET_OS           LINUX)
    set(TARGET_SOC          J721E)
elseif ("${TARGET_SOC_LOWER}" STREQUAL "j721s2")
    set(TARGET_PLATFORM     J7)
    set(TARGET_CPU          A72)
    set(TARGET_OS           LINUX)
    set(TARGET_SOC          J721S2)
elseif ("${TARGET_SOC_LOWER}" STREQUAL "j784s4")
    set(TARGET_PLATFORM     J7)
    set(TARGET_CPU          A72)
    set(TARGET_OS           LINUX)
    set(TARGET_SOC          J784S4)
elseif ("${TARGET_SOC_LOWER}" STREQUAL "am62a")
    set(TARGET_PLATFORM     SITARA)
    set(TARGET_CPU          A53)
    set(TARGET_OS           LINUX)
    set(TARGET_SOC          AM62A)
elseif ("${TARGET_SOC_LOWER}" STREQUAL "am62x")
    set(TARGET_PLATFORM     SITARA)
    set(TARGET_CPU          A53)
    set(TARGET_OS           LINUX)
    set(TARGET_SOC          AM62X)
else()
    message(FATAL_ERROR "SOC ${TARGET_SOC_LOWER} is not supported.")
endif()

message("SOC=${TARGET_SOC_LOWER}")

add_definitions(
    -DTARGET_CPU=${TARGET_CPU}
    -DTARGET_OS=${TARGET_OS}
    -DSOC_${TARGET_SOC}
)

if ("${TARGET_SOC}" STREQUAL "J721E" OR "${TARGET_SOC}" STREQUAL "J721S2" OR "${TARGET_SOC}" STREQUAL "J784S4" OR "${TARGET_SOC}" STREQUAL "AM62A")
    include_directories(/usr/include/processor_sdk/vision_apps
                        /usr/include/processor_sdk/app_utils)
endif()
include_directories(/usr/include/edgeai-apps-utils/)

set(APP_PERF_STATS_SRCS
    ti_perfstats.cpp)

set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${PROJECT_SOURCE_DIR}/lib/${CMAKE_BUILD_TYPE})
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${PROJECT_SOURCE_DIR}/bin/${CMAKE_BUILD_TYPE})

add_executable(${PROJECT_NAME} ${APP_PERF_STATS_SRCS})
if ("${TARGET_SOC}" STREQUAL "J721E" OR "${TARGET_SOC}" STREQUAL "J721S2" OR "${TARGET_SOC}" STREQUAL "J784S4" OR "${TARGET_SOC}" STREQUAL "AM62A")
    target_link_libraries(${PROJECT_NAME} tivision_apps)
endif()
target_link_libraries(${PROJECT_NAME} edgeai-apps-utils pthread)
