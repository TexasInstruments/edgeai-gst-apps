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

topdir=$EDGEAI_GST_APPS_PATH
usb_camera=`ls /dev/v4l/by-path/*usb*video-index0 | head -1 | xargs readlink -f`
usb_fmt=jpeg
usb_width=1280
usb_height=720

BRIGHTWHITE='\033[0;37;1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
NOCOLOR='\033[0m'

####################################################################################################

export TEST_ENGINE_DEBUG=1
config_file="$topdir/tests/test_config.yaml"
parse_script="$topdir/tests/parse_log_data.py"
timeout=30
filter=""
measure_cpuload="false"

####################################################################################################
cleanup() {
	echo
	echo "[Ctrl-C] Killing the script..."
}

# TODO: The trap is not reliable currently, need to be fixed
trap cleanup SIGINT

# Setup the source and sink in the test config YAML file
sed -i "s@source:.*@source: $usb_camera@" $config_file
sed -i "s@format:.*@format: $usb_fmt@" $config_file
sed -i "1,/width:.*/s//width: $usb_width/" $config_file
sed -i "1,/height:.*/s//height: $usb_height/" $config_file
sed -i "s@sink:.*@sink: kmssink@" $config_file

for test_suite in "OPTIFLOW-PERF-USBCAM"; do
	cd $(dirname $0)
	./test_engine.sh "OPTIFLOW-PERF-USBCAM" $config_file $timeout $parse_script "$filter" $measure_cpuload
done