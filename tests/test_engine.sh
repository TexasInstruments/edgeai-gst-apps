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

<< DESCRIPTION
This script acts as a test engine to run the edge AI demos with different
parameters. This can be used to develop different types of sanity, regression,
performance, long run tests.

Following are some of it's features:
* Allow to run tests for all available models
* Specify a filter for the models to be tested
* Select between Python and C++ demos
* Save the stdout and stderr for all the test cases
* Provide custom parsing script for validation criteria
DESCRIPTION

# Global variables
topdir=$EDGEAI_GST_APPS_PATH
BRIGHTWHITE='\033[0;37;1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
NOCOLOR='\033[0m'

cpuload=0

debug() {
	if [ ! -z $TEST_ENGINE_DEBUG ]; then
		printf "[DEBUG] $1\n"
	fi
}

usage() {
	cat <<- EOF
		test_engine.sh - Run different tests on the edgeai apps
		Usage:
		  test_engine.sh TSUIT TARGS TIMEOUT PARSE_SCRIPT FILTER
		    TSUIT        : Unique string for each varient of test
		                   Must start with one of PY, CPP No underscores
		    TARGS        : Arguments to be passed to the test scripts
		                   Escape the quotes to pass as single argument
		    TIMEOUT      : No of seconds to run the test before killing it
		                   Useful for forever running camera tests
		    PARSE_SCRIPT : Script to handle the test logs and decide the
		                   validation criteria for the test run
		    FILTER       : Optionally filter out models like below:
		                   "grep CL" to run only classification models
		                   "grep TVM" to run only those models with TVM runtime
		                   "grep TFL-CL-007" to run only specific model
	EOF
}

# Measure cpuload using a background subshell function
# Use a temp file to return the measured data
start_cpuload_measurement() {
	duration=$1

	load=0
	# Handle the Host / Guest OS compatibility
	if [ `mpstat | grep gnice | wc -l` == "1" ]; then
		# Ubuntu mpstat, has additional gnice column, 12th item is idle
		load=`mpstat 1 $duration | stdbuf -o0 grep "all" | awk -F" " '{ sum += $12 } END { printf "%0.2f\n", 100 - sum / NR }'`
	else
		# busybox mpstat, 11th item is idle
		load=`mpstat 1 $duration | stdbuf -o0 grep "all" | awk -F" " '{ sum += $11 } END { printf "%0.2f\n", 100 - sum / NR }'`
	fi
	echo $load > /tmp/__cpuload.txt
}

stop_cpuload_measurement() {
	ps -eaf | grep "[m]pstat" | awk -F" " '{print $2}' | xargs kill -9 2>/dev/null
	sleep 1

	cpuload=`cat /tmp/__cpuload.txt`
	rm -f /tmp/__cpuload.txt
}

build_cpp_apps() {
	dump_inf_data=$1
	if [ "$dump_inf_data" == "true" ]; then
		build_flag="-DEDGEAI_ENABLE_OUTPUT_FOR_TEST=ON"
	fi
	cd $topdir/apps_cpp
	mkdir -p build
	cd build
	cmake $build_flag ..
	make

	if [ "$?" -ne "0" ]; then
		echo "ERROR: Failed to build CPP apps" 1>&2
		exit 1
	fi
}

# Run a single command with a timeout, save the stdout/stderr
# Returns the status of the command
run_single_test() {
	test_name=$1
	test_dir=$2
	timeout=$3
	parse_script=$4
	measure_cpuload=$5
	test_command=$6

	# Setup log files for stout and stderr for each test run
	stdout="$topdir/logs/"$test_name"_stdout.log"
	stderr="$topdir/logs/"$test_name"_stderr.log"
	echo -e "$command\n\n" > $stdout

	echo
	printf "[TEST] START $test_name\n"

	cd $test_dir
	echo -e "$test_command\n\n" > $stdout
	debug "Running $BRIGHTWHITE$test_command$NOCOLOR"

	if [ "$measure_cpuload" == "true" ]; then
		start_cpuload_measurement $((timeout - 1)) &
	fi

    # Run the app with the timeout and force kill the test 4 after seconds
	timeout -s INT -k $(($timeout + 4)) $timeout $test_command >> $stdout 2> $stderr
	test_status=$?

	if [ "$measure_cpuload" == "true" ]; then
		stop_cpuload_measurement
	fi

	if [ "$test_status" -ne "0" ] && [ "$test_status" -ne "124" ]; then
		# Test failed while running
		printf "[TEST]$RED FAIL_RUN$NOCOLOR $test_name (retval $test_status)\n"
		printf "        Test Log saved @ $RED$stdout$NOCOLOR\n"
		return $test_status
	fi

	if [ "$parse_script" != "null" ]; then
		cd $topdir/tests/
		parse_command="$parse_script $stdout"
		debug "Running $BRIGHTWHITE$parse_command$NOCOLOR"

		$parse_command
		parse_status=$?

		if [ "$parse_status" -ne "0" ]; then
			printf "[TEST]$RED FAIL_PARSE$NOCOLOR $test_name (retval $parse_status)\n"
			printf "        Test Log saved @ $RED$stdout$NOCOLOR\n"
			printf "        Parse command $parse_command\n"
			return $parse_status
		fi
	fi

	printf "[TEST]$GREEN PASS$NOCOLOR $test_name\n"
	return 0
}

################################################################################
# Main script starts from here

if [ "$#" -lt "3" ] || [ "$#" -gt "8" ]; then
	echo "ERROR: Invalid arguments"
	usage
	exit 1
fi

test_suite=$1
config_file=$2
timeout=$3
parse_script=${4:-"null"}
test_filter=${5:-"null"}
measure_cpuload=${6:-"true"}
modelname=${7:-"null"}
dump_inf_data=${8:-"false"}

if [[ "$test_suite" = "CPP"* ]]; then
	echo "[TEST] Building CPP applications..."
	build_cpp_apps $8 >/dev/null
fi

# Create a directory to store logs
mkdir -p $topdir/logs
cd $topdir/

if [ "$modelname" == "null" ]; then
	# Find out a list of models for which to run the test
	searchcmd="find ../model_zoo -maxdepth 1 -mindepth 1 -type d"
	if [ "$test_filter" != "null" ]; then
		searchcmd="$searchcmd | $test_filter"
	fi
	searchcmd="$searchcmd | sort"
else
	searchcmd="find ../model_zoo/$modelname -maxdepth 0 -mindepth 0 -type d"
	if [ -f "$searchcmd" ]; then
		echo "ERROR: $searchcmd does not exist."
		exit 1
	fi
fi

# Iterate over the list of filtered models
for model_path in $(eval $searchcmd); do
	model=`echo $model_path | cut -d'/' -f3`
	model_type=`echo $model | cut -d'-' -f2`
	case $model_type in
		"CL")
			model_type="classification"
			app_tag="classify"
			;;
		"OD")
			model_type="detection"
			app_tag="objdet"
			;;
		"SS")
			model_type="segmentation"
			app_tag="semseg"
			;;
		"KD")                                                 
            model_type="Key-point detection"                   
            app_tag="keyptdet"                                
            ;;                                             
		*)
			continue
			;;
	esac

	python_app="./app_edgeai.py"
	cpp_app="./bin/Release/app_edgeai"
    optiflow_app="./optiflow.py"
	if [[ "$test_suite" = "PY"* ]]; then
			test_dir="$topdir/apps_python"
			test_app=$python_app
	elif [[ "$test_suite" = "CPP"* ]]; then
			test_dir="$topdir/apps_cpp/"
			test_app=$cpp_app
    elif [[ "$test_suite" = "OPTIFLOW"* ]]; then
            test_dir="$topdir/optiflow"
            test_app=$optiflow_app
	else
		echo "ERROR: test_suite should start with either of PY, CPP"
		echo "ERROR: Invalid test_suite name"
		exit 1
	fi


	# Update the config file with correct model path if modelname isnt specified
	if [ "$modelname" == "null" ]; then
		sed -i "s@model_path:.*@model_path: $topdir/$model_path@" $config_file
	fi

	# Generate a unique test name for each test_suite / model
	# This way, logs will not be overwritten
	tname="$test_suite"_"$model"
    if [[ "$test_suite" = "OPTIFLOW"* ]]; then
        command="$test_app $config_file"
	else
	    command="$test_app -n -v $config_file"
    fi

	# This will run the test and save the logs
	run_single_test $tname $test_dir $timeout $parse_script $measure_cpuload "$command"

done
