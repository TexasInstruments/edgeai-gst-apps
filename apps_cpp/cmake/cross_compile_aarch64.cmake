# Usage: Please refer to README.md file in the home directory

set(CMAKE_SYSTEM_NAME      Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)

if (DEFINED ENV{CROSS_COMPILER_PREFIX})
    set(CROSS_COMPILER_PREFIX   $ENV{CROSS_COMPILER_PREFIX})
else()
    message("CROSS_COMPILER_PREFIX not defined, Setting to NULL")
endif()

if (DEFINED ENV{CROSS_COMPILER_PATH})
    set(CROSS_COMPILER_PATH     $ENV{CROSS_COMPILER_PATH})
    set(TOOLCHAIN_PREFIX        ${CROSS_COMPILER_PATH}/bin/${CROSS_COMPILER_PREFIX})
    set(CMAKE_C_COMPILER        ${TOOLCHAIN_PREFIX}gcc)
    set(CMAKE_CXX_COMPILER      ${TOOLCHAIN_PREFIX}g++)
    set(CMAKE_AR                ${TOOLCHAIN_PREFIX}ar CACHE FILEPATH "")
    set(CMAKE_LINKER            ${TOOLCHAIN_PREFIX}ld)
    set(CMAKE_OBJCOPY           ${TOOLCHAIN_PREFIX}objcopy)
    set(CMAKE_RANLIB            ${TOOLCHAIN_PREFIX}ranlib CACHE FILEPATH "")
    set(CMAKE_SIZE              ${TOOLCHAIN_PREFIX}size)
    set(CMAKE_STRIP             ${TOOLCHAIN_PREFIX}strip)
else()
    message("CROSS_COMPILER_PATH not defined, Using default TOOLCHAIN")
endif()

if (DEFINED ENV{TARGET_FS})
    set(TARGET_FS               $ENV{TARGET_FS})
    set(CMAKE_SYSROOT           ${TARGET_FS})
else()
    message("TARGET_FS not defined, Using /")
endif()

# search programs, headers and, libraries in the target environment
# programs: make etc
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# Skip the test program compilation
set(CMAKE_C_COMPILER_WORKS 1)
set(CMAKE_CXX_COMPILER_WORKS 1)

# Use list(APPEND) rather than set() so that any variables added by CMake aren't lost!
#
# Here is the docs for this variable:
# https://cmake.org/cmake/help/latest/variable/CMAKE_TRY_COMPILE_PLATFORM_VARIABLES.html
list(APPEND CMAKE_TRY_COMPILE_PLATFORM_VARIABLES CROSS_COMPILER_PATH TARGET_FS TOOLCHAIN_PREFIX)

link_directories(${TARGET_FS}/usr/local/lib/python3.10/dist-packages/dlr
                 )
