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

BRIGHTWHITE='\033[0;37;1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
NOCOLOR='\033[0m'

####################################################################################################

export TEST_ENGINE_DEBUG=1
config_file="$topdir/tests/test_config.yaml"
parse_script="$topdir/tests/parse_perf_data.py"
timeout=120
filter=""

####################################################################################################
cleanup() {
	echo
	echo "[Ctrl-C] Killing the script..."
	ps -eaf | grep "[g]en_performance_data.sh" | awk -F" " '{print $2}' | xargs kill -9
}

# TODO: The trap is not reliable currently, need to be fixed
trap cleanup SIGINT

# Setup the source and sink in the test config YAML file
sed -i "s@source:.*@source: $usb_camera@" $config_file
sed -i "s@format:.*@format: $usb_fmt@" $config_file
sed -i "1,/width:.*/s//width: $usb_width/" $config_file
sed -i "1,/height:.*/s//height: $usb_height/" $config_file
sed -i "s@sink:.*@sink: kmssink@" $config_file

for test_suite in "PY-PERF-USBCAM" "CPP-PERF-USBCAM"; do
	cd $(dirname $0)
	cat > "performance_$test_suite.rst" <<- EOF
		+----------------+-------+-----------+--------------+-----------------+------------------+----------------+-------------------+
		| Inference type | Model | Framerate | CPU Load (%) | Total time (ms) | Pre-Process (ms) | Inference (ms) | Post-Process (ms) |
		+================+=======+===========+==============+=================+==================+================+===================+
	EOF

	./test_engine.sh $test_suite $config_file $timeout $parse_script "$filter"
done

# Merge the table to show the performance of each model one after other
# into a single table
cat > performance.rst <<- EOF
	+----------------+-------+-------------+-----------+--------------+----------------+------------------+
	| Inference type | Model | Application | Framerate | CPU Load (%) |Total time (ms) | Inference (ms)   |
	+================+=======+=============+===========+==============+================+==================+
EOF

for model_path in $(find $MODEL_ZOO_PATH -maxdepth 1 -mindepth 1 -type d | sort); do
	model=`echo $model_path | cut -d'/' -f6`

	for test_suite in "PY-PERF-USBCAM" "CPP-PERF-USBCAM"; do

		if [[ "$test_suite" = "PY"* ]]; then
			app="Python"
		elif [[ "$test_suite" = "CPP"* ]]; then
			app="C++"
		else
			echo "Invalid test_suite $test_suite"
			exit 1
		fi

		entry=`grep $model performance_$test_suite.rst`
		if [ "$entry" == "" ]; then
			printf "$RED WARN: No performance data from $app app for $model $NOCOLOR\n"
			continue
		fi

		lhs=`echo $entry | cut -d '|' -f1-3`
		rhs=`echo $entry | cut -d '|' -f4-`
		echo "$lhs| $app |$rhs" >> performance.rst
		echo "+----------------+-------+-------------+-----------+-----------------+------------------+----------------+-------------------+" >> performance.rst
		echo "+----------------+-------+-------------+-----------+--------------+----------------+------------------+----------------+-------------------+" >> performance.rst
	done
done

#kill using following command
#ps -eaf | grep "[g]en_performance_data.sh" | awk -F" " '{print $2}' | xargs kill -9