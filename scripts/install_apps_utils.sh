#!/bin/bash

#  Copyright (C) 2022 Texas Instruments Incorporated - http://www.ti.com/
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
while getopts ":i:d" flag; do
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
        *)
            if [ $OPTARG == i ]; then
                echo "Installation directory not provided"
                cd $current_dir
                exit 1
            fi
            ;;
    esac
done

# Clone edgeai-apps-utils under /opt
cd $install_dir
ls | grep "edgeai-apps-utils"
if [ "$?" -ne "0" ]; then
    git clone --single-branch --branch EDGEAI_APP_STACK_09_00_00_00 https://git.ti.com/cgit/edgeai/edgeai-apps-utils
    if [ "$?" -ne "0" ]; then
        cd $current_dir
        exit 1
    fi
fi

set -e

# Install if running from target else skip
if [ `arch` == "aarch64" ]; then
    cd edgeai-apps-utils
    rm -rf build
    mkdir build
    cd build
    cmake $build_flag ..
    make -j2
    make install
fi

cd $current_dir
