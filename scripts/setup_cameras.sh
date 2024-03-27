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

GREEN='\033[0;32m'
NOCOLOR='\033[0m'

IMX219_CAM_FMT="${IMX219_CAM_FMT:-[fmt:SRGGB8_1X8/1920x1080]}"
IMX390_CAM_FMT="${IMX390_CAM_FMT:-[fmt:SRGGB12_1X12/1936x1100 field: none]}"
OV2312_CAM_FMT="${OV2312_CAM_FMT:-[fmt:SBGGI10_1X10/1600x1300 field: none]}"
OV5640_CAM_FMT="${OV5640_CAM_FMT:-[fmt:YUYV8_1X16/1280x720@1/30]}"

declare -A ALL_UB960_FMT_STR
declare -A ALL_CDNS_FMT_STR
declare -A ALL_CSI2RX_FMT_STR

setup_routes(){
    for i in "${!ALL_UB960_FMT_STR[@]}"
    do
        id="$(cut -d',' -f1 <<<"$i")"
        name="$(cut -d',' -f2 <<<"$i")"
        # UB960 ROUTING & FORMATS
        media-ctl -d $id -R "'$name' [${ALL_UB960_FMT_STR[$i]}]"

        for name in `media-ctl -d $id -p | grep entity | grep ov2312 | cut -d ' ' -f 5`; do
            UB953_NAME=`media-ctl -d $id -p -e "ov2312 $name" | grep ub953 | cut -d "\"" -f 2`
            UB960_NAME=`media-ctl -d $id -p -e "$UB953_NAME" | grep ub960 | cut -d "\"" -f 2`
            UB960_PAD=`media-ctl -d $id -p -e "$UB953_NAME" | grep ub960 | cut -d : -f 2 | awk '{print $1}'`
            media-ctl -d $id -V "'$UB960_NAME':$UB960_PAD/0 $OV2312_CAM_FMT"
            media-ctl -d $id -V "'$UB960_NAME':$UB960_PAD/1 $OV2312_CAM_FMT"
        done

        for name in `media-ctl -d $id -p | grep entity | grep imx390 | cut -d ' ' -f 5`; do
            UB953_NAME=`media-ctl -d $id -p -e "imx390 $name" | grep ub953 | cut -d "\"" -f 2`
            UB960_NAME=`media-ctl -d $id -p -e "$UB953_NAME" | grep ub960 | cut -d "\"" -f 2`
            UB960_PAD=`media-ctl -d $id -p -e "$UB953_NAME" | grep ub960 | cut -d : -f 2 | awk '{print $1}'`
            media-ctl -d $id -V "'$UB960_NAME':$UB960_PAD $IMX390_CAM_FMT"
        done
    done

    # CDNS ROUTING
    for i in "${!ALL_CDNS_FMT_STR[@]}"
    do
        id="$(cut -d',' -f1 <<<"$i")"
        name="$(cut -d',' -f2 <<<"$i")"
        # CDNS ROUTING & FORMATS
        media-ctl -d $id -R "'$name' [${ALL_CDNS_FMT_STR[$i]}]"

        for name in `media-ctl -d $id -p | grep entity | grep ov2312 | cut -d ' ' -f 5`; do
            UB953_NAME=`media-ctl -d $id -p -e "ov2312 $name" | grep ub953 | cut -d "\"" -f 2`
            UB960_NAME=`media-ctl -d $id -p -e "$UB953_NAME" | grep ub960 | cut -d "\"" -f 2`
            UB960_PAD=`media-ctl -d $id -p -e "$UB953_NAME" | grep ub960 | cut -d : -f 2 | awk '{print $1}'`
            CSI_PAD0=`media-ctl -d $id -p -e "$UB960_NAME" | grep $UB960_PAD/0.*[ACTIVE] | cut -d "/" -f 3 | awk '{print $1}'`
            CSI_PAD1=`media-ctl -d $id -p -e "$UB960_NAME" | grep $UB960_PAD/1.*[ACTIVE] | cut -d "/" -f 3 | awk '{print $1}'`
            CSI_BRIDGE_NAME=`media-ctl -d $id -p -e "$UB960_NAME" | grep csi-bridge | cut -d "\"" -f 2`
            media-ctl -d $id -V "'$CSI_BRIDGE_NAME':0/$CSI_PAD0 $OV2312_CAM_FMT"
            media-ctl -d $id -V "'$CSI_BRIDGE_NAME':0/$CSI_PAD1 $OV2312_CAM_FMT"
        done

        for name in `media-ctl -d $id -p | grep entity | grep imx390 | cut -d ' ' -f 5`; do
            UB953_NAME=`media-ctl -d $id -p -e "imx390 $name" | grep ub953 | cut -d "\"" -f 2`
            UB960_NAME=`media-ctl -d $id -p -e "$UB953_NAME" | grep ub960 | cut -d "\"" -f 2`
            UB960_PAD=`media-ctl -d $id -p -e "$UB953_NAME" | grep ub960 | cut -d : -f 2 | awk '{print $1}'`
            CSI_PAD=`media-ctl -d $id -p -e "$UB960_NAME" | grep $UB960_PAD/.*[ACTIVE] | cut -d "/" -f 3 | awk '{print $1}'`
            CSI_BRIDGE_NAME=`media-ctl -d $id -p -e "$UB960_NAME" | grep csi-bridge | cut -d "\"" -f 2`
            media-ctl -d $id -V "'$CSI_BRIDGE_NAME':0/$CSI_PAD $IMX390_CAM_FMT"
        done
    done

    # CSI2RX ROUTING
    for i in "${!ALL_CSI2RX_FMT_STR[@]}"
    do
        id="$(cut -d',' -f1 <<<"$i")"
        name="$(cut -d',' -f2 <<<"$i")"
        media-ctl -d $id -R "'$name' [${ALL_CSI2RX_FMT_STR[$i]}]"
    done
}

setup_imx390(){
    i=0
    for media_id in {0..3}; do
    # UB953 FORMATS
    UB960_FMT_STR=""
    CDNS_FMT_STR=""
    CSI2RX_FMT_STR=""
    for name in `media-ctl -d $media_id -p | grep entity | grep imx390 | cut -d ' ' -f 5`; do

        CAM_SUBDEV=`media-ctl -d $media_id -p -e "imx390 $name" | grep v4l-subdev | awk '{print $4}'`
        v4l2-ctl -d $CAM_SUBDEV --set-ctrl wide_dynamic_range=0

        UB953_NAME=`media-ctl -d $media_id -p -e "imx390 $name" | grep ub953 | cut -d "\"" -f 2`
        media-ctl -d $media_id -V "'$UB953_NAME':0 $IMX390_CAM_FMT"

        UB960_NAME=`media-ctl -d $media_id -p -e "$UB953_NAME" | grep ub960 | cut -d "\"" -f 2`
        UB960_PAD=`media-ctl -d $media_id -p -e "$UB953_NAME" | grep ub960 | cut -d : -f 2 | awk '{print $1}'`

        CSI_BRIDGE_NAME=`media-ctl -d $media_id -p -e "$UB960_NAME" | grep csi-bridge | cut -d "\"" -f 2`

        CSI2RX_NAME=`media-ctl -d $media_id -p -e "$CSI_BRIDGE_NAME" | grep "ticsi2rx\"" | cut -d "\"" -f 2`

        LAST_PAD=`echo ${ALL_UB960_FMT_STR[$media_id,$UB960_NAME]} | rev | cut -d'/' -f 1 | rev`
        LAST_PAD=${LAST_PAD:0:1}
        if [[ "$LAST_PAD" == "" ]] ; then
            NEXT_PAD=$UB960_PAD
        else
            NEXT_PAD=$(($LAST_PAD+1))
        fi

        CSI2RX_CONTEXT_NAME="$CSI2RX_NAME context $((NEXT_PAD+1))"

        UB960_FMT_STR="${UB960_PAD}/0 -> 4/$(($NEXT_PAD)) [1]"
        CDNS_FMT_STR="0/${NEXT_PAD} -> 1/$(($NEXT_PAD)) [1]"
        CSI2RX_FMT_STR="0/${NEXT_PAD} -> $(($NEXT_PAD+2))/0 [1]"

        # Append UB960 Routes
        if [[ -v "ALL_UB960_FMT_STR[$media_id,$UB960_NAME]" ]] ; then
            ALL_UB960_FMT_STR[$media_id,$UB960_NAME]="${ALL_UB960_FMT_STR[$media_id,$UB960_NAME]}, $UB960_FMT_STR"
        else
            ALL_UB960_FMT_STR[$media_id,$UB960_NAME]="$UB960_FMT_STR"
        fi

        # Append CDNS Routes
        if [[ -v "ALL_CDNS_FMT_STR[$media_id,$CSI_BRIDGE_NAME]" ]] ; then
            ALL_CDNS_FMT_STR[$media_id,$CSI_BRIDGE_NAME]="${ALL_CDNS_FMT_STR[$media_id,$CSI_BRIDGE_NAME]}, $CDNS_FMT_STR"
        else
            ALL_CDNS_FMT_STR[$media_id,$CSI_BRIDGE_NAME]="$CDNS_FMT_STR"
        fi

        # Append CSIRX Routes
        if [[ -v "ALL_CSI2RX_FMT_STR[$media_id,$CSI2RX_NAME]" ]] ; then
            ALL_CSI2RX_FMT_STR[$media_id,$CSI2RX_NAME]="${ALL_CSI2RX_FMT_STR[$media_id,$CSI2RX_NAME]}, $CSI2RX_FMT_STR"
        else
            ALL_CSI2RX_FMT_STR[$media_id,$CSI2RX_NAME]="$CSI2RX_FMT_STR"
        fi
        CAM_DEV=`media-ctl -d $media_id -p -e "$CSI2RX_CONTEXT_NAME" | grep video | awk '{print $4}'`
        CAM_DEV_NAME=/dev/video-imx390-cam$i

        CAM_SUBDEV_NAME=/dev/v4l-imx390-subdev$i

        ln -snf $CAM_DEV $CAM_DEV_NAME
        ln -snf $CAM_SUBDEV $CAM_SUBDEV_NAME

        v4l2-ctl -d $CAM_SUBDEV_NAME --set-ctrl red_balance=256
        v4l2-ctl -d $CAM_SUBDEV_NAME --set-ctrl blue_balance=256

        echo -e "${GREEN}IMX390 Camera $i detected${NOCOLOR}"
        echo "    device = $CAM_DEV_NAME"
        echo "    name = imx390"
        echo "    format = $IMX390_CAM_FMT"
        echo "    subdev_id = $CAM_SUBDEV_NAME"
        echo "    isp_required = yes"
        echo "    ldc_required = yes"

        ((i++))
    done
    done
}

setup_ov2312(){
    i=0
    for media_id in {0..3}; do
    # UB953 FORMATS
    UB960_FMT_STR=""
    CDNS_FMT_STR=""
    CSI2RX_FMT_STR=""
    for name in `media-ctl -d $media_id -p | grep entity | grep ov2312 | cut -d ' ' -f 5`; do

        CAM_SUBDEV=`media-ctl -d $media_id -p -e "ov2312 $name" | grep v4l-subdev | awk '{print $4}'`

        UB953_NAME=`media-ctl -d $media_id -p -e "ov2312 $name" | grep ub953 | cut -d "\"" -f 2`
        media-ctl -d $media_id -R "'$UB953_NAME' [0/0 -> 1/0 [1], 0/1 -> 1/1 [1]]"
        media-ctl -d $media_id -V "'$UB953_NAME':0/0 $OV2312_CAM_FMT"
        media-ctl -d $media_id -V "'$UB953_NAME':0/1 $OV2312_CAM_FMT"

        UB960_NAME=`media-ctl -d $media_id -p -e "$UB953_NAME" | grep ub960 | cut -d "\"" -f 2`
        UB960_PAD=`media-ctl -d $media_id -p -e "$UB953_NAME" | grep ub960 | cut -d : -f 2 | awk '{print $1}'`

        CSI_BRIDGE_NAME=`media-ctl -d $media_id -p -e "$UB960_NAME" | grep csi-bridge | cut -d "\"" -f 2`

        CSI2RX_NAME=`media-ctl -d $media_id -p -e "$CSI_BRIDGE_NAME" | grep "ticsi2rx\"" | cut -d "\"" -f 2`

        CSI2RX_CONTEXT_NAME_IR="$CSI2RX_NAME context $(($UB960_PAD*2 + 1))"
        CSI2RX_CONTEXT_NAME_RGB="$CSI2RX_NAME context $(($UB960_PAD*2 + 2))"

        UB960_FMT_STR="${UB960_PAD}/0 -> 4/$(($UB960_PAD * 2)) [1], ${UB960_PAD}/1 -> 4/$(($UB960_PAD * 2  + 1)) [1]"
        CDNS_FMT_STR="0/$(($UB960_PAD * 2)) -> 1/$(($UB960_PAD * 2)) [1], 0/$(($UB960_PAD * 2 + 1)) -> 1/$(($UB960_PAD * 2 + 1)) [1]"
        CSI2RX_FMT_STR="0/$(($UB960_PAD * 2)) -> $(($UB960_PAD * 2 + 2))/0 [1], 0/$(($UB960_PAD * 2 + 1)) -> $(($UB960_PAD * 2 + 3))/0 [1]"

        # Append UB960 Routes
        if [[ -v "ALL_UB960_FMT_STR[$media_id,$UB960_NAME]" ]] ; then
            ALL_UB960_FMT_STR[$media_id,$UB960_NAME]="${ALL_UB960_FMT_STR[$media_id,$UB960_NAME]}, $UB960_FMT_STR"
        else
            ALL_UB960_FMT_STR[$media_id,$UB960_NAME]="$UB960_FMT_STR"
        fi
        # Append CDNS Routes
        if [[ -v "ALL_CDNS_FMT_STR[$media_id,$CSI_BRIDGE_NAME]" ]] ; then
            ALL_CDNS_FMT_STR[$media_id,$CSI_BRIDGE_NAME]="${ALL_CDNS_FMT_STR[$media_id,$CSI_BRIDGE_NAME]}, $CDNS_FMT_STR"
        else
            ALL_CDNS_FMT_STR[$media_id,$CSI_BRIDGE_NAME]="$CDNS_FMT_STR"
        fi
        # Append CSIRX Routes
        if [[ -v "ALL_CSI2RX_FMT_STR[$media_id,$CSI2RX_NAME]" ]] ; then
            ALL_CSI2RX_FMT_STR[$media_id,$CSI2RX_NAME]="${ALL_CSI2RX_FMT_STR[$media_id,$CSI2RX_NAME]}, $CSI2RX_FMT_STR"
        else
            ALL_CSI2RX_FMT_STR[$media_id,$CSI2RX_NAME]="$CSI2RX_FMT_STR"
        fi

        IR_CAM_DEV=`media-ctl -d $media_id -p -e "$CSI2RX_CONTEXT_NAME_IR" | grep video | awk '{print $4}'`
        RGB_CAM_DEV=`media-ctl -d $media_id -p -e "$CSI2RX_CONTEXT_NAME_RGB" | grep video | awk '{print $4}'`
        IR_CAM_DEV_NAME=/dev/video-ov2312-ir-cam$i
        RGB_CAM_DEV_NAME=/dev/video-ov2312-rgb-cam$i

        CAM_SUBDEV_NAME=/dev/v4l-ov2312-subdev$i

        ln -snf $IR_CAM_DEV $IR_CAM_DEV_NAME
        ln -snf $RGB_CAM_DEV $RGB_CAM_DEV_NAME
        ln -snf $CAM_SUBDEV $CAM_SUBDEV_NAME

        echo -e "${GREEN}OV2312 Camera $i detected${NOCOLOR}"
        echo "    device IR = $IR_CAM_DEV_NAME"
        echo "    device RGB = $RGB_CAM_DEV_NAME"
        echo "    name = ov2312"
        echo "    format = $OV2312_CAM_FMT"
        echo "    subdev_id = $CAM_SUBDEV_NAME"
        echo "    isp_required = yes"
        echo "    ldc_required = no"

        ((i++))
    done
    done
}

setup_imx219(){
    count=0
    for media_id in {0..3}; do
    for name in `media-ctl -d $media_id -p | grep entity | grep imx219 | cut -d ' ' -f 5`; do
        CAM_SUBDEV=`media-ctl -d $media_id -p -e "imx219 $name" | grep v4l-subdev | awk '{print $4}'`
        media-ctl -d $media_id --set-v4l2 ''"\"imx219 $name\""':0 '$IMX219_CAM_FMT''

        CSI_BRIDGE_NAME=`media-ctl -d $media_id -p -e "imx219 $name" | grep csi-bridge | cut -d "\"" -f 2`
        CSI2RX_NAME=`media-ctl -d $media_id -p -e "$CSI_BRIDGE_NAME" | grep "ticsi2rx\"" | cut -d "\"" -f 2`
        CSI2RX_CONTEXT_NAME="$CSI2RX_NAME context 0"

        CAM_DEV=`media-ctl -d $media_id -p -e "$CSI2RX_CONTEXT_NAME" | grep video | awk '{print $4}'`
        CAM_DEV_NAME=/dev/video-imx219-cam$count

        CAM_SUBDEV_NAME=/dev/v4l-imx219-subdev$count

        ln -snf $CAM_DEV $CAM_DEV_NAME
        ln -snf $CAM_SUBDEV $CAM_SUBDEV_NAME

        echo -e "${GREEN}IMX219 Camera $media_id detected${NOCOLOR}"
        echo "    device = $CAM_DEV_NAME"
        echo "    name = imx219"
        echo "    format = $IMX219_CAM_FMT"
        echo "    subdev_id = $CAM_SUBDEV_NAME"
        echo "    isp_required = yes"
        count=$(($count + 1))
    done
    done
}

setup_ov5640(){
    count=0
    for media_id in {0..3}; do
    for name in `media-ctl -d $media_id -p | grep entity | grep ov5640 | cut -d ' ' -f 5`; do
        CAM_SUBDEV=`media-ctl -d $media_id -p -e "ov5640 $name" | grep v4l-subdev | awk '{print $4}'`
        media-ctl -d $media_id --set-v4l2 ''"\"ov5640 $name\""':0 '$OV5640_CAM_FMT''

        CSI_BRIDGE_NAME=`media-ctl -d $media_id -p -e "ov5640 $name" | grep csi-bridge | cut -d "\"" -f 2`
        CSI2RX_NAME=`media-ctl -d $media_id -p -e "$CSI_BRIDGE_NAME" | grep "ticsi2rx\"" | cut -d "\"" -f 2`
        CSI2RX_CONTEXT_NAME="$CSI2RX_NAME context 0"

        CAM_DEV=`media-ctl -d $media_id -p -e "$CSI2RX_CONTEXT_NAME" | grep video | awk '{print $4}'`
        CAM_DEV_NAME=/dev/video-ov5640-cam$count

        CAM_SUBDEV_NAME=/dev/v4l-ov5640-subdev$count

        ln -snf $CAM_DEV $CAM_DEV_NAME
        ln -snf $CAM_SUBDEV $CAM_SUBDEV_NAME

        echo -e "${GREEN}CSI Camera $media_id detected${NOCOLOR}"
        echo "    device = $CAM_DEV_NAME"
        echo "    name = ov5640"
        echo "    format = $OV5640_CAM_FMT"
        echo "    subdev_id = $CAM_SUBDEV_NAME"
        echo "    isp_required = no"
        count=$(($count + 1))
    done
    done
}

setup_USB_camera(){
    ls /dev/v4l/by-path/*usb*video-index0 > /dev/null 2>&1
    if [ "$?" == "0" ]; then
        USB_CAM_ARR=(`ls /dev/v4l/by-path/*usb*video-index0`)
        count=0
        for i in ${USB_CAM_ARR[@]}
        do
            USB_CAM_DEV=`readlink -f $i`
            USB_CAM_NAME=/dev/video-usb-cam$count
            ln -snf $USB_CAM_DEV $USB_CAM_NAME
            echo -e "${GREEN}USB Camera $count detected${NOCOLOR}"
            echo "    device = $USB_CAM_NAME"
            echo "    format = jpeg"
            count=$(($count + 1))
        done
    fi
}

setup_USB_camera
setup_imx219
setup_ov5640
setup_ov2312
setup_imx390
setup_routes
