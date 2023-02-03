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

# Putting display on standby
killall weston 2>/dev/null
sleep 1

BG_IMAGE=/usr/share/demo/
if grep -q sk /proc/device-tree/compatible
then
    BG_IMAGE+=$SOC-sk-wallpaper.jpg
else
    BG_IMAGE+=$SOC-evm-wallpaper.jpg
fi

if [ "$BG_IMAGE" != "" ]
then
#get ip addr to overlay
arr=(`ifconfig eth0 2>&1 | grep inet | grep -v inet6`)
ip_eth0=${arr[1]}
arr=(`ifconfig wlp1s0 2>&1 | grep inet | grep -v inet6`)
ip_wlp1s0=${arr[1]}

TEXTOVERLAY="textoverlay font-desc=\"Arial 8\" color=0xFF000000 \
            valignment=3 halignment=right draw-shadow=false \
            draw-outline=false"

GST_OVERLAY_STR=""
YPOS=0.03
STEP=0.03
if [ "$ip_eth0" == "" -a "$ip_wlp1s0" == "" ]
then
    GST_OVERLAY_STR+="$TEXTOVERLAY text=\"Ethernet and WiFi Not connected, \
                          use UART for accessing the board\" \
                          ypos=$YPOS ! "
    YPOS=`bc <<< $YPOS+$STEP`
fi

if [ "$ip_eth0" != "" ]
then
    GST_OVERLAY_STR+="$TEXTOVERLAY text=\"ip_eth0=$ip_eth0\" ypos=$YPOS !"
    YPOS=`bc <<< $YPOS+$STEP`
    GST_OVERLAY_STR+="$TEXTOVERLAY text=\"user:pwd=root:root\" ypos=$YPOS !"
    YPOS=`bc <<< $YPOS+2*$STEP`
fi

if [ "$ip_wlp1s0" != "" ]
then
    GST_OVERLAY_STR+="$TEXTOVERLAY text=\"ip_wlp1s0=$ip_wlp1s0\" ypos=$YPOS !"
    YPOS=`bc <<< $YPOS+$STEP`
    GST_OVERLAY_STR+="$TEXTOVERLAY text=\"`cat /usr/share/intel9260/hostapd.conf | grep ssid `\" ypos=$YPOS !"
    YPOS=`bc <<< $YPOS+$STEP`
    GST_OVERLAY_STR+="$TEXTOVERLAY text=\"user:pwd=root:root\" ypos=$YPOS !"
    YPOS=`bc <<< $YPOS+2*$STEP`
fi

gcc scripts/get_fb_resolution.c -o get_fb_resolution
gst-launch-1.0 filesrc location=$BG_IMAGE ! jpegdec ! videoconvert ! \
video/x-raw, format=BGRA ! videoscale ! `./get_fb_resolution` ! \
$GST_OVERLAY_STR \
filesink location=/dev/fb > /dev/null 2>&1
rm -rf get_fb_resolution
fi

export PYTHONPATH=/usr/lib/python3.8/site-packages/

# Disable Neo-DLR phone-home feature
echo '{"enable_phone_home": false}' > $PYTHONPATH/dlr/counter/ccm_config.json

bash /opt/edgeai-gst-apps/scripts/setup_cameras.sh

rm -rf /usr/lib/libvx_tidl_rt.so.map
rm -rf /usr/lib/libtidl_onnxrt_EP.so.map
rm -rf /usr/lib/libtidl_tfl_delegate.so.map

# Link headers and libraries for DLR
mkdir -p /usr/dlr/
ln -snf /usr/lib/python3.8/site-packages/dlr/libdlr.so /usr/dlr/libdlr.so
ln -snf /usr/dlr/libdlr.so /usr/lib/libdlr.so

ldconfig

#Remove stale gstreamer cache
rm -rf ~/.cache/gstreamer-1.0/registry.aarch64.bin

# Set VPAC Freq to 720 MHz to support 8 ch IMX390  use case at 30 FPS
k3conf set clock 290 0 720000000 &> /dev/null
k3conf set clock 48 0 480000000 &> /dev/null

source ./scripts/setup_proxy.sh

#Set time
if ! ps -ef  | grep -v grep | grep -q ntpd
then
    ntpd -s
fi

export EDGEAI_GST_APPS_PATH=/opt/edgeai-gst-apps
export EDGEAI_DATA_PATH=/opt/edgeai-test-data
export MODEL_ZOO_PATH=/opt/model_zoo
