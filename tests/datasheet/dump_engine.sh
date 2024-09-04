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
topdir=$MODEL_ZOO_PATH
BRIGHTWHITE='\033[0;37;1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
NOCOLOR='\033[0m'

usage() {
	cat <<- EOF
		dump_engine.sh - Run different tests on the edgeai apps
		Usage:
		  dump_engine.sh TSUIT TARGS TIMEOUT PARSE_SCRIPT 
		    TSUIT        : Unique string for each varient of test
		                   Must start with one of PY, CPP No underscores
		    TARGS        : Arguments to be passed to the test scripts
		                   Escape the quotes to pass as single argument
		    TIMEOUT      : No of seconds to run the test before killing it
		                   Useful for forever running camera tests
		    PARSE_SCRIPT : Script to parse and generate the datasheet
	EOF
}

# Run a single command with a timeout, save the stdout/stderr
# Returns the status of the command
run_single_model() {
	test_name=$1
	test_dir=$2
	timeout=$3
	test_command=$4

    # Setup log files for stout and stderr for each test run
    stdout="$EDGEAI_GST_APPS_PATH/logs/"$test_name"_stdout.log"
    stderr="$EDGEAI_GST_APPS_PATH/logs/"$test_name"_stderr.log"
    echo -e "$command\n\n" > $stdout

    echo
	printf "[DUMP] Start $test_name\n"

	cd $test_dir
	echo -e "$test_command\n\n" > $stdout

    # Run the app with the timeout and force kill the test 5 after seconds
	timeout --preserve-status --foreground -s INT -k $(($timeout + 5)) $timeout $test_command >> $stdout 2> $stderr
	dump_status=$?

	if [ "$dump_status" -ne "0" ] && [ "$dump_status" -ne "124" ]; then
		# Dump failed while running
		printf "[DUMP]$RED FAIL_RUN$NOCOLOR $test_name (retval $dump_status)\n"
		printf "        Dump Log saved @ $RED$stdout$NOCOLOR\n"
		return $dump_status
	fi

	printf "[DUMP]$GREEN PASS$NOCOLOR $test_name\n"
	return 0
}

################################################################################
# Main script starts from here

if [ "$#" -lt "3" ] || [ "$#" -gt "5" ]; then
	echo "ERROR: Invalid arguments"
	usage
	exit 1
fi

test_suite=$1
config_file=$2
timeout=$3
modelname=$4
parse_script=$5

mkdir -p  $EDGEAI_GST_APPS_PATH/logs
cd $EDGEAI_GST_APPS_PATH/

searchcmd="find /opt/model_zoo/$modelname -maxdepth 0 -mindepth 0 -type d"
if [ -f "$searchcmd" ]; then
    echo "ERROR: $searchcmd does not exist."
    exit 1
fi

# Iterate over the list of filtered models
for model_path in $(eval $searchcmd); do
    model=`echo $model_path | cut -d'/' -f4`
    model_type=`echo $model | cut -d'-' -f2`
    sed -i "s/title:.*/title: "$modelname"/" $config_file
    case $model_type in
        "CL")
            model_type="classification"
            sed -i "s/start-dumps:.*/start-dumps: 5/" $config_file
            ;;
        "OD")
            model_type="detection"
            sed -i "s/start-dumps:.*/start-dumps: 150/" $config_file
            ;;
        *)
            continue
            ;;
    esac

    optiflow_app="./optiflow.py"
    test_dir="$EDGEAI_GST_APPS_PATH/optiflow"
    test_app=$optiflow_app

	sed -i "s@model_path:.*@model_path: $model_path@" $config_file
    command="$test_app $config_file"
    tname="OPTIFLOW_$modelname"

	# This will run the test and save the logs
	run_single_model $tname $test_dir $timeout "$command"
done
