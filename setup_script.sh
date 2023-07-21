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

current_dir=$(pwd)
cd $(dirname $0)

exit_setup()
{
    echo "Setup FAILED! : Make sure you have active network connection"
    cd $current_dir
    exit 1
}

source ./scripts/detect_soc.sh

# Install EdgeAI Apps Utils
./scripts/install_apps_utils.sh $*
if [ "$?" -ne "0" ]; then
    exit_setup
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

cd $current_dir

ldconfig
sync

echo "Setup Done!"
