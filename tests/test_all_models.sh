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

BRIGHTWHITE='\033[0;37;1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
NOCOLOR='\033[0m'

####################################################################################################
export TEST_ENGINE_DEBUG=1
timeout=30
config_file="$topdir/tests/test_config.yaml"
parse_script="$topdir/tests/parse_log_data.py"
filter=""
measure_cpuload="false"

####################################################################################################
cleanup() {
	echo
	echo "[Ctrl-C] Killing the script..."
	ps -eaf | grep "[t]est_all_models.sh" | awk -F" " '{print $2}' | xargs kill -9
}

####################################################################################################
usage() {
	echo "./test_all_models.sh --all  | --python | --cpp | --optiflow"
	echo "./test_all_models.sh --help | -h - To display this"
}

####################################################################################################
test_suite_array=()

if [ -z "$*" ]; then
	test_suite_array+=("OPTIFLOW-TEST" "PYTHON-TEST" "CPP-TEST");
else
	while [[ $# -gt 0 ]]
	do
	case $1 in
		"--python")
			test_suite_array+=("PYTHON-TEST")
			shift
			;;
		"--cpp")
			test_suite_array+=("CPP-TEST")
			shift
			;;
		"--optiflow")
			test_suite_array+=("OPTIFLOW-TEST")
			shift
			;;
		"--all")
			test_suite_array+=("OPTIFLOW-TEST" "PYTHON-TEST" "CPP-TEST")
			shift
			;;
		"--help" | "-h")
			usage
			exit 0
			;;
		*)
			echo "Inavlid argument $1"
			usage
			exit 1
			;;
	esac
	done
fi
####################################################################################################

# TODO: The trap is not reliable currently, need to be fixed
trap cleanup SIGINT

for test_suite in "${test_suite_array[@]}"; do
	./test_engine.sh $test_suite $config_file $timeout $parse_script "$filter" $measure_cpuload
done