#!/bin/bash

awk -F, 'NR==1{for(i=1;i<=NF;i++)Arr[i]=$i;next}{printf("%s,",$1);for(j=2;j<=NF;j++){printf("%s: %s\n",Arr[j],$j)}printf("\n")}' /run/video_ONR-OD-8200-yolox-nano-lite-mmdet-coco-416x416.csv | tail -30 | grep -E "mpu|c7x|avg|fps|VISS|MSC*" > /run/video_ONR-OD-8200-yolox-nano-lite-mmdet-coco-416x416.txt

awk -F, 'NR==1{for(i=1;i<=NF;i++)Arr[i]=$i;next}{printf("%s,",$1);for(j=2;j<=NF;j++){printf("%s: %s\n",Arr[j],$j)}printf("\n")}' /run/video_TFL-CL-0000-mobileNetV1-mlperf.csv | tail -30 | grep -E "mpu|c7x|avg|fps|VISS|MSC*" > /run/video_TFL-CL-0000-mobileNetV1-mlperf.txt

awk -F, 'NR==1{for(i=1;i<=NF;i++)Arr[i]=$i;next}{printf("%s,",$1);for(j=2;j<=NF;j++){printf("%s: %s\n",Arr[j],$j)}printf("\n")}' /run/video_ONR-CL-6360-regNetx-200mf.csv | tail -30 | grep -E "mpu|c7x|avg|fps|VISS|MSC*" > /run/video_ONR-CL-6360-regNetx-200mf.txt

awk -F, 'NR==1{for(i=1;i<=NF;i++)Arr[i]=$i;next}{printf("%s,",$1);for(j=2;j<=NF;j++){printf("%s: %s\n",Arr[j],$j)}printf("\n")}' /run/video_TFL-OD-2020-ssdLite-mobDet-DSP-coco-320x320.csv | tail -30 | grep -E "mpu|c7x|avg|fps|VISS|MSC*" > /run/video_TFL-OD-2020-ssdLite-mobDet-DSP-coco-320x320.txt

awk -F, 'NR==1{for(i=1;i<=NF;i++)Arr[i]=$i;next}{printf("%s,",$1);for(j=2;j<=NF;j++){printf("%s: %s\n",Arr[j],$j)}printf("\n")}' /run/camera_ONR-OD-8200-yolox-nano-lite-mmdet-coco-416x416.csv | tail -30 | grep -E "mpu|c7x|avg|fps|VISS|MSC*" > /run/camera_ONR-OD-8200-yolox-nano-lite-mmdet-coco-416x416.txt

awk -F, 'NR==1{for(i=1;i<=NF;i++)Arr[i]=$i;next}{printf("%s,",$1);for(j=2;j<=NF;j++){printf("%s: %s\n",Arr[j],$j)}printf("\n")}' /run/camera_TFL-CL-0000-mobileNetV1-mlperf.csv | tail -30 | grep -E "mpu|c7x|avg|fps|VISS|MSC*" > /run/camera_TFL-CL-0000-mobileNetV1-mlperf.txt

awk -F, 'NR==1{for(i=1;i<=NF;i++)Arr[i]=$i;next}{printf("%s,",$1);for(j=2;j<=NF;j++){printf("%s: %s\n",Arr[j],$j)}printf("\n")}' /run/camera_ONR-CL-6360-regNetx-200mf.csv | tail -30 | grep -E "mpu|c7x|avg|fps|VISS|MSC*" > /run/camera_ONR-CL-6360-regNetx-200mf.txt

awk -F, 'NR==1{for(i=1;i<=NF;i++)Arr[i]=$i;next}{printf("%s,",$1);for(j=2;j<=NF;j++){printf("%s: %s\n",Arr[j],$j)}printf("\n")}' /run/camera_TFL-OD-2020-ssdLite-mobDet-DSP-coco-320x320.csv | tail -30 | grep -E "mpu|c7x|avg|fps|VISS|MSC*" > /run/camera_TFL-OD-2020-ssdLite-mobDet-DSP-coco-320x320.txt

find /run/ -maxdepth 1 | grep -E "txt" | xargs sed -i 's/mpu/A53 Load (%)/g'
find /run/ -maxdepth 1 | grep -E "txt" | xargs sed -i 's/c7x_1/C7x Load (%)/g'
find /run/ -maxdepth 1 | grep -E "txt" | xargs sed -i 's/ddr_read_avg/DDR Read BW (MB/s)/g'
find /run/ -maxdepth 1 | grep -E "txt" | xargs sed -i 's/ddr_write_avg/DDR Write BW (MB/s)/g'
find /run/ -maxdepth 1 | grep -E "txt" | xargs sed -i 's/ddr_total_avg/DDR Total BW (MB/s)/g'
find /run/ -maxdepth 1 | grep -E "txt" | xargs sed -i 's/fps/FPS/g'
find /run/ -maxdepth 1 | grep -E "txt" | xargs sed -i 's/MSC0/MSC_0 (%)/g'
find /run/ -maxdepth 1 | grep -E "txt" | xargs sed -i 's/MSC1/MSC_1 (%)/g'
find /run/ -maxdepth 1 | grep -E "txt" | xargs sed -i 's/VISS/VISS (%)/g'

echo -e "Perf Stats of video_ONR-OD-8200-yolox-nano-lite-mmdet-coco-416x416\n" > ${SOC}_optiflow_stats.txt
cat /run/video_ONR-OD-8200-yolox-nano-lite-mmdet-coco-416x416.txt >> ${SOC}_optiflow_stats.txt

echo -e "\nPerf Stats of video_TFL-CL-0000-mobileNetV1-mlperf\n" >> ${SOC}_optiflow_stats.txt
cat /run/video_TFL-CL-0000-mobileNetV1-mlperf.txt >> ${SOC}_optiflow_stats.txt

echo -e "\nPerf Stats of video_ONR-CL-6360-regNetx-200mf\n" >> ${SOC}_optiflow_stats.txt
cat /run/video_ONR-CL-6360-regNetx-200mf.txt >> ${SOC}_optiflow_stats.txt

echo -e "\nPerf Stats of video_TFL-OD-2020-ssdLite-mobDet-DSP-coco-320x320\n" >> ${SOC}_optiflow_stats.txt
cat /run/video_TFL-OD-2020-ssdLite-mobDet-DSP-coco-320x320.txt >> ${SOC}_optiflow_stats.txt

echo -e "\nPerf Stats of camera_ONR-OD-8200-yolox-nano-lite-mmdet-coco-416x416\n" >> ${SOC}_optiflow_stats.txt
cat /run/camera_ONR-OD-8200-yolox-nano-lite-mmdet-coco-416x416.txt >> ${SOC}_optiflow_stats.txt

echo -e "\nPerf Stats of camera_TFL-CL-0000-mobileNetV1-mlperf\n" >> ${SOC}_optiflow_stats.txt
cat /run/camera_TFL-CL-0000-mobileNetV1-mlperf.txt >> ${SOC}_optiflow_stats.txt

echo -e "\nPerf Stats of camera_ONR-CL-6360-regNetx-200mf\n" >> ${SOC}_optiflow_stats.txt
cat /run/camera_ONR-CL-6360-regNetx-200mf.txt >> ${SOC}_optiflow_stats.txt

echo -e "\nPerf Stats of camera_TFL-OD-2020-ssdLite-mobDet-DSP-coco-320x320\n" >> ${SOC}_optiflow_stats.txt
cat /run/camera_TFL-OD-2020-ssdLite-mobDet-DSP-coco-320x320.txt >> ${SOC}_optiflow_stats.txt

sync
