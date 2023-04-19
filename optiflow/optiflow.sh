#!/bin/bash

if [ "$1" == "" ]
then
    echo "ERROR: No config file specified"
    exit
fi

export GST_DEBUG_FILE=/run/trace.log
export GST_DEBUG_NO_COLOR=1
export GST_DEBUG="GST_TRACER:7"
export GST_TRACERS="latency(flags=element)"

rm $GST_DEBUG_FILE

`$EDGEAI_GST_APPS_PATH/optiflow/optiflow.py -t $1` > /dev/null 2>&1 &

ls $GST_DEBUG_FILE > /dev/null 2>&1
while [ "$?" != "0" ]
do
    ls $GST_DEBUG_FILE > /dev/null 2>&1
done

sleep 2

$EDGEAI_GST_APPS_PATH/scripts/gst_tracers/parse_gst_tracers.py $GST_DEBUG_FILE 2>/dev/null | stdbuf --output=0 grep tidlinferer 2>/dev/null

pkill gst-launch-1.0
