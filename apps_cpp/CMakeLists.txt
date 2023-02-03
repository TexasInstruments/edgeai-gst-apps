cmake_minimum_required(VERSION 3.10.0)

project(edgeai_cpp_demos)

exec_program(pkg-config ARGS --cflags glib-2.0 OUTPUT_VARIABLE GLIB_FLAGS)
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} ${GLIB_FLAGS} -Wall -Wextra")

add_subdirectory(utils)
add_subdirectory(common)
add_subdirectory(app_edgeai)
add_subdirectory(app_config_checker)
