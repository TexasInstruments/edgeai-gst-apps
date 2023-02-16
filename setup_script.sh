#!/bin/bash

#  Copyright (C) 2021 Texas Instruments Incorporated - http://www.ti.com/
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

if [ "$(basename "/"$0)" != "setup_script.sh" ]
then
    SOURCED=1
fi

current_dir=$(pwd)
cd $(dirname $0)

SOC_LIST=(j721e j721s2 j784s4 am62a)

exit_setup()
{
    echo "Setup FAILED!"
    cd $current_dir
    if [ "$SOURCED" == "1" ]; then
        return
    else
        exit 1
    fi
}

# Get SOC
if [ `arch` == "aarch64" ]; then
    source ./scripts/detect_soc.sh
elif [ "$SOC" == "" ]; then
    echo "Please enter the SOC you want to build for"
    read -p "(`echo ${SOC_LIST[@]}`): " SOC
    export SOC
fi

SOC_VALID=0
for S in ${SOC_LIST[@]}
do
    if [ "$S" == $SOC ]; then
        SOC_VALID=1
        break
    fi
done

if [ "$SOC_VALID" == "0" ]; then
    echo "$SOC is not valid SOC!"
    exit_setup
fi

# Get TOOLCHAIN and TARGET_FS
if [ `arch` != "aarch64" ]; then
    export CROSS_COMPILER_PREFIX=aarch64-none-linux-gnu-
    if [ "$TARGET_FS" == "" ]; then
        echo "Please enter the target filesystem PATH"
        read -e -p "TARGET_FS: " TARGET_FS
        export TARGET_FS
    fi

    if [ "$CROSS_COMPILER_PATH" == "" ]; then
        echo "Please enter the cross compiler toolchain path"
        read -e -p "CROSS_COMPILER_PATH: " CROSS_COMPILER_PATH
        export CROSS_COMPILER_PATH
    fi

    if [ "$INSTALL_PATH" == "" ]; then
        echo "Please enter the install path"
        read -e -p "INSTALL PATH: " INSTALL_PATH
        export INSTALL_PATH
    fi
else
    export TARGET_FS="/"
    export INSTALL_PATH="/"
fi

# Install DL Inferer library and its depencendy
./scripts/install_dl_inferer.sh $*
if [ "$?" -ne "0" ]; then
    exit_setup
fi

# Install TIOVX kernels required for tiovx modules
./scripts/install_tiovx_kernels.sh $*
if [ "$?" -ne "0" ]; then
    exit_setup
fi

# Install TIOVX modules required for custom GST plugins
./scripts/install_tiovx_modules.sh $*
if [ "$?" -ne "0" ]; then
    exit_setup
fi

# Install custom GST plugins which uses TIOVX modules
./scripts/install_gst_plugins.sh $*
if [ "$?" -ne "0" ]; then
    exit_setup
fi

# Build C++ apps
./scripts/compile_cpp_apps.sh $*
if [ "$?" -ne "0" ]; then
    exit_setup
fi

# Build GPIO Libs
./scripts/install_ti_gpio_libs.sh $*
if [ "$?" -ne "0" ]; then
    exit_setup
fi

# Install streamlit
if [ `arch` == "aarch64" ]; then
    pip3 install streamlit --disable-pip-version-check
    ldconfig
fi

cd $current_dir

sync
echo "Setup Done!"
