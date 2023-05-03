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

# Example: ./test_script.sh --test_suite="PY_USB_DISPLAY" --yaml=*yaml*s
#   test_suite = Name given to test. PY or CPP decides what test is run
#   yaml = absolute path to test yaml file
#   parse_log = true/false [Default: true]
#   golden_ref_check = true/false [Default: true]
# [Note: If golden_ref_check=true, make sure that the config file has debug 
#  enabled. Refer to configs/app_config_template.yaml to know how to enable.]

usage() {
        echo "Usage:"
        echo "./test_script.sh --test_suite=*test-suite* --yaml=*path-to-yaml-file* --parse_log=<true/false> --golden_ref_check=<true/false>"
}

topdir=$EDGEAI_GST_APPS_PATH
timeout=30
test_suite=""
yaml=""
rebuild_apps_cpp=""
parse_log=""
golden_ref_check=""
#Parse command line args
while [ $# -gt 0 ]; do
        case "$1" in
        --test_suite=*)
        test_suite="${1#*=}"
        ;;
        --yaml=*)
        yaml="${1#*=}"
        ;;
        --parse_log=*)
        parse_log="${1#*=}"
        ;;
        --golden_ref_check=*)
        golden_ref_check="${1#*=}"
        ;;
        --help)
        echo "command line arguments to the scripts:"
        usage
        exit
        ;;
        *)
        echo "Error: Invalid argument $1 !!"
        usage
        exit
        ;;
        esac
        shift
done

if [[ "$test_suite" = "PY"* ]]; then
    test_dir="$topdir/apps_python"
    app="python"
elif [[ "$test_suite" = "CPP"* ]]; then
    test_dir="$topdir/apps_cpp/"
    app="cpp"
elif [[ "$test_suite" = "OPTIFLOW"* ]]; then
    test_dir="$topdir/optiflow/"
    app="optiflow"
else
    echo "[PROMPT]: FAIL - Test suite should start with PY or CPP or OPTIFLOW."
    exit 1
fi
if [ ! -f "$yaml" ]; then  
    echo "[PROMPT]: FAIL - $yaml does not exist."
    exit 1
fi
if [ "$parse_log" != "" -a "$parse_log" != "true" -a "$parse_log" != "false" ]; then
        echo "[PROMPT]: FAIL - Invalid parse_log $parse_log."
        usage
        exit 1
fi
if [ "$golden_ref_check" != "" -a "$golden_ref_check" != "true" -a "$golden_ref_check" != "false" ]; then
        echo "ERROR: Invalid golden_ref_check $golden_ref_check"
        usage
        exit 1
fi

if [ "$parse_log" == "" ]; then
    parse_log="true"
fi
if [ "$golden_ref_check" == "" ]; then
    golden_ref_check="true"
fi

measure_cpuload="false"
dump_inf_data="true"

#Get model_name
model_name=`sed -n "/model_path/p" $yaml | rev | cut -d'/' -f1 | rev | xargs`

#Get debug_dir_name
debug_dir_prefix=`sed -n "/dir_suffix/p" $yaml | cut -d':' -f2 | xargs`

test_name="$test_suite"_"$model_name"
stdout="$topdir/logs/"$test_name"_stdout.log"
stderr="$topdir/logs/"$test_name"_stderr.log"

#Start the test
./test_engine.sh $test_suite $yaml $timeout "null" "null" $measure_cpuload $model_name $dump_inf_data
test_status=$?
if [ "$test_status" -ne "0" ] && [ "$test_status" -ne "124" ]; then
    echo "[EXIT-STATUS] FAIL $test_status"
    exit $test_status
fi
echo "[EXIT-STATUS] PASS $test_status"

#Parse Log File
if [ "$parse_log" != "false" ]; then
    python3 $topdir/tests/parse_log_data.py $stdout
    test_status=$?
    if [ "$test_status" -ne "0" ] && [ "$test_status" -ne "124" ]; then
        exit $test_status
    fi
fi

#Check Golden Ref
if [ "$golden_ref_check" != "false" ]; then
    dump_dir="$test_dir/debug_out/$model_name/$app/$debug_dir_prefix"
    python3 $topdir/tests/parse_golden_ref.py $dump_dir
    test_status=$?
    if [ "$test_status" -ne "0" ] && [ "$test_status" -ne "124" ]; then
        exit $test_status
    fi
fi