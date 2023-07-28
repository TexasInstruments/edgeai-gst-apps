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

BG_IMAGE=$OOB_DEMO_ASSETS_PATH/wallpaper.jpg

if [ "$BG_IMAGE" != "" ]
then
#get ip addr to overlay
arr=(`ifconfig eth0 2>&1 | grep inet | grep -v inet6`)
ip_eth0=${arr[1]}
arr=(`ifconfig wlp1s0 2>&1 | grep inet | grep -v inet6`)
ip_wlp1s0=${arr[1]}

TEXTOVERLAY="textoverlay font-desc=\"Arial 8\" color=0xFF00FF00 \
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

gcc $EDGEAI_GST_APPS_PATH/scripts/get_fb_resolution.c -o get_fb_resolution
gst-launch-1.0 filesrc location=$BG_IMAGE ! jpegdec ! videoconvert ! \
video/x-raw, format=BGRA ! videoscale ! `./get_fb_resolution` ! \
$GST_OVERLAY_STR \
filesink location=/dev/fb > /dev/null 2>&1
rm -rf get_fb_resolution
fi