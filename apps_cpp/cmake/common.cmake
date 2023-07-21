include(GNUInstallDirs)
include(CMakePackageConfigHelpers)

add_compile_options(-std=c++17)

option(USE_DLR_RT "Enable DLR inference" ON)
option(USE_TENSORFLOW_RT "Enable Tensorflow inference" ON)
option(USE_ONNX_RT "Enable Onnx inference" ON)

# Specific compile optios across all targets
#add_compile_definitions(MINIMAL_LOGGING)

IF(NOT CMAKE_BUILD_TYPE)
  SET(CMAKE_BUILD_TYPE Release)
ENDIF()

# Turn off output data dumps for testing by default
OPTION(EDGEAI_ENABLE_OUTPUT_FOR_TEST "Enable Output Dumps for test" OFF)

# Check if we got an option from command line
if(EDGEAI_ENABLE_OUTPUT_FOR_TEST)
    message("EDGEAI_ENABLE_OUTPUT_FOR_TEST enabled")
    add_definitions(-DEDGEAI_ENABLE_OUTPUT_FOR_TEST)
endif()

message(STATUS "CMAKE_BUILD_TYPE = ${CMAKE_BUILD_TYPE} PROJECT_NAME = ${PROJECT_NAME}")

SET(CMAKE_FIND_LIBRARY_PREFIXES "" "lib")
SET(CMAKE_FIND_LIBRARY_SUFFIXES ".a" ".lib" ".so")

if(NOT CMAKE_OUTPUT_DIR)
    set(CMAKE_OUTPUT_DIR ${CMAKE_SOURCE_DIR})
endif()
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_OUTPUT_DIR}/lib/${CMAKE_BUILD_TYPE})
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_OUTPUT_DIR}/lib/${CMAKE_BUILD_TYPE})
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_OUTPUT_DIR}/bin/${CMAKE_BUILD_TYPE})

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


set(TENSORFLOW_INSTALL_DIR ${TARGET_FS}/usr/include/tensorflow)
set(ONNXRT_INSTALL_DIR ${TARGET_FS}/usr/include/onnxruntime)
set(TFLITE_INSTALL_DIR ${TARGET_FS}/usr/lib/tflite_2.8)

if(USE_DLR_RT)
add_definitions(-DUSE_DLR_RT)
endif()

if(USE_TENSORFLOW_RT)
add_definitions(-DUSE_TENSORFLOW_RT)
endif()

if(USE_ONNX_RT)
add_definitions(-DUSE_ONNX_RT)
endif()

link_directories(${TARGET_FS}/usr/lib/aarch64-linux-gnu
                 ${TARGET_FS}/usr/lib/
                 )

if(USE_DLR_RT)
link_directories(${TARGET_FS}/usr/lib/python3.10/site-packages/dlr)
endif()

if(USE_TENSORFLOW_RT)
link_directories(${TFLITE_INSTALL_DIR}/ruy-build
                 ${TFLITE_INSTALL_DIR}/xnnpack-build
                 ${TFLITE_INSTALL_DIR}/pthreadpool
                 ${TFLITE_INSTALL_DIR}/fft2d-build
                 ${TFLITE_INSTALL_DIR}/cpuinfo-build
                 ${TFLITE_INSTALL_DIR}/flatbuffers-build
                 ${TFLITE_INSTALL_DIR}/clog-build
                 ${TFLITE_INSTALL_DIR}/farmhash-build
)
endif()

if(USE_ONNX_RT)
endif()

#message("PROJECT_SOURCE_DIR =" ${PROJECT_SOURCE_DIR})
#message("CMAKE_SOURCE_DIR =" ${CMAKE_SOURCE_DIR})

include_directories(${PROJECT_SOURCE_DIR}
                    ${PROJECT_SOURCE_DIR}/..
                    ${PROJECT_SOURCE_DIR}/include
                    SYSTEM ${TARGET_FS}/usr/local/include
                    SYSTEM ${TARGET_FS}/usr/include/gstreamer-1.0
                    SYSTEM ${TARGET_FS}/usr/include/glib-2.0
                    SYSTEM ${TARGET_FS}/usr/lib/glib-2.0/include
                    SYSTEM ${TARGET_FS}/usr/lib/aarch64-linux-gnu/glib-2.0/include
                    SYSTEM ${TARGET_FS}/usr/include/opencv4/
                    SYSTEM ${TARGET_FS}/usr/include/processor_sdk/vision_apps
                    SYSTEM ${TARGET_FS}/usr/include/processor_sdk/app_utils
                    SYSTEM ${TARGET_FS}/usr/include/edgeai_dl_inferer
                    )

if(USE_DLR_RT)
include_directories(${TARGET_FS}/usr/lib/python3.10/site-packages/dlr/include/)
endif()

if(USE_TENSORFLOW_RT)
include_directories(SYSTEM ${TENSORFLOW_INSTALL_DIR}
                    SYSTEM ${TENSORFLOW_INSTALL_DIR}/lite/tools/make/downloads/flatbuffers/include
                    )
endif()

if(USE_ONNX_RT)
include_directories(SYSTEM ${ONNXRT_INSTALL_DIR}/include/onnxruntime
                    SYSTEM ${ONNXRT_INSTALL_DIR}/include/onnxruntime/core/session
                    )
endif()

set(COMMON_LINK_LIBS
    edgeai_utils
    edgeai_common
    edgeai_dl_inferer
    edgeai_pre_process
    edgeai_post_process
    )

set(SYSTEM_LINK_LIBS
    ncurses
    tinfo
    gstreamer-1.0
    glib-2.0
    gobject-2.0
    gstapp-1.0
    opencv_core
    opencv_imgproc
    yaml-cpp
    pthread
    dl
    )

if(NOT ${TARGET_SOC} STREQUAL "AM62X")
set(SYSTEM_LINK_LIBS ${SYSTEM_LINK_LIBS} tivision_apps)
endif()

if(USE_DLR_RT)
set(SYSTEM_LINK_LIBS ${SYSTEM_LINK_LIBS} dlr)
endif()

if(USE_TENSORFLOW_RT)
set(SYSTEM_LINK_LIBS ${SYSTEM_LINK_LIBS} tensorflow-lite)
set(SYSTEM_LINK_LIBS ${SYSTEM_LINK_LIBS}
                     flatbuffers
                     fft2d_fftsg2d
                     fft2d_fftsg
                     cpuinfo
                     clog
                     farmhash
                     ruy_allocator
                     ruy_apply_multiplier
                     ruy_blocking_counter
                     ruy_block_map
                     ruy_context
                     ruy_context_get_ctx
                     ruy_cpuinfo
                     ruy_ctx
                     ruy_denormal
                     ruy_frontend
                     ruy_have_built_path_for_avx2_fma
                     ruy_have_built_path_for_avx512
                     ruy_have_built_path_for_avx
                     ruy_kernel_arm
                     ruy_kernel_avx2_fma
                     ruy_kernel_avx512
                     ruy_kernel_avx
                     ruy_pack_arm
                     ruy_pack_avx2_fma
                     ruy_pack_avx512
                     ruy_pack_avx
                     ruy_prepacked_cache
                     ruy_prepare_packed_matrices
                     ruy_system_aligned_alloc
                     ruy_thread_pool
                     ruy_trmul
                     ruy_tune
                     ruy_wait
                     pthreadpool
                     #xnn lib
                     XNNPACK
)
endif()

if(USE_ONNX_RT)
set(SYSTEM_LINK_LIBS ${SYSTEM_LINK_LIBS} onnxruntime)
endif()

set(SYSTEM_LINK_LIBS ${SYSTEM_LINK_LIBS} pthread dl)

# Function for building a node:
# ARG0: app name
# ARG1: source list
function(build_app)
    set(app ${ARGV0})
    set(src ${ARGV1})
    add_executable(${app} ${${src}})
    target_link_libraries(${app}
                          -Wl,--start-group
                          ${COMMON_LINK_LIBS}
                          ${TARGET_LINK_LIBS}
                          ${SYSTEM_LINK_LIBS}
                          -Wl,--end-group)
endfunction(build_app)

# Function for building a node:
# ARG0: lib name
# ARG1: source list
# ARG2: type (STATIC, SHARED)
function(build_lib)
    set(lib ${ARGV0})
    set(src ${ARGV1})
    set(type ${ARGV2})
    set(version 1.0.0)

    add_library(${lib} ${type} ${${src}})

    get_filename_component(PROJ_DIR "${CMAKE_CURRENT_SOURCE_DIR}" NAME)

    set(INC_DIR_DST ${CMAKE_INSTALL_LIBDIR}/${CMAKE_INSTALL_INCLUDEDIR}/${PROJ_DIR})

    install(TARGETS ${lib}
            LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}  # Shared Libs
            ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}  # Static Libs
            RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}  # Executables, DLLs
            INCLUDES DESTINATION ${INC_DIR_DST}
    )

    # Specify the header files to install
    install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/include
        DESTINATION ${INC_DIR_DST}
    )

endfunction(build_lib)

