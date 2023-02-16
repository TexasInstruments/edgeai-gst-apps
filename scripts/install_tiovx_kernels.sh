#!/bin/bash

#  Copyright (C) 2023 Texas Instruments Incorporated - http://www.ti.com/
#
#  Redistribution and use in source and binary forms, with or without
#  modification, are permitted provided that the following conditions
#  are met:
#
#    Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
#
#    Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the
#    distribution.
#
#    Neither the name of Texas Instruments Incorporated nor the names of
#    its contributors may be used to endorse or promote products derived
#    from this software without specific prior written permission.
#
#  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
#  "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
#  LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
#  A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
#  OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
#  SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
#  LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
#  DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
#  THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
#  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
#  OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

current_dir=$(pwd)
cd $(dirname $0)

if [ `arch` == "aarch64" ]; then
    install_dir="/opt/"
else
    install_dir="../../"
fi
while getopts ":i:dn" flag; do
    case "${flag}" in
        i)
            if [ -z $OPTARG ] || [ ! -d $OPTARG ]; then
                echo "Invalid installation directory "
                cd $current_dir
                exit 1
            fi
            install_dir="$OPTARG"
            ;;
        d)
            build_flag="-DCMAKE_BUILD_TYPE=Debug"
            ;;
        n)
            NO_CLEAN=1
            ;;
        *)
            if [ $OPTARG == i ]; then
                echo "Installation directory not provided"
                cd $current_dir
                exit 1
            fi
            ;;
    esac
done

# Clone edgeai-tiovx-kernels under /opt required for custom GST plugins
cd $install_dir
ls | grep "edgeai-tiovx-kernels"
if [ "$?" -ne "0" ]; then
    git clone --single-branch --branch develop https://git.ti.com/cgit/edgeai/edgeai-tiovx-kernels
    if [ "$?" -ne "0" ]; then
        cd $current_dir
        exit 1
    fi
fi

set -e

if [ `arch` != "aarch64" ]; then
    build_flag="$build_flag -DCMAKE_TOOLCHAIN_FILE=../cmake/cross_compile_aarch64.cmake"
fi

cd edgeai-tiovx-kernels
if [ "$NO_CLEAN" != "1" ]; then
    rm -rf build
fi
if [ ! -d build ]; then
    mkdir build
    cd build
    cmake $build_flag ..
else
    cd build
fi
make -j2
if [ "$INSTALL_PATH" != "" ]; then
    if [ ! -w $TARGET_FS ]; then
        echo "You do not have write permission to $TARGET_FS, adding sudo to install command"
        sudo make -j`nproc` install DESTDIR=$INSTALL_PATH
    else
        make -j`nproc` install DESTDIR=$INSTALL_PATH
    fi
else
    echo "INSTALL_PATH not defined, Skipping install !"
fi

cd $current_dir
