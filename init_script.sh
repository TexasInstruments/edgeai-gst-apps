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


if [ "$(basename "/"$0)" != "init_script.sh" ]
then
    SOURCED=1
fi

cd $(dirname "$(readlink -f "$BASH_SOURCE")")

source ./scripts/detect_soc.sh

export PYTHONPATH=/usr/lib/python3.10/site-packages/

# Disable Neo-DLR phone-home feature
echo '{"enable_phone_home": false}' > $PYTHONPATH/dlr/counter/ccm_config.json

bash /opt/edgeai-gst-apps/scripts/setup_cameras.sh

rm -rf /usr/lib/libvx_tidl_rt.so.map
rm -rf /usr/lib/libtidl_onnxrt_EP.so.map
rm -rf /usr/lib/libtidl_tfl_delegate.so.map

# Link headers and libraries for DLR
mkdir -p /usr/dlr/
ln -snf /usr/lib/python3.10/site-packages/dlr/libdlr.so /usr/dlr/libdlr.so
ln -snf /usr/dlr/libdlr.so /usr/lib/libdlr.so

ldconfig

#Remove stale gstreamer cache
rm -rf ~/.cache/gstreamer-1.0/registry.aarch64.bin

# Set VPAC Freq to 720 MHz to support 8 ch IMX390  use case at 30 FPS
k3conf set clock 290 0 720000000 &> /dev/null
k3conf set clock 48 0 480000000 &> /dev/null

# Increase ulimits for number of open files, to support multi channel demo
ulimit -Sn 10240
ulimit -Hn 40960

export EDGEAI_GST_APPS_PATH=/opt/edgeai-gst-apps
export EDGEAI_DATA_PATH=/opt/edgeai-test-data
export OOB_DEMO_ASSETS_PATH=/opt/oob-demo-assets
export MODEL_ZOO_PATH=/opt/model_zoo
export EDGEAI_VERSION=9.0
export EDGEAI_SDK_VERSION=09_00_00
