#!/bin/bash

mkdir -p /opt/datasheet/

dump_inference_time()
{
	export GST_DEBUG_FILE=/run/trace.log
	export GST_DEBUG_NO_COLOR=1
	export GST_DEBUG="GST_TRACER:7"
	export GST_TRACERS="latency(flags=element)"

	rm $GST_DEBUG_FILE
	sleep 2
}

dump_video_perf()
{
	dump_inference_time

	timeout -s INT -k 15 10 gst-launch-1.0 multifilesrc location=/opt/edgeai-test-data/videos/video0_1280_768.h264 loop=true stop-index=-1 ! \
	h264parse ! v4l2h264dec capture-io-mode=5 ! tiovxmemalloc pool-size=12 ! video/x-raw, format=NV12 ! \
	tiovxmultiscaler name=split_01 src_0::roi-startx=0 src_0::roi-starty=0 src_0::roi-width=1280 src_0::roi-height=768 target=0 split_01. ! queue ! \
	video/x-raw, width=416, height=416 ! tiovxdlpreproc model=/opt/model_zoo/ONR-OD-8200-yolox-nano-lite-mmdet-coco-416x416  out-pool-size=4 ! \
	application/x-tensor-tiovx ! tidlinferer target=1  model=/opt/model_zoo/ONR-OD-8200-yolox-nano-lite-mmdet-coco-416x416 ! post_0.tensor split_01. ! \
	queue ! video/x-raw, width=1280, height=720 ! \
	post_0.sink tidlpostproc name=post_0 model=/opt/model_zoo/ONR-OD-8200-yolox-nano-lite-mmdet-coco-416x416 alpha=0.200000 viz-threshold=0.600000 top-N=5 display-model=true ! queue ! \
	mosaic_0. tiovxmosaic name=mosaic_0 target=1 src::pool-size=4 sink_0::startx="<320>" sink_0::starty="<150>" sink_0::widths="<1280>" sink_0::heights="<720>" ! \
	video/x-raw,format=NV12, width=1920, height=1080 ! queue ! \
	tiperfoverlay title="Object Detection" overlay-type=graph dump=true location=/opt/datasheet/video_ONR-OD-8200-yolox-nano-lite-mmdet-coco-416x416.csv num-dumps=1 start-dumps=150 ! \
	kmssink driver-name=tidss sync=false

	sleep 2

	timeout -s INT -k 7 5 $EDGEAI_GST_APPS_PATH/scripts/gst_tracers/parse_gst_tracers.py $GST_DEBUG_FILE 2>/dev/null | stdbuf --output=0 grep tidlinferer 2>/dev/null | \
	head -n 1 >> /opt/datasheet/video_ONR-OD-8200-yolox-nano-lite-mmdet-coco-416x416.csv

	dump_inference_time

	timeout -s INT -k 15 10 gst-launch-1.0 multifilesrc location=/opt/edgeai-test-data/videos/video0_1280_768.h264 loop=true stop-index=-1 ! h264parse ! v4l2h264dec capture-io-mode=5 ! \
	tiovxmemalloc pool-size=12 ! video/x-raw, format=NV12 ! \
	tiovxmultiscaler name=split_01 src_0::roi-startx=0 src_0::roi-starty=0 src_0::roi-width=1280 src_0::roi-height=768 target=0 split_01. ! queue ! video/x-raw, width=320, height=320 ! \
	tiovxdlpreproc model=/opt/model_zoo/TFL-OD-2020-ssdLite-mobDet-DSP-coco-320x320  out-pool-size=4 ! application/x-tensor-tiovx ! \
	tidlinferer target=1  model=/opt/model_zoo/TFL-OD-2020-ssdLite-mobDet-DSP-coco-320x320 ! post_0.tensor split_01. ! queue ! video/x-raw, width=1280, height=720 ! \
	post_0.sink tidlpostproc name=post_0 model=/opt/model_zoo/TFL-OD-2020-ssdLite-mobDet-DSP-coco-320x320 alpha=0.200000 viz-threshold=0.600000 top-N=5 display-model=true ! \
	queue ! mosaic_0. tiovxmosaic name=mosaic_0 target=1 src::pool-size=4 sink_0::startx="<320>" sink_0::starty="<150>" sink_0::widths="<1280>" sink_0::heights="<720>" ! \
	video/x-raw,format=NV12, width=1920, height=1080 ! queue ! \
	tiperfoverlay title="Object Detection" overlay-type=graph dump=true location=/opt/datasheet/video_TFL-OD-2020-ssdLite-mobDet-DSP-coco-320x320.csv num-dumps=1 start-dumps=150 ! \
	kmssink driver-name=tidss sync=false

	sleep 2

	timeout -s INT -k 7 5 $EDGEAI_GST_APPS_PATH/scripts/gst_tracers/parse_gst_tracers.py $GST_DEBUG_FILE 2>/dev/null | stdbuf --output=0 grep tidlinferer 2>/dev/null | \
	head -n 1 >> /opt/datasheet/video_TFL-OD-2020-ssdLite-mobDet-DSP-coco-320x320.csv

	dump_inference_time

	timeout -s INT -k 15 10 gst-launch-1.0 multifilesrc location=/opt/edgeai-test-data/videos/video0_1280_768.h264 loop=true stop-index=-1 ! h264parse ! v4l2h264dec capture-io-mode=5 ! \
	tiovxmemalloc pool-size=12 ! video/x-raw, format=NV12 ! tiovxmultiscaler name=split_01 src_0::roi-startx=80 src_0::roi-starty=48 src_0::roi-width=1120 src_0::roi-height=672 target=0 split_01. ! \
       	queue ! video/x-raw, width=280, height=224 ! tiovxmultiscaler target=1 ! video/x-raw, width=224, height=224 ! tiovxdlpreproc model=/opt/model_zoo/ONR-CL-6360-regNetx-200mf  out-pool-size=4 ! \
	application/x-tensor-tiovx ! tidlinferer target=1  model=/opt/model_zoo/ONR-CL-6360-regNetx-200mf ! post_0.tensor split_01. ! queue ! video/x-raw, width=1280, height=720 ! \
	post_0.sink tidlpostproc name=post_0 model=/opt/model_zoo/ONR-CL-6360-regNetx-200mf alpha=0.200000 viz-threshold=0.500000 top-N=5 display-model=true ! queue ! \
	mosaic_0. tiovxmosaic name=mosaic_0 target=1 src::pool-size=4 sink_0::startx="<320>" sink_0::starty="<150>" sink_0::widths="<1280>" sink_0::heights="<720>" ! \
	video/x-raw,format=NV12, width=1920, height=1080 ! queue ! tiperfoverlay title="Image Classification" overlay-type=graph dump=true \
	location=/opt/datasheet/video_ONR-CL-6360-regNetx-200mf.csv num-dumps=1 start-dumps=5 ! kmssink driver-name=tidss sync=false force-modesetting=true

	sleep 2

	timeout -s INT -k 7 5 $EDGEAI_GST_APPS_PATH/scripts/gst_tracers/parse_gst_tracers.py $GST_DEBUG_FILE 2>/dev/null | stdbuf --output=0 grep tidlinferer 2>/dev/null | \
	head -n 1 >> /opt/datasheet/video_ONR-CL-6360-regNetx-200mf.csv

	dump_inference_time

	timeout -s INT -k 15 10 gst-launch-1.0 multifilesrc location=/opt/edgeai-test-data/videos/video0_1280_768.h264 loop=true stop-index=-1 ! h264parse ! v4l2h264dec capture-io-mode=5 ! \
	tiovxmemalloc pool-size=12 ! video/x-raw, format=NV12 ! tiovxmultiscaler name=split_01 src_0::roi-startx=80 src_0::roi-starty=48 src_0::roi-width=1120 src_0::roi-height=672 target=0 split_01. ! \
       	queue ! video/x-raw, width=280, height=224 ! tiovxmultiscaler target=1 ! video/x-raw, width=224, height=224 ! tiovxdlpreproc model=/opt/model_zoo/TFL-CL-0000-mobileNetV1-mlperf  out-pool-size=4 !\
	application/x-tensor-tiovx ! tidlinferer target=1  model=/opt/model_zoo/TFL-CL-0000-mobileNetV1-mlperf ! post_0.tensor split_01. ! queue ! video/x-raw, width=1280, height=720 ! \
	post_0.sink tidlpostproc name=post_0 model=/opt/model_zoo/TFL-CL-0000-mobileNetV1-mlperf alpha=0.200000 viz-threshold=0.500000 top-N=5 display-model=true ! queue ! \
	mosaic_0. tiovxmosaic name=mosaic_0 target=1 src::pool-size=4 sink_0::startx="<320>" sink_0::starty="<150>" sink_0::widths="<1280>" sink_0::heights="<720>" ! \
	video/x-raw,format=NV12, width=1920, height=1080 ! queue ! tiperfoverlay title="Image Classification" overlay-type=graph dump=true \
	location=/opt/datasheet/video_TFL-CL-0000-mobileNetV1-mlperf.csv num-dumps=1 start-dumps=5 ! kmssink driver-name=tidss sync=false force-modesetting=true

	sleep 2

	timeout -s INT -k 7 5 $EDGEAI_GST_APPS_PATH/scripts/gst_tracers/parse_gst_tracers.py $GST_DEBUG_FILE 2>/dev/null | stdbuf --output=0 grep tidlinferer 2>/dev/null | \
	head -n 1 >> /opt/datasheet/video_TFL-CL-0000-mobileNetV1-mlperf.csv
}

dump_camera_perf()
{

	dump_inference_time

	timeout -s INT -k 15 10 gst-launch-1.0 v4l2src device=/dev/video-imx219-cam0 io-mode=5 ! queue leaky=2 ! video/x-bayer, width=1920, height=1080, format=rggb ! \
	tiovxisp sensor-name=SENSOR_SONY_IMX219_RPI dcc-isp-file=/opt/imaging/imx219/linear/dcc_viss.bin format-msb=7 sink_0::dcc-2a-file=/opt/imaging/imx219/linear/dcc_2a.bin sink_0::device=/dev/v4l-imx219-subdev0 ! \
	video/x-raw, format=NV12 ! tiovxmultiscaler name=split_01 src_0::roi-startx=0 src_0::roi-starty=0 src_0::roi-width=1920 src_0::roi-height=1080 target=0 split_01. ! queue ! \
	video/x-raw, width=480, height=416 ! tiovxmultiscaler target=1 ! video/x-raw, width=416, height=416 ! tiovxdlpreproc model=/opt/model_zoo/ONR-OD-8200-yolox-nano-lite-mmdet-coco-416x416  out-pool-size=4 ! \
	application/x-tensor-tiovx ! tidlinferer target=1  model=/opt/model_zoo/ONR-OD-8200-yolox-nano-lite-mmdet-coco-416x416 ! post_0.tensor split_01. ! \
	queue ! video/x-raw, width=1280, height=720 ! \
	post_0.sink tidlpostproc name=post_0 model=/opt/model_zoo/ONR-OD-8200-yolox-nano-lite-mmdet-coco-416x416 alpha=0.200000 viz-threshold=0.600000 top-N=5 display-model=true ! queue ! \
	mosaic_0. tiovxmosaic name=mosaic_0 target=1 src::pool-size=4 sink_0::startx="<320>" sink_0::starty="<150>" sink_0::widths="<1280>" sink_0::heights="<720>" ! \
	video/x-raw,format=NV12, width=1920, height=1080 ! queue ! \
	tiperfoverlay title="Object Detection" overlay-type=graph dump=true location=/opt/datasheet/camera_ONR-OD-8200-yolox-nano-lite-mmdet-coco-416x416.csv num-dumps=1 start-dumps=150 ! \
	kmssink driver-name=tidss sync=false

	sleep 2

	timeout -s INT -k 7 5 $EDGEAI_GST_APPS_PATH/scripts/gst_tracers/parse_gst_tracers.py $GST_DEBUG_FILE 2>/dev/null | stdbuf --output=0 grep tidlinferer 2>/dev/null | \
	head -n 1 >> /opt/datasheet/camera_ONR-OD-8200-yolox-nano-lite-mmdet-coco-416x416.csv

	dump_inference_time

	timeout -s INT -k 15 10 gst-launch-1.0 v4l2src device=/dev/video-imx219-cam0 io-mode=5 ! queue leaky=2 ! video/x-bayer, width=1920, height=1080, format=rggb ! \
	tiovxisp sensor-name=SENSOR_SONY_IMX219_RPI dcc-isp-file=/opt/imaging/imx219/linear/dcc_viss.bin format-msb=7 sink_0::dcc-2a-file=/opt/imaging/imx219/linear/dcc_2a.bin sink_0::device=/dev/v4l-imx219-subdev0 ! \
	video/x-raw, format=NV12 ! tiovxmultiscaler name=split_01 src_0::roi-startx=0 src_0::roi-starty=0 src_0::roi-width=1920 src_0::roi-height=1080 target=0 split_01. ! queue ! video/x-raw, width=480, height=320 ! \
	tiovxmultiscaler target=1 ! video/x-raw, width=320, height=320 ! tiovxdlpreproc model=/opt/model_zoo/TFL-OD-2020-ssdLite-mobDet-DSP-coco-320x320  out-pool-size=4 ! application/x-tensor-tiovx ! \
	tidlinferer target=1  model=/opt/model_zoo/TFL-OD-2020-ssdLite-mobDet-DSP-coco-320x320 ! post_0.tensor split_01. ! queue ! video/x-raw, width=1280, height=720 ! \
	post_0.sink tidlpostproc name=post_0 model=/opt/model_zoo/TFL-OD-2020-ssdLite-mobDet-DSP-coco-320x320 alpha=0.200000 viz-threshold=0.600000 top-N=5 display-model=true ! \
	queue ! mosaic_0. tiovxmosaic name=mosaic_0 target=1 src::pool-size=4 sink_0::startx="<320>" sink_0::starty="<150>" sink_0::widths="<1280>" sink_0::heights="<720>" ! \
	video/x-raw,format=NV12, width=1920, height=1080 ! queue ! \
	tiperfoverlay title="Object Detection" overlay-type=graph dump=true location=/opt/datasheet/camera_TFL-OD-2020-ssdLite-mobDet-DSP-coco-320x320.csv num-dumps=1 start-dumps=150 ! \
	kmssink driver-name=tidss sync=false

	sleep 2

	timeout -s INT -k 7 5 $EDGEAI_GST_APPS_PATH/scripts/gst_tracers/parse_gst_tracers.py $GST_DEBUG_FILE 2>/dev/null | stdbuf --output=0 grep tidlinferer 2>/dev/null | \
	head -n 1 >> /opt/datasheet/camera_TFL-OD-2020-ssdLite-mobDet-DSP-coco-320x320.csv

	dump_inference_time

	timeout -s INT -k 15 10 gst-launch-1.0 v4l2src device=/dev/video-imx219-cam0 io-mode=5 ! queue leaky=2 ! video/x-bayer, width=1920, height=1080, format=rggb ! \
	tiovxisp sensor-name=SENSOR_SONY_IMX219_RPI dcc-isp-file=/opt/imaging/imx219/linear/dcc_viss.bin format-msb=7 sink_0::dcc-2a-file=/opt/imaging/imx219/linear/dcc_2a.bin sink_0::device=/dev/v4l-imx219-subdev0 ! \
	video/x-raw, format=NV12 ! tiovxmultiscaler name=split_01 src_0::roi-startx=120 src_0::roi-starty=67 src_0::roi-width=1680 src_0::roi-height=946 target=0 split_01. ! queue ! video/x-raw, width=420, height=238 ! \
	tiovxmultiscaler target=1 ! video/x-raw, width=224, height=224 ! tiovxdlpreproc model=/opt/model_zoo/ONR-CL-6360-regNetx-200mf  out-pool-size=4 ! application/x-tensor-tiovx ! \
	tidlinferer target=1  model=/opt/model_zoo/ONR-CL-6360-regNetx-200mf ! post_0.tensor split_01. ! queue ! video/x-raw, width=1280, height=720 ! \
	post_0.sink tidlpostproc name=post_0 model=/opt/model_zoo/ONR-CL-6360-regNetx-200mf alpha=0.200000 viz-threshold=0.500000 top-N=5 display-model=true ! queue ! \
	mosaic_0. tiovxmosaic name=mosaic_0 target=1 src::pool-size=4 sink_0::startx="<320>" sink_0::starty="<150>" sink_0::widths="<1280>" sink_0::heights="<720>" ! \
	video/x-raw,format=NV12, width=1920, height=1080 ! queue ! \
	tiperfoverlay title="Image Classification" overlay-type=graph dump=true location=/opt/datasheet/camera_ONR-CL-6360-regNetx-200mf.csv num-dumps=1 start-dumps=5 ! \
	kmssink driver-name=tidss sync=true

	sleep 2

	timeout -s INT -k 7 5 $EDGEAI_GST_APPS_PATH/scripts/gst_tracers/parse_gst_tracers.py $GST_DEBUG_FILE 2>/dev/null | stdbuf --output=0 grep tidlinferer 2>/dev/null | \
	head -n 1 >> /opt/datasheet/camera_ONR-CL-6360-regNetx-200mf.csv

	dump_inference_time

	timeout -s INT -k 15 10 gst-launch-1.0 v4l2src device=/dev/video-imx219-cam0 io-mode=5 ! queue leaky=2 ! video/x-bayer, width=1920, height=1080, format=rggb ! \
	tiovxisp sensor-name=SENSOR_SONY_IMX219_RPI dcc-isp-file=/opt/imaging/imx219/linear/dcc_viss.bin format-msb=7 sink_0::dcc-2a-file=/opt/imaging/imx219/linear/dcc_2a.bin sink_0::device=/dev/v4l-imx219-subdev0 ! \
	video/x-raw, format=NV12 ! tiovxmultiscaler name=split_01 src_0::roi-startx=120 src_0::roi-starty=67 src_0::roi-width=1680 src_0::roi-height=946 target=0 split_01. ! queue ! video/x-raw, width=420, height=238 ! \
	tiovxmultiscaler target=1 ! video/x-raw, width=224, height=224 ! tiovxdlpreproc model=/opt/model_zoo/TFL-CL-0000-mobileNetV1-mlperf  out-pool-size=4 ! application/x-tensor-tiovx ! \
	tidlinferer target=1  model=/opt/model_zoo/TFL-CL-0000-mobileNetV1-mlperf ! post_0.tensor split_01. ! queue ! video/x-raw, width=1280, height=720 ! \
	post_0.sink tidlpostproc name=post_0 model=/opt/model_zoo/TFL-CL-0000-mobileNetV1-mlperf alpha=0.200000 viz-threshold=0.500000 top-N=5 display-model=true ! queue ! \
	mosaic_0. tiovxmosaic name=mosaic_0 target=1 src::pool-size=4 sink_0::startx="<320>" sink_0::starty="<150>" sink_0::widths="<1280>" sink_0::heights="<720>" ! \
	video/x-raw,format=NV12, width=1920, height=1080 ! queue ! \
	tiperfoverlay title="Image Classification" overlay-type=graph dump=true location=/opt/datasheet/camera_TFL-CL-0000-mobileNetV1-mlperf.csv num-dumps=1 start-dumps=5 ! \
	kmssink driver-name=tidss sync=true

	sleep 2

	timeout -s INT -k 7 5 $EDGEAI_GST_APPS_PATH/scripts/gst_tracers/parse_gst_tracers.py $GST_DEBUG_FILE 2>/dev/null | stdbuf --output=0 grep tidlinferer 2>/dev/null | \
	head -n 1 >> /opt/datasheet/camera_TFL-CL-0000-mobileNetV1-mlperf.csv
}

dump_video_perf
dump_camera_perf
