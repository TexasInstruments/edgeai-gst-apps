#!/bin/bash

find /run/ -maxdepth 1 | grep -E "csv" | xargs sed -i 's/title/Model Name/g'
find /run/ -maxdepth 1 | grep -E "csv" | xargs sed -i 's/mpu/A53 Load (%)/g'
find /run/ -maxdepth 1 | grep -E "csv" | xargs sed -i 's/c7x_1/C7x Load (%)/g'
find /run/ -maxdepth 1 | grep -E "csv" | xargs sed -i 's/ddr_read_avg/DDR Read BW (MB\/s)/g'
find /run/ -maxdepth 1 | grep -E "csv" | xargs sed -i 's/ddr_write_avg/DDR Write BW (MB\/s)/g'
find /run/ -maxdepth 1 | grep -E "csv" | xargs sed -i 's/ddr_total_avg/DDR Total BW (MB\/s)/g'
find /run/ -maxdepth 1 | grep -E "csv" | xargs sed -i 's/ddr_read_peak/DDR Read Peak BW (MB\/s)/g'
find /run/ -maxdepth 1 | grep -E "csv" | xargs sed -i 's/ddr_total_peak/DDR Total Peak BW (MB\/s)/g'
find /run/ -maxdepth 1 | grep -E "csv" | xargs sed -i 's/ddr_write_peak/DDR Write Peak BW (MB\/s)/g'
find /run/ -maxdepth 1 | grep -E "csv" | xargs sed -i 's/fps/FPS/g'
find /run/ -maxdepth 1 | grep -E "csv" | xargs sed -i 's/MSC0/MSC_0 (%)/g'
find /run/ -maxdepth 1 | grep -E "csv" | xargs sed -i 's/MSC1/MSC_1 (%)/g'
find /run/ -maxdepth 1 | grep -E "csv" | xargs sed -i 's/VISS/VISS (%)/g'

awk '(NR == 1) || (FNR > 1)' /run/video*.csv > ${SOC}_optiflow_video.csv
awk '(NR == 1) || (FNR > 1)' /run/camera*.csv > ${SOC}_optiflow_camera.csv

awk '{sub(/[^,]*/,"");sub(/,/,"")} 1'  ${SOC}_optiflow_video.csv > optiflow_video_${SOC}.csv
awk '{sub(/[^,]*/,"");sub(/,/,"")} 1'  ${SOC}_optiflow_camera.csv > optiflow_camera_${SOC}.csv

rm -rf ${SOC}_optiflow_video.csv ${SOC}_optiflow_camera.csv

sync
