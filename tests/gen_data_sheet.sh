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

topdir=$EDGEAI_GST_APPS_PATH
usb_camera=`ls /dev/v4l/by-path/*usb*video-index0 | head -1 | xargs readlink -f`
usb_fmt=jpeg
usb_width=1280
usb_height=720
ov5640_camera=`ls /dev/v4l/by-path/*csi*video-index0 | head -1 | xargs readlink -f`
ov5640_fmt=auto
ov5640_width=1280
ov5640_height=720
imx219_camera=`ls /dev/v4l/by-path/*csi*video-index0 | head -1 | xargs readlink -f`
imx219_fmt=rggb
imx219_width=1920
imx219_height=1080
imx219_subdev_id=2
imx219_sen_id=imx219
imx219_ldc=False
imx390_camera=`ls /dev/v4l/by-path/*csi*video-index0 | head -1 | xargs readlink -f`
imx390_fmt=rggb12
imx390_width=1936
imx390_height=1100
imx390_subdev_id=2
imx390_sen_id=imx390
imx390_ldc=True
video_file=$EDGEAI_DATA_PATH/videos/video_0000_h264.mp4
video_fmt=h264
video_width=1280
video_height=720

BRIGHTWHITE='\033[0;37;1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
NOCOLOR='\033[0m'

####################################################################################################

export TEST_ENGINE_DEBUG=1
config_file="$topdir/tests/test_config.yaml"
parse_script="$topdir/tests/parse_data_sheet.py"
timeout=30
filter=" grep -f /tmp/test_models.txt"

# This will make sure that the test is run only on the listed models

cat > /tmp/test_models.txt << EOF
TFL-CL-0000-mobileNetV1-mlperf
ONR-CL-6158-mobileNetV2-1p4-qat
TFL-OD-2020-ssdLite-mobDet-DSP-coco-320x320
EOF

sed -i '/^$/d' /tmp/test_models.txt

####################################################################################################
cleanup() {
	echo
	echo "[Ctrl-C] Killing the script..."
	ps -eaf | grep "[g]en_data_sheet.sh" | awk -F" " '{print $2}' | xargs kill -9
}

# TODO: The trap is not reliable currently, need to be fixed
trap cleanup SIGINT

rm -rf ../perf_logs/

for suite in "CPP-PERF"; do
	for input in "USBCAM" "VIDEO" "IMX219"; do
	#for input in "OV5640"; do
	#for input in "IMX390"; do
	for output in "DISPLAY"; do
		test_suite="$suite-$input-$output"

		# Update the config file with correct parameters
		# TODO: Simplify the complex find and replace with yq
		case $input in
		"VIDEO")
			sed -i "s@source:.*@source: $video_file@" $config_file
			sed -i "s@format:.*@format: $video_fmt@" $config_file
			sed -i "1,/width:.*/s//width: $video_width/" $config_file
			sed -i "1,/height:.*/s//height: $video_height/" $config_file
			;;
		"USBCAM")
			sed -i "s@source:.*@source: $usb_camera@" $config_file
			sed -i "s@format:.*@format: $usb_fmt@" $config_file
			sed -i "1,/width:.*/s//width: $usb_width/" $config_file
			sed -i "1,/height:.*/s//height: $usb_height/" $config_file
			;;
		"OV5640")
			sed -i "s@source:.*@source: $ov5640_camera@" $config_file
			sed -i "s@format:.*@format: $ov5640_fmt@" $config_file
			sed -i "1,/width:.*/s//width: $ov5640_width/" $config_file
			sed -i "1,/height:.*/s//height: $ov5640_height/" $config_file
			;;
		"IMX219")
			sed -i "s@source:.*@source: $imx219_camera@" $config_file
			sed -i "s@format:.*@format: $imx219_fmt@" $config_file
			sed -i "1,/width:.*/s//width: $imx219_width/" $config_file
			sed -i "1,/height:.*/s//height: $imx219_height/" $config_file
			sed -i "s@subdev-id:.*@subdev-id: $imx219_subdev_id@" $config_file
			sed -i "s@sen-id:.*@sen-id: $imx219_sen_id@" $config_file
			sed -i "s@ldc:.*@ldc: $imx219_ldc@" $config_file
			;;
		"IMX390")
			sed -i "s@source:.*@source: $imx390_camera@" $config_file
			sed -i "s@format:.*@format: $imx390_fmt@" $config_file
			sed -i "1,/width:.*/s//width: $imx390_width/" $config_file
			sed -i "1,/height:.*/s//height: $imx390_height/" $config_file
			sed -i "s@subdev-id:.*@subdev-id: $imx390_subdev_id@" $config_file
			sed -i "s@sen-id:.*@sen-id: $imx390_sen_id@" $config_file
			sed -i "s@ldc:.*@ldc: $imx390_ldc@" $config_file
			;;
		*)
			continue
			;;
		esac

		case $output in
		"VIDEO")
			sed -i "s@sink:.*@sink: $EDGEAI_DATA_PATH/output/output_0000.avi@" $config_file
			;;
		"DISPLAY")
			sed -i "s@sink:.*@sink: kmssink@" $config_file
			;;
		*)
			continue
			;;
		esac

        cat > data_sheet_$test_suite.rst << EOF
.. csv-table:: Performance table
    :header: "Model", "FPS", "Total time (ms)", "Inference time (ms)", "A72 Load (%)", "DDR Read BW (MB/s)", "DDR Write BW (MB/s)", "DDR Total BW (MB/s)", "C71 Load (%)", "C66_1 Load (%)", "C66_2 Load (%) ", "MCU2_0 Load (%)", "MCU2_1 Load (%)", "MSC_0 (%)", "MSC_1 (%)", "VISS (%)", "NF (%)", "LDC (%)", "SDE (%)", "DOF (%)"
    :widths: 50, 20, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10

EOF
		# Now start the test engine with above filter
		./test_engine.sh $test_suite $config_file $timeout $parse_script "$filter"
	done
	done
done

#kill using following command
#ps -eaf | grep "[s]anity_test.sh" | awk -F" " '{print $2}' | xargs kill -9