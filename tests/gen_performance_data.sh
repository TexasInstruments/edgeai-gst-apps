#!/bin/bash

################################################################################

NUM_BUFFERS=600
LOOP_COUNT=1
LOG_FILE="$SOC"_perf_stats.csv
START_DUMPS=300
NUM_DUMPS=5
PERF="queue ! tiperfoverlay dump=true overlay=false location=$LOG_FILE \
      start-dumps=$START_DUMPS num-dumps=$NUM_DUMPS"
FILTER=""

################################################################################
VIDEO_FILE_MP4_1MP=/opt/edgeai-test-data/videos/video_0000_h264.mp4
VIDEO_FILE_H264_1MP=/opt/edgeai-test-data/videos/video_0000_h264.h264
VIDEO_FILE_H264_2MP=/opt/edgeai-test-data/videos/video_0000_h264_2mp.h264
VIDEO_FILE_H265_2MP=/opt/edgeai-test-data/videos/video_0000_h265_2mp.h265

VIDEOTESTSRC_2MP="videotestsrc pattern=4 num-buffers=600 is-live=true ! video/x-raw,format=NV12,width=1920,height=1080,framerate=30/1"

if [ "$SOC" == "j721e" ]
then
  H264_DECODE="v4l2h264dec capture-io-mode=5 ! tiovxmemalloc pool-size=8"
  H265_DECODE="v4l2h265dec capture-io-mode=5 ! tiovxmemalloc pool-size=8"
else
  H264_DECODE="v4l2h264dec"
  H265_DECODE="v4l2h265dec"
fi

VIDEO_H264_2MP()
{
  cp $VIDEO_FILE_H264_2MP $VIDEO_FILE_H264_2MP$1
  echo "multifilesrc location=$VIDEO_FILE_H264_2MP$1"
  echo "stop-index=$LOOP_COUNT"
  echo "caps=\"video/x-h264, width=1920, height=1080\" !"
  echo "h264parse ! $H264_DECODE ! video/x-raw,format=NV12"
}

VIDEO_H265_2MP()
{
  cp $VIDEO_FILE_H265_2MP $VIDEO_FILE_H265_2MP$1
  echo "multifilesrc location=$VIDEO_FILE_H265_2MP$1"
  echo "stop-index=$LOOP_COUNT"
  echo "caps=\"video/x-h265, width=1920, height=1088\" !"
  echo "h265parse ! $H265_DECODE ! video/x-raw,format=NV12"
}

################################################################################

IMX390()
{

  if [ "`$EDGEAI_GST_APPS_PATH/scripts/setup_cameras.sh | grep "imx390"`" == "" ]
  then
    return
  fi

  if [ "$1" == "" ]
  then
    return
  fi

  IMX390_DEV=(`$EDGEAI_GST_APPS_PATH/scripts/setup_cameras.sh | grep "IMX390 Camera $1" -A 4 | grep device`)
  IMX390_DEV=${IMX390_DEV[2]}
  if [ "$IMX390_DEV" == "" ]
  then
    echo "[WARN] IMX390 camera $1 not connected, Skipping tests"
  fi

  IMX390_SUBDEV=(`$EDGEAI_GST_APPS_PATH/scripts/setup_cameras.sh | grep "IMX390 Camera $1" -A 4 | grep subdev_id`)
  IMX390_SUBDEV=${IMX390_SUBDEV[2]}

  IMX390_SRC="v4l2src device=$IMX390_DEV io-mode=5 num-buffers=$NUM_BUFFERS"
  IMX390_FMT="video/x-bayer, width=1936, height=1100, format=rggb12"
  IMX390_ISP_COMMON_PROPS="dcc-isp-file=/opt/imaging/imx390/dcc_viss.bin \
                           format-msb=11 \
                           sensor-name=SENSOR_SONY_IMX390_UB953_D3 \
                           sink_0::dcc-2a-file=/opt/imaging/imx390/dcc_2a.bin"
  IMX390_ISP="tiovxisp $IMX390_ISP_COMMON_PROPS sink_0::device=$IMX390_SUBDEV"
  IMX390_LDC_COMMON_PROPS="sensor-name=SENSOR_SONY_IMX390_UB953_D3 dcc-file=/opt/imaging/imx390/dcc_ldc.bin"
  IMX390_LDC="tiovxldc $IMX390_LDC_COMMON_PROPS ! video/x-raw,format=NV12,width=1920,height=1080"
  echo "$IMX390_SRC ! queue ! $IMX390_FMT ! $IMX390_ISP ! video/x-raw,format=NV12 ! $IMX390_LDC"
}

################################################################################

IMX219()
{
  if [ "`$EDGEAI_GST_APPS_PATH/scripts/setup_cameras.sh | grep "imx219"`" == "" ]
  then
    return
  fi

  if [ "$1" == "" ]
  then
    return
  fi

  IMX219_DEV=(`$EDGEAI_GST_APPS_PATH/scripts/setup_cameras.sh | grep "CSI Camera $1" -A 4 | grep device`)
  IMX219_DEV=${IMX219_DEV[2]}
  if [ "$IMX219_DEV" == "" ]
  then
    echo "[WARN] IMX219 camera $1 not connected, Skipping tests"
  fi

  IMX219_SUBDEV=(`$EDGEAI_GST_APPS_PATH/scripts/setup_cameras.sh | grep "CSI Camera $1" -A 4 | grep subdev_id`)
  IMX219_SUBDEV=${IMX219_SUBDEV[2]}

  IMX219_SRC="v4l2src device=$IMX219_DEV io-mode=5 num-buffers=$NUM_BUFFERS"
  IMX219_FMT="video/x-bayer, width=1920, height=1080, format=rggb"
  IMX219_ISP_COMMON_PROPS="dcc-isp-file=/opt/imaging/imx219/dcc_viss.bin \
                           format-msb=7 \
                           sink_0::dcc-2a-file=/opt/imaging/imx219/dcc_2a.bin"
  IMX219_ISP="tiovxisp $IMX219_ISP_COMMON_PROPS sink_0::device=$IMX219_SUBDEV"
  echo "$IMX219_SRC ! queue ! $IMX219_FMT ! $IMX219_ISP"
}

################################################################################

POST_PROC_PROPS="alpha=0.400000 viz-threshold=0.600000 top-N=5"
POST_PROC_CAPS="video/x-raw, width=640, height=360"

MODEL_OD=/opt/model_zoo/ONR-OD-8200-yolox-nano-lite-mmdet-coco-416x416
MODEL_OD_PRE_PROC_PROPS="data-type=3 channel-order=0 tensor-format=bgr out-pool-size=4"
MODEL_OD_CAPS="video/x-raw, width=416, height=416"

INFER_OD()
{
  if [ "$2" == "" ]
  then
    target=0
  else
    target=$2
  fi

  if [[ "$1" == "" || "$(($1%2))" == "0" ]]
  then
    echo "tiovxmultiscaler target=$target name=split$1"
    echo "src_0::roi-startx=360 src_0::roi-starty=200"
    echo "src_0::roi-width=1200 src_0::roi-height=680"
    echo "src_1::roi-startx=360 src_1::roi-starty=200"
    echo "src_1::roi-width=1200 src_1::roi-height=680"
    echo "src_2::roi-startx=360 src_2::roi-starty=200"
    echo "src_2::roi-width=1200 src_2::roi-height=680"
    echo "src_3::roi-startx=360 src_3::roi-starty=200"
    echo "src_3::roi-width=1200 src_3::roi-height=680"
    split_name="split$1"
  else
    split_name="split$(($1 - 1))"
  fi
  echo "$split_name. ! queue ! $MODEL_OD_CAPS !"
  echo "tiovxdlpreproc $MODEL_OD_PRE_PROC_PROPS !"
  echo "tidlinferer model=$MODEL_OD !"
  echo "post$1.tensor"
  echo "$split_name. ! queue ! $POST_PROC_CAPS !"
  echo "post$1.sink"
  echo "tidlpostproc $POST_PROC_PROPS name=post$1 model=$MODEL_OD"
}

MODEL_CL=/opt/model_zoo/TFL-CL-0000-mobileNetV1-mlperf
MODEL_CL_PRE_PROC_PROPS="data-type=3 channel-order=1 tensor-format=rgb out-pool-size=4"
MODEL_CL_CAPS="video/x-raw, width=224, height=224"

INFER_CL()
{
  if [ "$2" == "" ]
  then
    target=0
  else
    target=$2
  fi

  if [[ "$1" == "" || "$(($1%2))" == "0" ]]
  then
    echo "tiovxmultiscaler target=$target name=split$1"
    echo "src_0::roi-startx=0 src_0::roi-starty=0"
    echo "src_0::roi-width=896 src_0::roi-height=896"
    echo "src_2::roi-startx=0 src_2::roi-starty=0"
    echo "src_2::roi-width=896 src_2::roi-height=896"
    split_name="split$1"
  else
    split_name="split$(($1 - 1))"
  fi
  echo "$split_name. ! queue ! $MODEL_CL_CAPS !"
  echo "tiovxdlpreproc $MODEL_CL_PRE_PROC_PROPS !"
  echo "tidlinferer model=$MODEL_CL !"
  echo "post$1.tensor"
  echo "$split_name. ! queue ! $POST_PROC_CAPS !"
  echo "post$1.sink"
  echo "tidlpostproc $POST_PROC_PROPS name=post$1 model=$MODEL_CL"
}

MODEL_SS=/opt/model_zoo/ONR-SS-8610-deeplabv3lite-mobv2-ade20k32-512x512
MODEL_SS_PRE_PROC_PROPS="data-type=3 channel-order=0 tensor-format=rgb out-pool-size=4"
MODEL_SS_CAPS="video/x-raw, width=512, height=512"

INFER_SS()
{
  if [ "$2" == "" ]
  then
    target=0
  else
    target=$2
  fi

  if [[ "$1" == "" || "$(($1%2))" == "0" ]]
  then
    echo "tiovxmultiscaler target=$target name=split$1"
    split_name="split$1"
  else
    split_name="split$(($1 - 1))"
  fi
  echo "$split_name. ! queue ! $MODEL_SS_CAPS !"
  echo "tiovxdlpreproc $MODEL_SS_PRE_PROC_PROPS !"
  echo "tidlinferer model=$MODEL_SS !"
  echo "post$1.tensor"
  echo "$split_name. ! queue ! $POST_PROC_CAPS !"
  echo "post$1.sink"
  echo "tidlpostproc $POST_PROC_PROPS name=post$1 model=$MODEL_SS"
}
################################################################################

MOSAIC()
{

  WINDOW_WIDTH=640
  WINDOW_HEIGHT=360
  NUM_WINDOWS_X=3
  NUM_WINDOWS_Y=3
  OUT_WIDTH=1920
  OUT_HEIGHT=1080

  if [ $(($1 > 9)) == "1" ]
  then
    WINDOW_WIDTH=480
    WINDOW_HEIGHT=270
    NUM_WINDOWS_X=4
    NUM_WINDOWS_Y=4
  fi

  echo "tiovxmosaic name=mosaic target=2"
  for ((i=0;i<$1;i++))
  do
    startx=$(($i % $NUM_WINDOWS_X * $WINDOW_WIDTH));
    starty=$(($i/$NUM_WINDOWS_X % $NUM_WINDOWS_Y * $WINDOW_HEIGHT));
    echo "sink_$i::startx=<$startx> sink_$i::starty=<$starty>"
    echo "sink_$i::widths=<$WINDOW_WIDTH> sink_$i::heights=<$WINDOW_HEIGHT>"
  done
  echo "! video/x-raw, width=$OUT_WIDTH, height=$OUT_HEIGHT"
}

################################################################################

DISPLAY="kmssink sync=false driver-name=tidss"
ENCODE_H264="v4l2h264enc bitrate=10000000 ! fakesink sync=true"
ENCODE_H265="v4l2h265enc ! fakesink sync=true"

###############################################################################

GST_LAUNCH()
{
  sleep 2
  set -x
  gst-launch-1.0 $1
  set +x
}

################################################################################
############################## SISO TEST CASES #################################
################################################################################
SISO_TEST_CASE_0001()
{
  echo "" >> $LOG_FILE

  NAME="SISO_TEST_CASE_0001"
  TITLE="1x IMX219 2MP @30fps - ISP - MSC - PreProc - 1x DLInferer (classification) - PostProc (1MP) - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX219 0) ! $(INFER_CL) ! $(MOSAIC 1) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################
SISO_TEST_CASE_0002()
{
  echo "" >> $LOG_FILE

  NAME="SISO_TEST_CASE_0002"
  TITLE="1x IMX219 2MP @30fps - ISP - MSC - PreProc - 1x DLInferer (detection) - PostProc (1MP) - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX219 0) ! $(INFER_OD) ! $(MOSAIC 1) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################
SISO_TEST_CASE_0003()
{
  echo "" >> $LOG_FILE

  NAME="SISO_TEST_CASE_0003"
  TITLE="1x IMX219 2MP @30fps - ISP - MSC - PreProc - 1x DLInferer (segmentation) - PostProc (1MP) - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX219 0) ! $(INFER_SS) ! $(MOSAIC 1) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################
SISO_TEST_CASE_0004()
{
  echo "" >> $LOG_FILE

  NAME="SISO_TEST_CASE_0004"
  TITLE="1x IMX219 2MP @30fps - ISP - MSC - PreProc - 1x DLInferer (classification) - PostProc (2MP) - H.264 Encode (IPP | High | 2MP @ 30fps | 10Mbps)"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX219 0) ! $(INFER_CL) ! $(MOSAIC 1) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H264"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################
SISO_TEST_CASE_0005()
{
  echo "" >> $LOG_FILE

  NAME="SISO_TEST_CASE_0005"
  TITLE="1x IMX219 2MP @30fps - ISP - MSC - PreProc - 1x DLInferer (detection) - PostProc (2MP) - H.264 Encode (IPP | High | 2MP @ 30fps | 10Mbps)"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX219 0) ! $(INFER_OD) ! $(MOSAIC 1) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H264"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################
SISO_TEST_CASE_0006()
{
  echo "" >> $LOG_FILE

  NAME="SISO_TEST_CASE_0006"
  TITLE="1x IMX219 2MP @30fps - ISP - MSC - PreProc - 1x DLInferer (segmentation) - PostProc (2MP) - H.264 Encode (IPP | High | 2MP @ 30fps | 10Mbps)"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX219 0) ! $(INFER_SS) ! $(MOSAIC 1) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H264"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################

SISO_TEST_CASE_0007()
{
  echo "" >> $LOG_FILE

  NAME="SISO_TEST_CASE_0007"
  TITLE="1x IMX219 2MP @30fps - ISP - MSC - PreProc - 1x DLInferer (classification) - PostProc (2MP) - H.265 Encode (IPP | High | 2MP @ 30fps | 10Mbps)"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX219 0) ! $(INFER_CL) ! $(MOSAIC 1) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H265"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################

SISO_TEST_CASE_0008()
{
  echo "" >> $LOG_FILE

  NAME="SISO_TEST_CASE_0008"
  TITLE="1x IMX219 2MP @30fps - ISP - MSC - PreProc - 1x DLInferer (detection) - PostProc (2MP) - H.265 Encode (IPP | High | 2MP @ 30fps | 10Mbps)"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX219 0) ! $(INFER_OD) ! $(MOSAIC 1) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H265"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################

SISO_TEST_CASE_0009()
{
  echo "" >> $LOG_FILE

  NAME="SISO_TEST_CASE_0009"
  TITLE="1x IMX219 2MP @30fps - ISP - MSC - PreProc - 1x DLInferer (segmentation) - PostProc (2MP) - H.265 Encode (IPP | High | 2MP @ 30fps | 10Mbps)"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX219 0) ! $(INFER_SS) ! $(MOSAIC 1) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H265"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################
SISO_TEST_CASE_0010()
{
  echo "" >> $LOG_FILE

  NAME="SISO_TEST_CASE_0010"
  TITLE="1x video 2MP @30fps - H.264 Decode - MSC - PreProc - 1x DLInferer (classification) - PostProc (1MP) - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H264_2MP) ! $(INFER_CL) ! $(MOSAIC 1) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################
SISO_TEST_CASE_0011()
{
  echo "" >> $LOG_FILE

  NAME="SISO_TEST_CASE_0011"
  TITLE="1x video 2MP @30fps - H.264 Decode - MSC - PreProc - 1x DLInferer (detection) - PostProc (1MP) - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H264_2MP) ! $(INFER_OD) ! $(MOSAIC 1) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################
SISO_TEST_CASE_0012()
{
  echo "" >> $LOG_FILE

  NAME="SISO_TEST_CASE_0012"
  TITLE="1x video 2MP @30fps - H.264 Decode - MSC - PreProc - 1x DLInferer (segmentation) - PostProc (1MP) - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H264_2MP) ! $(INFER_SS) ! $(MOSAIC 1) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################
SISO_TEST_CASE_0013()
{
  echo "" >> $LOG_FILE

  NAME="SISO_TEST_CASE_0013"
  TITLE="1x video 2MP @30fps - H.265 Decode - MSC - PreProc - 1x DLInferer (classification) - PostProc (1MP) - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H265_2MP) ! $(INFER_CL) ! $(MOSAIC 1) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################
SISO_TEST_CASE_0014()
{
  echo "" >> $LOG_FILE

  NAME="SISO_TEST_CASE_0014"
  TITLE="1x video 2MP @30fps - H.265 Decode - MSC - PreProc - 1x DLInferer (detection) - PostProc (1MP) - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H265_2MP) ! $(INFER_OD) ! $(MOSAIC 1) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################
SISO_TEST_CASE_0015()
{
  echo "" >> $LOG_FILE

  NAME="SISO_TEST_CASE_0015"
  TITLE="1x video 2MP @30fps - H.265 Decode - MSC - PreProc - 1x DLInferer (segmentation) - PostProc (1MP) - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H265_2MP) ! $(INFER_SS) ! $(MOSAIC 1) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################
SISO_TEST_CASE_0016()
{
  echo "" >> $LOG_FILE

  NAME="SISO_TEST_CASE_0016"
  TITLE="1x video 2MP @30fps - H.264 Decode - MSC - PreProc - 1x DLInferer (classification) - PostProc (2MP) - H.264 Encode (IPP | High | 2MP @ 30fps | 10Mbps)"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H264_2MP) ! $(INFER_CL) ! $(MOSAIC 1) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H264"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################
SISO_TEST_CASE_0017()
{
  echo "" >> $LOG_FILE

  NAME="SISO_TEST_CASE_0017"
  TITLE="1x video 2MP @30fps - H.264 Decode - MSC - PreProc - 1x DLInferer (detection) - PostProc (2MP) - H.264 Encode (IPP | High | 2MP @ 30fps | 10Mbps)"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H264_2MP) ! $(INFER_OD) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H264"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################
SISO_TEST_CASE_0018()
{
  echo "" >> $LOG_FILE

  NAME="SISO_TEST_CASE_0018"
  TITLE="1x video 2MP @30fps - H.264 Decode - MSC - PreProc - 1x DLInferer (segmentation) - PostProc (2MP) - H.264 Encode (IPP | High | 2MP @ 30fps | 10Mbps)"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H264_2MP) ! $(INFER_SS) ! $(MOSAIC 1) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H264"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################

SISO_TEST_CASE_0019()
{
  echo "" >> $LOG_FILE

  NAME="SISO_TEST_CASE_0019"
  TITLE="1x video 2MP @30fps - H.265 Decode - MSC - PreProc - 1x DLInferer (classification) - PostProc (2MP) - H.265 Encode (IPP | High | 2MP @ 30fps | 10Mbps)"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H265_2MP) ! $(INFER_CL) ! $(MOSAIC 1) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H265"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################

SISO_TEST_CASE_0020()
{
  echo "" >> $LOG_FILE

  NAME="SISO_TEST_CASE_0020"
  TITLE="1x video 2MP @30fps - H.265 Decode - MSC - PreProc - 1x DLInferer (detection) - PostProc (2MP) - H.265 Encode (IPP | High | 2MP @ 30fps | 10Mbps)"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H265_2MP) ! $(INFER_OD) ! $(MOSAIC 1) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H265"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################

SISO_TEST_CASE_0021()
{
  echo "" >> $LOG_FILE

  NAME="SISO_TEST_CASE_0021"
  TITLE="1x video 2MP @30fps - H.265 Decode - MSC - PreProc - 1x DLInferer (segmentation) - PostProc (2MP) - H.265 Encode (IPP | High | 2MP @ 30fps | 10Mbps)"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H265_2MP) ! $(INFER_SS) ! $(MOSAIC 1) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H265"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################
############################## SIMO TEST CASES #################################
################################################################################
SIMO_TEST_CASE_0001()
{
  echo "" >> $LOG_FILE

  NAME="SIMO_TEST_CASE_0001"
  TITLE="1x IMX219 2MP @30fps - ISP - MSC - PreProc - 4x DLInferer (classification) - PostProc - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX219 0) ! tee name=src_split \
              src_split. ! queue ! $(INFER_CL 0) ! queue ! mosaic. \
                                   $(INFER_CL 1) ! queue ! mosaic. \
              src_split. ! queue ! $(INFER_CL 2) ! queue ! mosaic. \
                                   $(INFER_CL 3) ! queue ! mosaic. \
              $(MOSAIC 4) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################
SIMO_TEST_CASE_0002()
{
  echo "" >> $LOG_FILE

  NAME="SIMO_TEST_CASE_0002"
  TITLE="1x IMX219 2MP @30fps - ISP - MSC - PreProc - 4x DLInferer (detection) - PostProc - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX219 0) ! tee name=src_split \
              src_split. ! queue ! $(INFER_OD 0) ! queue ! mosaic. \
                                   $(INFER_OD 1) ! queue ! mosaic. \
              src_split. ! queue ! $(INFER_OD 2) ! queue ! mosaic. \
                                   $(INFER_OD 3) ! queue ! mosaic. \
              $(MOSAIC 4) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################
SIMO_TEST_CASE_0003()
{
  echo "" >> $LOG_FILE

  NAME="SIMO_TEST_CASE_0003"
  TITLE="1x IMX219 2MP @30fps - ISP - MSC - PreProc - 4x DLInferer (segmentation) - PostProc - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX219 0) ! tee name=src_split \
              src_split. ! queue ! $(INFER_SS 0) ! queue ! mosaic. \
                                   $(INFER_SS 1) ! queue ! mosaic. \
              src_split. ! queue ! $(INFER_SS 2) ! queue ! mosaic. \
                                   $(INFER_SS 3) ! queue ! mosaic. \
              $(MOSAIC 4) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################
SIMO_TEST_CASE_0004()
{
  echo "" >> $LOG_FILE

  NAME="SIMO_TEST_CASE_0004"
  TITLE="1x IMX219 2MP @30fps - ISP - MSC - PreProc - 4x DLInferer (classification) - PostProc (2MP) - H.264 Encode (IPP | High | 2MP @ 30fps | 10Mbps)"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX219 0) ! tee name=src_split \
              src_split. ! queue ! $(INFER_CL 0) ! queue ! mosaic. \
                                   $(INFER_CL 1) ! queue ! mosaic. \
              src_split. ! queue ! $(INFER_CL 2) ! queue ! mosaic. \
                                   $(INFER_CL 3) ! queue ! mosaic. \
              $(MOSAIC 4) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H264"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################
SIMO_TEST_CASE_0005()
{
  echo "" >> $LOG_FILE

  NAME="SIMO_TEST_CASE_0005"
  TITLE="1x IMX219 2MP @30fps - ISP - MSC - PreProc - 4x DLInferer (detection) - PostProc (2MP) - H.264 Encode (IPP | High | 2MP @ 30fps | 10Mbps)"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX219 0) ! tee name=src_split \
              src_split. ! queue ! $(INFER_OD 0) ! queue ! mosaic. \
                                   $(INFER_OD 1) ! queue ! mosaic. \
              src_split. ! queue ! $(INFER_OD 2) ! queue ! mosaic. \
                                   $(INFER_OD 3) ! queue ! mosaic. \
              $(MOSAIC 4) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H264"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################
SIMO_TEST_CASE_0006()
{
  echo "" >> $LOG_FILE

  NAME="SIMO_TEST_CASE_0006"
  TITLE="1x IMX219 2MP @30fps - ISP - MSC - PreProc - 4x DLInferer (segmentation) - PostProc (2MP) - H.264 Encode (IPP | High | 2MP @ 30fps | 10Mbps)"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX219 0) ! tee name=src_split \
              src_split. ! queue ! $(INFER_SS 0) ! queue ! mosaic. \
                                   $(INFER_SS 1) ! queue ! mosaic. \
              src_split. ! queue ! $(INFER_SS 2) ! queue ! mosaic. \
                                   $(INFER_SS 3) ! queue ! mosaic. \
              $(MOSAIC 4) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H264"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################

SIMO_TEST_CASE_0007()
{
  echo "" >> $LOG_FILE

  NAME="SIMO_TEST_CASE_0007"
  TITLE="1x IMX219 2MP @30fps - ISP - MSC - PreProc - 4x DLInferer (classification) - PostProc (2MP) - H.265 Encode (IPP | High | 2MP @ 30fps | 10Mbps)"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX219 0) ! tee name=src_split \
              src_split. ! queue ! $(INFER_CL 0) ! queue ! mosaic. \
                                   $(INFER_CL 1) ! queue ! mosaic. \
              src_split. ! queue ! $(INFER_CL 2) ! queue ! mosaic. \
                                   $(INFER_CL 3) ! queue ! mosaic. \
              $(MOSAIC 4) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H265"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################

SIMO_TEST_CASE_0008()
{
  echo "" >> $LOG_FILE

  NAME="SIMO_TEST_CASE_0008"
  TITLE="1x IMX219 2MP @30fps - ISP - MSC - PreProc - 4x DLInferer (detection) - PostProc (2MP) - H.265 Encode (IPP | High | 2MP @ 30fps | 10Mbps)"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX219 0) ! tee name=src_split \
              src_split. ! queue ! $(INFER_OD 0) ! queue ! mosaic. \
                                   $(INFER_OD 1) ! queue ! mosaic. \
              src_split. ! queue ! $(INFER_OD 2) ! queue ! mosaic. \
                                   $(INFER_OD 3) ! queue ! mosaic. \
              $(MOSAIC 4) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H265"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################

SIMO_TEST_CASE_0009()
{
  echo "" >> $LOG_FILE

  NAME="SIMO_TEST_CASE_0009"
  TITLE="1x IMX219 2MP @30fps - ISP - MSC - PreProc - 4x DLInferer (segmentation) - PostProc (2MP) - H.265 Encode (IPP | High | 2MP @ 30fps | 10Mbps)"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX219 0) ! tee name=src_split \
              src_split. ! queue ! $(INFER_SS 0) ! queue ! mosaic. \
                                   $(INFER_SS 1) ! queue ! mosaic. \
              src_split. ! queue ! $(INFER_SS 2) ! queue ! mosaic. \
                                   $(INFER_SS 3) ! queue ! mosaic. \
              $(MOSAIC 4) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H265"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################
SIMO_TEST_CASE_0010()
{
  echo "" >> $LOG_FILE

  NAME="SIMO_TEST_CASE_0010"
  TITLE="1x video 2MP @30fps - H.264 Decode - MSC - PreProc - 4x DLInferer (classification) - PostProc - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H264_2MP) ! tee name=src_split \
              src_split. ! queue ! $(INFER_CL 0) ! queue ! mosaic. \
                                   $(INFER_CL 1) ! queue ! mosaic. \
              src_split. ! queue ! $(INFER_CL 2) ! queue ! mosaic. \
                                   $(INFER_CL 3) ! queue ! mosaic. \
              $(MOSAIC 4) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################
SIMO_TEST_CASE_0011()
{
  echo "" >> $LOG_FILE

  NAME="SIMO_TEST_CASE_0011"
  TITLE="1x video 2MP @30fps - H.264 Decode - MSC - PreProc - 4x DLInferer (detection) - PostProc - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H264_2MP) ! tee name=src_split \
              src_split. ! queue ! $(INFER_OD 0) ! queue ! mosaic. \
                                   $(INFER_OD 1) ! queue ! mosaic. \
              src_split. ! queue ! $(INFER_OD 2) ! queue ! mosaic. \
                                   $(INFER_OD 3) ! queue ! mosaic. \
              $(MOSAIC 4) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################
SIMO_TEST_CASE_0012()
{
  echo "" >> $LOG_FILE

  NAME="SIMO_TEST_CASE_0012"
  TITLE="1x video 2MP @30fps - H.264 Decode - MSC - PreProc - 4x DLInferer (segmentation) - PostProc - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H264_2MP) ! tee name=src_split \
              src_split. ! queue ! $(INFER_SS 0) ! queue ! mosaic. \
                                   $(INFER_SS 1) ! queue ! mosaic. \
              src_split. ! queue ! $(INFER_SS 2) ! queue ! mosaic. \
                                   $(INFER_SS 3) ! queue ! mosaic. \
              $(MOSAIC 4) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################
SIMO_TEST_CASE_0013()
{
  echo "" >> $LOG_FILE

  NAME="SIMO_TEST_CASE_0013"
  TITLE="1x video 2MP @30fps - H.265 Decode - MSC - PreProc - 4x DLInferer (classification) - PostProc - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H265_2MP) ! tee name=src_split \
              src_split. ! queue ! $(INFER_CL 0) ! queue ! mosaic. \
                                   $(INFER_CL 1) ! queue ! mosaic. \
              src_split. ! queue ! $(INFER_CL 2) ! queue ! mosaic. \
                                   $(INFER_CL 3) ! queue ! mosaic. \
              $(MOSAIC 4) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################
SIMO_TEST_CASE_0014()
{
  echo "" >> $LOG_FILE

  NAME="SIMO_TEST_CASE_0014"
  TITLE="1x video 2MP @30fps - H.265 Decode - MSC - PreProc - 4x DLInferer (detection) - PostProc - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H265_2MP) ! tee name=src_split \
              src_split. ! queue ! $(INFER_OD 0) ! queue ! mosaic. \
                                   $(INFER_OD 1) ! queue ! mosaic. \
              src_split. ! queue ! $(INFER_OD 2) ! queue ! mosaic. \
                                   $(INFER_OD 3) ! queue ! mosaic. \
              $(MOSAIC 4) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################
SIMO_TEST_CASE_0015()
{
  echo "" >> $LOG_FILE

  NAME="SIMO_TEST_CASE_0015"
  TITLE="1x video 2MP @30fps - H.265 Decode - MSC - PreProc - 4x DLInferer (se) - PostProc - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H265_2MP) ! tee name=src_split \
              src_split. ! queue ! $(INFER_SS 0) ! queue ! mosaic. \
                                   $(INFER_SS 1) ! queue ! mosaic. \
              src_split. ! queue ! $(INFER_SS 2) ! queue ! mosaic. \
                                   $(INFER_SS 3) ! queue ! mosaic. \
              $(MOSAIC 4) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################
SIMO_TEST_CASE_0016()
{
  echo "" >> $LOG_FILE

  NAME="SIMO_TEST_CASE_0016"
  TITLE="1x video 2MP @30fps - H.264 Decode - MSC - PreProc - 4x DLInferer (classification) - PostProc (2MP) - H.264 Encode (IPP | High | 2MP @ 30fps | 10Mbps)"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H264_2MP) ! tee name=src_split \
              src_split. ! queue ! $(INFER_CL 0) ! queue ! mosaic. \
                                   $(INFER_CL 1) ! queue ! mosaic. \
              src_split. ! queue ! $(INFER_CL 2) ! queue ! mosaic. \
                                   $(INFER_CL 3) ! queue ! mosaic. \
              $(MOSAIC 4) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H264"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################
SIMO_TEST_CASE_0017()
{
  echo "" >> $LOG_FILE

  NAME="SIMO_TEST_CASE_0017"
  TITLE="1x video 2MP @30fps - H.264 Decode - MSC - PreProc - 4x DLInferer (detection) - PostProc (2MP) - H.264 Encode (IPP | High | 2MP @ 30fps | 10Mbps)"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H264_2MP) ! tee name=src_split \
              src_split. ! queue ! $(INFER_OD 0) ! queue ! mosaic. \
                                   $(INFER_OD 1) ! queue ! mosaic. \
              src_split. ! queue ! $(INFER_OD 2) ! queue ! mosaic. \
                                   $(INFER_OD 3) ! queue ! mosaic. \
              $(MOSAIC 4) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H264"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################
SIMO_TEST_CASE_0018()
{
  echo "" >> $LOG_FILE

  NAME="SIMO_TEST_CASE_0018"
  TITLE="1x video 2MP @30fps - H.264 Decode - MSC - PreProc - 4x DLInferer (segmentation) - PostProc (2MP) - H.264 Encode (IPP | High | 2MP @ 30fps | 10Mbps)"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H264_2MP) ! tee name=src_split \
              src_split. ! queue ! $(INFER_SS 0) ! queue ! mosaic. \
                                   $(INFER_SS 1) ! queue ! mosaic. \
              src_split. ! queue ! $(INFER_SS 2) ! queue ! mosaic. \
                                   $(INFER_SS 3) ! queue ! mosaic. \
              $(MOSAIC 4) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H264"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################

SIMO_TEST_CASE_0019()
{
  echo "" >> $LOG_FILE

  NAME="SIMO_TEST_CASE_0019"
  TITLE="1x video 2MP @30fps - H.265 Decode - MSC - PreProc - 4x DLInferer (classification) - PostProc (2MP) - H.265 Encode (IPP | High | 2MP @ 30fps | 10Mbps)"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H265_2MP) ! tee name=src_split \
              src_split. ! queue ! $(INFER_CL 0) ! queue ! mosaic. \
                                   $(INFER_CL 1) ! queue ! mosaic. \
              src_split. ! queue ! $(INFER_CL 2) ! queue ! mosaic. \
                                   $(INFER_CL 3) ! queue ! mosaic. \
              $(MOSAIC 4) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H265"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################

SIMO_TEST_CASE_0020()
{
  echo "" >> $LOG_FILE

  NAME="SIMO_TEST_CASE_0020"
  TITLE="1x video 2MP @30fps - H.265 Decode - MSC - PreProc - 4x DLInferer (detection) - PostProc (2MP) - H.265 Encode (IPP | High | 2MP @ 30fps | 10Mbps)"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H265_2MP) ! tee name=src_split \
              src_split. ! queue ! $(INFER_OD 0) ! queue ! mosaic. \
                                   $(INFER_OD 1) ! queue ! mosaic. \
              src_split. ! queue ! $(INFER_OD 2) ! queue ! mosaic. \
                                   $(INFER_OD 3) ! queue ! mosaic. \
              $(MOSAIC 4) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H265"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################

SIMO_TEST_CASE_0021()
{
  echo "" >> $LOG_FILE

  NAME="SIMO_TEST_CASE_0021"
  TITLE="1x video 2MP @30fps - H.265 Decode - MSC - PreProc - 4x DLInferer (segmentation) - PostProc (2MP) - H.265 Encode (IPP | High | 2MP @ 30fps | 10Mbps)"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H265_2MP) ! tee name=src_split \
              src_split. ! queue ! $(INFER_SS 0) ! queue ! mosaic. \
                                   $(INFER_SS 1) ! queue ! mosaic. \
              src_split. ! queue ! $(INFER_SS 2) ! queue ! mosaic. \
                                   $(INFER_SS 3) ! queue ! mosaic. \
              $(MOSAIC 4) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H265"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################
############################## MIMO TEST CASES #################################
################################################################################
MIMO_TEST_CASE_0001()
{
  echo "" >> $LOG_FILE

  NAME="MIMO_TEST_CASE_0001"
  TITLE="2x IMX219 2MP @30fps - ISP - MSC - PreProc - 4x DLInferer (classification) - PostProc - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX219 0) ! $(INFER_CL 0) ! queue ! mosaic. \
                          $(INFER_CL 1) ! queue ! mosaic. \
              $(IMX219 1) ! $(INFER_CL 2) ! queue ! mosaic. \
                          $(INFER_CL 3) ! queue ! mosaic. \
              $(MOSAIC 4) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################
MIMO_TEST_CASE_0002()
{
  echo "" >> $LOG_FILE

  NAME="MIMO_TEST_CASE_0002"
  TITLE="2x IMX219 2MP @30fps - ISP - MSC - PreProc - 4x DLInferer (detection) - PostProc - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX219 0) ! $(INFER_OD 0) ! queue ! mosaic. \
                          $(INFER_OD 1) ! queue ! mosaic. \
              $(IMX219 1) ! $(INFER_OD 2) ! queue ! mosaic. \
                          $(INFER_OD 3) ! queue ! mosaic. \
              $(MOSAIC 4) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################
MIMO_TEST_CASE_0003()
{
  echo "" >> $LOG_FILE

  NAME="MIMO_TEST_CASE_0003"
  TITLE="2x IMX219 2MP @30fps - ISP - MSC - PreProc - 4x DLInferer (segmentation) - PostProc - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX219 0) ! $(INFER_SS 0) ! queue ! mosaic. \
                          $(INFER_SS 1) ! queue ! mosaic. \
              $(IMX219 1) ! $(INFER_SS 2) ! queue ! mosaic. \
                          $(INFER_SS 3) ! queue ! mosaic. \
              $(MOSAIC 4) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################
MIMO_TEST_CASE_0004()
{
  echo "" >> $LOG_FILE

  NAME="MIMO_TEST_CASE_0004"
  TITLE="2x IMX219 2MP @30fps - ISP - MSC - PreProc - 4x DLInferer (classification) - PostProc (2MP) - H.264 Encode (IPP | High | 2MP @ 30fps | 10Mbps)"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX219 0) ! $(INFER_CL 0) ! queue ! mosaic. \
                          $(INFER_CL 1) ! queue ! mosaic. \
              $(IMX219 1) ! $(INFER_CL 2) ! queue ! mosaic. \
                          $(INFER_CL 3) ! queue ! mosaic. \
              $(MOSAIC 4) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H264"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################
MIMO_TEST_CASE_0005()
{
  echo "" >> $LOG_FILE

  NAME="MIMO_TEST_CASE_0005"
  TITLE="2x IMX219 2MP @30fps - ISP - MSC - PreProc - 4x DLInferer (detection) - PostProc (2MP) - H.264 Encode (IPP | High | 2MP @ 30fps | 10Mbps)"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX219 0) ! $(INFER_OD 0) ! queue ! mosaic. \
                          $(INFER_OD 1) ! queue ! mosaic. \
              $(IMX219 1) ! $(INFER_OD 2) ! queue ! mosaic. \
                          $(INFER_OD 3) ! queue ! mosaic. \
              $(MOSAIC 4) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H264"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################
MIMO_TEST_CASE_0006()
{
  echo "" >> $LOG_FILE

  NAME="MIMO_TEST_CASE_0006"
  TITLE="2x IMX219 2MP @30fps - ISP - MSC - PreProc - 4x DLInferer (segmentation) - PostProc (2MP) - H.264 Encode (IPP | High | 2MP @ 30fps | 10Mbps)"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX219 0) ! $(INFER_SS 0) ! queue ! mosaic. \
                          $(INFER_SS 1) ! queue ! mosaic. \
              $(IMX219 1) ! $(INFER_SS 2) ! queue ! mosaic. \
                          $(INFER_SS 3) ! queue ! mosaic. \
              $(MOSAIC 4) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H264"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################

MIMO_TEST_CASE_0007()
{
  echo "" >> $LOG_FILE

  NAME="MIMO_TEST_CASE_0007"
  TITLE="2x IMX219 2MP @30fps - ISP - MSC - PreProc - 4x DLInferer (classification) - PostProc (2MP) - H.265 Encode (IPP | High | 2MP @ 30fps | 10Mbps)"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX219 0) ! $(INFER_CL 0) ! queue ! mosaic. \
                          $(INFER_CL 1) ! queue ! mosaic. \
              $(IMX219 1) ! $(INFER_CL 2) ! queue ! mosaic. \
                          $(INFER_CL 3) ! queue ! mosaic. \
              $(MOSAIC 4) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H265"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################

MIMO_TEST_CASE_0008()
{
  echo "" >> $LOG_FILE

  NAME="MIMO_TEST_CASE_0008"
  TITLE="2x IMX219 2MP @30fps - ISP - MSC - PreProc - 4x DLInferer (detection) - PostProc (2MP) - H.265 Encode (IPP | High | 2MP @ 30fps | 10Mbps)"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX219 0) ! $(INFER_OD 0) ! queue ! mosaic. \
                          $(INFER_OD 1) ! queue ! mosaic. \
              $(IMX219 1) ! $(INFER_OD 2) ! queue ! mosaic. \
                          $(INFER_OD 3) ! queue ! mosaic. \
              $(MOSAIC 4) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H265"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################

MIMO_TEST_CASE_0009()
{
  echo "" >> $LOG_FILE

  NAME="MIMO_TEST_CASE_0009"
  TITLE="2x IMX219 2MP @30fps - ISP - MSC - PreProc - 4x DLInferer (segmentation) - PostProc (2MP) - H.265 Encode (IPP | High | 2MP @ 30fps | 10Mbps)"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX219 0) ! $(INFER_SS 0) ! queue ! mosaic. \
                          $(INFER_SS 1) ! queue ! mosaic. \
              $(IMX219 1) ! $(INFER_SS 2) ! queue ! mosaic. \
                          $(INFER_SS 3) ! queue ! mosaic. \
              $(MOSAIC 4) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H265"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################
MIMO_TEST_CASE_0010()
{
  echo "" >> $LOG_FILE

  NAME="MIMO_TEST_CASE_0010"
  TITLE="2x video 2MP @30fps - H.264 Decode - MSC - PreProc - 4x DLInferer (classification) - PostProc - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H264_2MP 0) ! $(INFER_CL 0) ! queue ! mosaic. \
                                    $(INFER_CL 1) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 1) ! $(INFER_CL 2) ! queue ! mosaic. \
                                    $(INFER_CL 3) ! queue ! mosaic. \
              $(MOSAIC 4) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################
MIMO_TEST_CASE_0011()
{
  echo "" >> $LOG_FILE

  NAME="MIMO_TEST_CASE_0011"
  TITLE="2x video 2MP @30fps - H.264 Decode - MSC - PreProc - 4x DLInferer (detection) - PostProc - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H264_2MP 0) ! $(INFER_OD 0) ! queue ! mosaic. \
                                    $(INFER_OD 1) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 1) ! $(INFER_OD 2) ! queue ! mosaic. \
                                    $(INFER_OD 3) ! queue ! mosaic. \
              $(MOSAIC 4) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################
MIMO_TEST_CASE_0012()
{
  echo "" >> $LOG_FILE

  NAME="MIMO_TEST_CASE_0012"
  TITLE="2x video 2MP @30fps - H.264 Decode - MSC - PreProc - 4x DLInferer (segmentation) - PostProc - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H264_2MP 0) ! $(INFER_SS 0) ! queue ! mosaic. \
                                    $(INFER_SS 1) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 1) ! $(INFER_SS 2) ! queue ! mosaic. \
                                    $(INFER_SS 3) ! queue ! mosaic. \
              $(MOSAIC 4) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################
MIMO_TEST_CASE_0013()
{
  echo "" >> $LOG_FILE

  NAME="MIMO_TEST_CASE_0013"
  TITLE="2x video 2MP @30fps - H.265 Decode - MSC - PreProc - 4x DLInferer (classification) - PostProc - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H265_2MP 0) ! $(INFER_CL 0) ! queue ! mosaic. \
                                    $(INFER_CL 1) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 1) ! $(INFER_CL 2) ! queue ! mosaic. \
                                    $(INFER_CL 3) ! queue ! mosaic. \
              $(MOSAIC 4) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################
MIMO_TEST_CASE_0014()
{
  echo "" >> $LOG_FILE

  NAME="MIMO_TEST_CASE_0014"
  TITLE="2x video 2MP @30fps - H.265 Decode - MSC - PreProc - 4x DLInferer (detection) - PostProc - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H265_2MP 0) ! $(INFER_OD 0) ! queue ! mosaic. \
                                    $(INFER_OD 1) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 1) ! $(INFER_OD 2) ! queue ! mosaic. \
                                    $(INFER_OD 3) ! queue ! mosaic. \
              $(MOSAIC 4) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################
MIMO_TEST_CASE_0015()
{
  echo "" >> $LOG_FILE

  NAME="MIMO_TEST_CASE_0015"
  TITLE="2x video 2MP @30fps - H.265 Decode - MSC - PreProc - 4x DLInferer (se) - PostProc - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H265_2MP 0) ! $(INFER_SS 0) ! queue ! mosaic. \
                                    $(INFER_SS 1) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 1) ! $(INFER_SS 2) ! queue ! mosaic. \
                                    $(INFER_SS 3) ! queue ! mosaic. \
              $(MOSAIC 4) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################
MIMO_TEST_CASE_0016()
{
  echo "" >> $LOG_FILE

  NAME="MIMO_TEST_CASE_0016"
  TITLE="2x video 2MP @30fps - H.264 Decode - MSC - PreProc - 4x DLInferer (classification) - PostProc (2MP) - H.264 Encode (IPP | High | 2MP @ 30fps | 10Mbps)"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H264_2MP 0) ! $(INFER_CL 0) ! queue ! mosaic. \
                                    $(INFER_CL 1) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 1) ! $(INFER_CL 2) ! queue ! mosaic. \
                                    $(INFER_CL 3) ! queue ! mosaic. \
              $(MOSAIC 4) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H264"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################
MIMO_TEST_CASE_0017()
{
  echo "" >> $LOG_FILE

  NAME="MIMO_TEST_CASE_0017"
  TITLE="2x video 2MP @30fps - H.264 Decode - MSC - PreProc - 4x DLInferer (detection) - PostProc (2MP) - H.264 Encode (IPP | High | 2MP @ 30fps | 10Mbps)"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H264_2MP 0) ! $(INFER_OD 0) ! queue ! mosaic. \
                                    $(INFER_OD 1) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 1) ! $(INFER_OD 2) ! queue ! mosaic. \
                                    $(INFER_OD 3) ! queue ! mosaic. \
              $(MOSAIC 4) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H264"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################
MIMO_TEST_CASE_0018()
{
  echo "" >> $LOG_FILE

  NAME="MIMO_TEST_CASE_0018"
  TITLE="2x video 2MP @30fps - H.264 Decode - MSC - PreProc - 4x DLInferer (segmentation) - PostProc (2MP) - H.264 Encode (IPP | High | 2MP @ 30fps | 10Mbps)"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H264_2MP 0) ! $(INFER_SS 0) ! queue ! mosaic. \
                                    $(INFER_SS 1) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 1) ! $(INFER_SS 2) ! queue ! mosaic. \
                                    $(INFER_SS 3) ! queue ! mosaic. \
              $(MOSAIC 4) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H264"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################

MIMO_TEST_CASE_0019()
{
  echo "" >> $LOG_FILE

  NAME="MIMO_TEST_CASE_0019"
  TITLE="2x video 2MP @30fps - H.265 Decode - MSC - PreProc - 4x DLInferer (classification) - PostProc (2MP) - H.265 Encode (IPP | High | 2MP @ 30fps | 10Mbps)"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H265_2MP 0) ! $(INFER_CL 0) ! queue ! mosaic. \
                                    $(INFER_CL 1) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 1) ! $(INFER_CL 2) ! queue ! mosaic. \
                                    $(INFER_CL 3) ! queue ! mosaic. \
              $(MOSAIC 4) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H265"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################

MIMO_TEST_CASE_0020()
{
  echo "" >> $LOG_FILE

  NAME="MIMO_TEST_CASE_0020"
  TITLE="2x video 2MP @30fps - H.265 Decode - MSC - PreProc - 4x DLInferer (detection) - PostProc (2MP) - H.265 Encode (IPP | High | 2MP @ 30fps | 10Mbps)"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H265_2MP 0) ! $(INFER_OD 0) ! queue ! mosaic. \
                                    $(INFER_OD 1) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 1) ! $(INFER_OD 2) ! queue ! mosaic. \
                                    $(INFER_OD 3) ! queue ! mosaic. \
              $(MOSAIC 4) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H265"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################

MIMO_TEST_CASE_0021()
{
  echo "" >> $LOG_FILE

  NAME="MIMO_TEST_CASE_0021"
  TITLE="2x video 2MP @30fps - H.265 Decode - MSC - PreProc - 4x DLInferer (segmentation) - PostProc (2MP) - H.265 Encode (IPP | High | 2MP @ 30fps | 10Mbps)"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H265_2MP 0) ! $(INFER_SS 0) ! queue ! mosaic. \
                                    $(INFER_SS 1) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 1) ! $(INFER_SS 2) ! queue ! mosaic. \
                                    $(INFER_SS 3) ! queue ! mosaic. \
              $(MOSAIC 4) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H265"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################
############################## MIMO 4CH TEST CASES #############################
################################################################################
MIMO_4CH_TEST_CASE_0001()
{
  echo "" >> $LOG_FILE

  NAME="MIMO_4CH_TEST_CASE_0001"
  TITLE="4x IMX390 2MP @30fps - ISP - MSC - PreProc - 4x DLInferer (classification) - PostProc - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX390 0) ! $(INFER_CL 0) ! queue ! mosaic. \
              $(IMX390 1) ! $(INFER_CL 2) ! queue ! mosaic. \
              $(IMX390 2) ! $(INFER_CL 4) ! queue ! mosaic. \
              $(IMX390 3) ! $(INFER_CL 6) ! queue ! mosaic. \
              $(MOSAIC 4) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################
MIMO_4CH_TEST_CASE_0002()
{
  echo "" >> $LOG_FILE

  NAME="MIMO_4CH_TEST_CASE_0002"
  TITLE="4x IMX390 2MP @30fps - ISP - MSC - PreProc - 4x DLInferer (classification) - PostProc (2MP) - H.264 Encode (IPP | High | 2MP @ 30fps | 10Mbps)"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX390 0) ! $(INFER_CL 0) ! queue ! mosaic. \
              $(IMX390 1) ! $(INFER_CL 2) ! queue ! mosaic. \
              $(IMX390 2) ! $(INFER_CL 4) ! queue ! mosaic. \
              $(IMX390 3) ! $(INFER_CL 6) ! queue ! mosaic. \
              $(MOSAIC 4) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H264"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################
MIMO_4CH_TEST_CASE_0003()
{
  echo "" >> $LOG_FILE

  NAME="MIMO_4CH_TEST_CASE_0003"
  TITLE="4x IMX390 2MP @30fps - ISP - MSC - PreProc - 4x DLInferer (classification) - PostProc (2MP) - H.265 Encode (IPP | High | 2MP @ 30fps | 10Mbps)"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX390 0) ! $(INFER_CL 0) ! queue ! mosaic. \
              $(IMX390 1) ! $(INFER_CL 2) ! queue ! mosaic. \
              $(IMX390 2) ! $(INFER_CL 4) ! queue ! mosaic. \
              $(IMX390 3) ! $(INFER_CL 6) ! queue ! mosaic. \
              $(MOSAIC 4) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H265"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################

################################################################################
MIMO_4CH_TEST_CASE_0004()
{
  echo "" >> $LOG_FILE

  NAME="MIMO_4CH_TEST_CASE_0004"
  TITLE="4x video 2MP @30fps - H.264 Decode - MSC - PreProc - 4x DLInferer (classification) - PostProc - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H264_2MP 0) ! $(INFER_CL 0) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 1) ! $(INFER_CL 2) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 2) ! $(INFER_CL 4) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 3) ! $(INFER_CL 6) ! queue ! mosaic. \
              $(MOSAIC 4) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################

################################################################################
MIMO_4CH_TEST_CASE_0005()
{
  echo "" >> $LOG_FILE

  NAME="MIMO_4CH_TEST_CASE_0005"
  TITLE="4x video 2MP @30fps - H.265 Decode - MSC - PreProc - 4x DLInferer (classification) - PostProc - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H265_2MP 0) ! $(INFER_CL 0) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 1) ! $(INFER_CL 2) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 2) ! $(INFER_CL 4) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 3) ! $(INFER_CL 6) ! queue ! mosaic. \
              $(MOSAIC 4) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################

################################################################################
MIMO_4CH_TEST_CASE_0006()
{
  echo "" >> $LOG_FILE

  NAME="MIMO_4CH_TEST_CASE_0006"
  TITLE="4x video 2MP @30fps - H.264 Decode - MSC - PreProc - 4x DLInferer (classification) - PostProc (2MP) - H.264 Encode (IPP | High | 2MP @ 30fps | 10Mbps)"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H264_2MP 0) ! $(INFER_CL 0) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 1) ! $(INFER_CL 2) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 2) ! $(INFER_CL 4) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 3) ! $(INFER_CL 6) ! queue ! mosaic. \
              $(MOSAIC 4) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H264"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}
################################################################################

################################################################################
MIMO_4CH_TEST_CASE_0007()
{
  echo "" >> $LOG_FILE

  NAME="MIMO_4CH_TEST_CASE_0007"
  TITLE="4x video 2MP @30fps - H.265 Decode - MSC - PreProc - 4x DLInferer (classification) - PostProc (2MP) - H.265 Encode (IPP | High | 2MP @ 30fps | 10Mbps)"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H265_2MP 0) ! $(INFER_CL 0) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 1) ! $(INFER_CL 2) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 2) ! $(INFER_CL 4) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 3) ! $(INFER_CL 6) ! queue ! mosaic. \
              $(MOSAIC 4) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H265"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}
################################################################################
############################## MIMO 6CH TEST CASES #############################
################################################################################
MIMO_6CH_TEST_CASE_0001()
{
  echo "" >> $LOG_FILE

  NAME="MIMO_6CH_TEST_CASE_0001"
  TITLE="6x IMX390 2MP @30fps - ISP - MSC - PreProc - 6x DLInferer (classification) - PostProc - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX390 0) ! $(INFER_CL 0 0) ! queue ! mosaic. \
              $(IMX390 1) ! $(INFER_CL 2 0) ! queue ! mosaic. \
              $(IMX390 2) ! $(INFER_CL 4 0) ! queue ! mosaic. \
              $(IMX390 3) ! $(INFER_CL 6 0) ! queue ! mosaic. \
              $(IMX390 4) ! $(INFER_CL 8 1) ! queue ! mosaic. \
              $(IMX390 5) ! $(INFER_CL 10 1) ! queue ! mosaic. \
              $(MOSAIC 6) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################

MIMO_6CH_TEST_CASE_0002()
{
  echo "" >> $LOG_FILE

  NAME="MIMO_6CH_TEST_CASE_0002"
  TITLE="6x IMX390 2MP @30fps - ISP - MSC - PreProc - 6x DLInferer (classification) - PostProc (2MP) - H.264 Encode (IPP | High | 2MP @ 30fps | 10Mbps)"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX390 0) ! $(INFER_CL 0 0) ! queue ! mosaic. \
              $(IMX390 1) ! $(INFER_CL 2 0) ! queue ! mosaic. \
              $(IMX390 2) ! $(INFER_CL 4 0) ! queue ! mosaic. \
              $(IMX390 3) ! $(INFER_CL 6 0) ! queue ! mosaic. \
              $(IMX390 4) ! $(INFER_CL 8 1) ! queue ! mosaic. \
              $(IMX390 5) ! $(INFER_CL 10 1) ! queue ! mosaic. \
              $(MOSAIC 6) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H264"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################

MIMO_6CH_TEST_CASE_0003()
{
  echo "" >> $LOG_FILE

  NAME="MIMO_6CH_TEST_CASE_0003"
  TITLE="6x IMX390 2MP @30fps - ISP - MSC - PreProc - 6x DLInferer (classification) - PostProc (2MP) - H.265 Encode (IPP | High | 2MP @ 30fps | 10Mbps)"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX390 0) ! $(INFER_CL 0 0) ! queue ! mosaic. \
              $(IMX390 1) ! $(INFER_CL 2 0) ! queue ! mosaic. \
              $(IMX390 2) ! $(INFER_CL 4 0) ! queue ! mosaic. \
              $(IMX390 3) ! $(INFER_CL 6 0) ! queue ! mosaic. \
              $(IMX390 4) ! $(INFER_CL 8 1) ! queue ! mosaic. \
              $(IMX390 5) ! $(INFER_CL 10 1) ! queue ! mosaic. \
              $(MOSAIC 6) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H265"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################

MIMO_6CH_TEST_CASE_0004()
{
  echo "" >> $LOG_FILE

  NAME="MIMO_6CH_TEST_CASE_0004"
  TITLE="6x video 2MP @30fps - H.264 Decode - MSC - PreProc - 6x DLInferer (classification) - PostProc - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H264_2MP 0) ! $(INFER_CL 0 0) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 1) ! $(INFER_CL 2 0) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 2) ! $(INFER_CL 4 0) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 3) ! $(INFER_CL 6 0) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 4) ! $(INFER_CL 8 1) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 5) ! $(INFER_CL 10 1) ! queue ! mosaic. \
              $(MOSAIC 6) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################

MIMO_6CH_TEST_CASE_0005()
{
  echo "" >> $LOG_FILE

  NAME="MIMO_6CH_TEST_CASE_0005"
  TITLE="6x video 2MP @30fps - H.265 Decode - MSC - PreProc - 6x DLInferer (classification) - PostProc - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H265_2MP 0) ! $(INFER_CL 0 0) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 1) ! $(INFER_CL 2 0) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 2) ! $(INFER_CL 4 0) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 3) ! $(INFER_CL 6 0) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 4) ! $(INFER_CL 8 1) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 5) ! $(INFER_CL 10 1) ! queue ! mosaic. \
              $(MOSAIC 6) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################

MIMO_6CH_TEST_CASE_0006()
{
  echo "" >> $LOG_FILE

  NAME="MIMO_6CH_TEST_CASE_0006"
  TITLE="6x video 2MP @30fps - H.264 Decode - MSC - PreProc - 6x DLInferer (classification) - PostProc (2MP) - H.264 Encode (IPP | High | 2MP @ 30fps | 10Mbps)"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H264_2MP 0) ! $(INFER_CL 0 0) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 1) ! $(INFER_CL 2 0) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 2) ! $(INFER_CL 4 0) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 3) ! $(INFER_CL 6 0) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 4) ! $(INFER_CL 8 1) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 5) ! $(INFER_CL 10 1) ! queue ! mosaic. \
              $(MOSAIC 6) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H264"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################

################################################################################

MIMO_6CH_TEST_CASE_0007()
{
  echo "" >> $LOG_FILE

  NAME="MIMO_6CH_TEST_CASE_0007"
  TITLE="6x video 2MP @30fps - H.265 Decode - MSC - PreProc - 6x DLInferer (classification) - PostProc (2MP) - H.265 Encode (IPP | High | 2MP @ 30fps | 10Mbps)"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H265_2MP 0) ! $(INFER_CL 0 0) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 1) ! $(INFER_CL 2 0) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 2) ! $(INFER_CL 4 0) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 3) ! $(INFER_CL 6 0) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 4) ! $(INFER_CL 8 1) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 5) ! $(INFER_CL 10 1) ! queue ! mosaic. \
              $(MOSAIC 6) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H265"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################
############################## MIMO 8CH TEST CASES #############################
################################################################################
MIMO_8CH_TEST_CASE_0001()
{
  echo "" >> $LOG_FILE

  NAME="MIMO_8CH_TEST_CASE_0001"
  TITLE="8x IMX390 2MP @30fps - ISP - MSC - PreProc - 8x DLInferer (classification) - PostProc - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX390 0) ! $(INFER_CL 0 0) ! queue ! mosaic. \
              $(IMX390 1) ! $(INFER_CL 2 0) ! queue ! mosaic. \
              $(IMX390 2) ! $(INFER_CL 4 0) ! queue ! mosaic. \
              $(IMX390 3) ! $(INFER_CL 6 0) ! queue ! mosaic. \
              $(IMX390 4) ! $(INFER_CL 8 0) ! queue ! mosaic. \
              $(IMX390 5) ! $(INFER_CL 10 1) ! queue ! mosaic. \
              $(IMX390 6) ! $(INFER_CL 12 1) ! queue ! mosaic. \
              $(IMX390 7) ! $(INFER_CL 14 1) ! queue ! mosaic. \
              $(MOSAIC 8) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################

MIMO_8CH_TEST_CASE_0002()
{
  echo "" >> $LOG_FILE

  NAME="MIMO_8CH_TEST_CASE_0002"
  TITLE="8x IMX390 2MP @30fps - ISP - MSC - PreProc - 8x DLInferer (classification) - PostProc (2MP) - H.264 Encode (IPP | High | 2MP @ 30fps | 10Mbps)"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX390 0) ! $(INFER_CL 0 0) ! queue ! mosaic. \
              $(IMX390 1) ! $(INFER_CL 2 0) ! queue ! mosaic. \
              $(IMX390 2) ! $(INFER_CL 4 0) ! queue ! mosaic. \
              $(IMX390 3) ! $(INFER_CL 6 0) ! queue ! mosaic. \
              $(IMX390 4) ! $(INFER_CL 8 0) ! queue ! mosaic. \
              $(IMX390 5) ! $(INFER_CL 10 1) ! queue ! mosaic. \
              $(IMX390 6) ! $(INFER_CL 12 1) ! queue ! mosaic. \
              $(IMX390 7) ! $(INFER_CL 14 1) ! queue ! mosaic. \
              $(MOSAIC 8) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H264"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################

MIMO_8CH_TEST_CASE_0003()
{
  echo "" >> $LOG_FILE

  NAME="MIMO_8CH_TEST_CASE_0003"
  TITLE="8x IMX390 2MP @30fps - ISP - MSC - PreProc - 8x DLInferer (classification) - PostProc (2MP) - H.265 Encode (IPP | High | 2MP @ 30fps | 10Mbps)"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX390 0) ! $(INFER_CL 0 0) ! queue ! mosaic. \
              $(IMX390 1) ! $(INFER_CL 2 0) ! queue ! mosaic. \
              $(IMX390 2) ! $(INFER_CL 4 0) ! queue ! mosaic. \
              $(IMX390 3) ! $(INFER_CL 6 0) ! queue ! mosaic. \
              $(IMX390 4) ! $(INFER_CL 8 0) ! queue ! mosaic. \
              $(IMX390 5) ! $(INFER_CL 10 1) ! queue ! mosaic. \
              $(IMX390 6) ! $(INFER_CL 12 1) ! queue ! mosaic. \
              $(IMX390 7) ! $(INFER_CL 14 1) ! queue ! mosaic. \
              $(MOSAIC 8) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H265"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################

MIMO_8CH_TEST_CASE_0004()
{
  echo "" >> $LOG_FILE

  NAME="MIMO_8CH_TEST_CASE_0004"
  TITLE="8x video 2MP @30fps - H.264 Decode - MSC - PreProc - 8x DLInferer (classification) - PostProc - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H264_2MP 0) ! $(INFER_CL 0 0) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 1) ! $(INFER_CL 2 0) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 2) ! $(INFER_CL 4 0) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 3) ! $(INFER_CL 6 0) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 4) ! $(INFER_CL 8 1) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 5) ! $(INFER_CL 10 1) ! queue ! mosaic. \
              $(MOSAIC 6) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################

MIMO_8CH_TEST_CASE_0005()
{
  echo "" >> $LOG_FILE

  NAME="MIMO_8CH_TEST_CASE_0005"
  TITLE="8x video 2MP @30fps - H.265 Decode - MSC - PreProc - 8x DLInferer (classification) - PostProc - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H265_2MP 0) ! $(INFER_CL 0 0) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 1) ! $(INFER_CL 2 0) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 2) ! $(INFER_CL 4 0) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 3) ! $(INFER_CL 6 0) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 4) ! $(INFER_CL 8 1) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 5) ! $(INFER_CL 10 1) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 6) ! $(INFER_CL 12 1) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 7) ! $(INFER_CL 14 1) ! queue ! mosaic. \
              $(MOSAIC 8) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################

MIMO_8CH_TEST_CASE_0006()
{
  echo "" >> $LOG_FILE

  NAME="MIMO_8CH_TEST_CASE_0006"
  TITLE="8x video 2MP @30fps - H.264 Decode - MSC - PreProc - 8x DLInferer (classification) - PostProc (2MP) - H.264 Encode (IPP | High | 2MP @ 30fps | 10Mbps)"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H264_2MP 0) ! $(INFER_CL 0 0) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 1) ! $(INFER_CL 2 0) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 2) ! $(INFER_CL 4 0) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 3) ! $(INFER_CL 6 0) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 4) ! $(INFER_CL 8 1) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 5) ! $(INFER_CL 10 1) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 6) ! $(INFER_CL 12 1) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 7) ! $(INFER_CL 14 1) ! queue ! mosaic. \
              $(MOSAIC 8) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H264"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################

################################################################################

MIMO_8CH_TEST_CASE_0007()
{
  echo "" >> $LOG_FILE

  NAME="MIMO_8CH_TEST_CASE_0007"
  TITLE="8x video 2MP @30fps - H.265 Decode - MSC - PreProc - 6x DLInferer (classification) - PostProc (2MP) - H.265 Encode (IPP | High | 2MP @ 30fps | 10Mbps)"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H265_2MP 0) ! $(INFER_CL 0 0) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 1) ! $(INFER_CL 2 0) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 2) ! $(INFER_CL 4 0) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 3) ! $(INFER_CL 6 0) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 4) ! $(INFER_CL 8 0) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 5) ! $(INFER_CL 10 1) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 6) ! $(INFER_CL 12 1) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 7) ! $(INFER_CL 14 1) ! queue ! mosaic. \
              $(MOSAIC 8) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H265"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

###############################################################################

############### IMX390 2CH ###########################

IMX390_2CH_TEST_CASE_0001()
{
  echo "" >> $LOG_FILE

  NAME="IMX390_2CH_TEST_CASE_0001"
  TITLE="2x IMX390 2MP @30fps - ISP - MSC - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX390 0) ! tiovxmultiscaler target=0 ! video/x-raw,width=640,height=360 ! queue ! mosaic. \
              $(IMX390 1) ! tiovxmultiscaler target=1 ! video/x-raw,width=640,height=360 ! queue ! mosaic. \
              $(MOSAIC 2) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

IMX390_2CH_TEST_CASE_0002()
{
  echo "" >> $LOG_FILE

  NAME="IMX390_2CH_TEST_CASE_0002"
  TITLE="2x IMX390 2MP @30fps - ISP - MSC - PreProc - 2x DLInferer (detection) - PostProc - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX390 0) ! $(INFER_OD 0) ! queue ! mosaic. \
              $(IMX390 1) ! $(INFER_OD 2 1) ! queue ! mosaic. \
              $(MOSAIC 2) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

IMX390_2CH_TEST_CASE_0003()
{
  echo "" >> $LOG_FILE

  NAME="IMX390_2CH_TEST_CASE_0003"
  TITLE="2x IMX390 2MP @30fps - ISP - H.264 Encode"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX390 0) ! $ENCODE_H264 \
              $(IMX390 1) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H264"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

IMX390_2CH_TEST_CASE_0004()
{
  echo "" >> $LOG_FILE

  NAME="IMX390_2CH_TEST_CASE_0004"
  TITLE="2x IMX390 2MP @30fps - ISP - H.265 Encode"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX390 0) ! $ENCODE_H265 \
              $(IMX390 1) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H265"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

IMX390_2CH_TEST_CASE_0005()
{
  echo "" >> $LOG_FILE

  NAME="IMX390_2CH_TEST_CASE_0005"
  TITLE="2x IMX390 2MP @30fps - ISP - MSC - PreProc - 2x DLInferer (detection) - PostProc - H.264 Encode"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX390 0) ! $(INFER_OD 0) ! $ENCODE_H264 \
              $(IMX390 1) ! $(INFER_OD 2 1) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H264"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

IMX390_2CH_TEST_CASE_0006()
{
  echo "" >> $LOG_FILE

  NAME="IMX390_2CH_TEST_CASE_0006"
  TITLE="2x IMX390 2MP @30fps - ISP - MSC - PreProc - 2x DLInferer (detection) - PostProc - H.265 Encode"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX390 0) ! $(INFER_OD 0) ! $ENCODE_H265 \
              $(IMX390 1) ! $(INFER_OD 2 1) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H265"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

############### IMX390 4CH ###########################

IMX390_4CH_TEST_CASE_0001()
{
  echo "" >> $LOG_FILE

  NAME="IMX390_4CH_TEST_CASE_0001"
  TITLE="4x IMX390 2MP @30fps - ISP - MSC - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX390 0) ! tiovxmultiscaler target=0 ! video/x-raw,width=640,height=360 ! queue ! mosaic. \
              $(IMX390 1) ! tiovxmultiscaler target=0 ! video/x-raw,width=640,height=360 ! queue ! mosaic. \
              $(IMX390 2) ! tiovxmultiscaler target=1 ! video/x-raw,width=640,height=360 ! queue ! mosaic. \
              $(IMX390 3) ! tiovxmultiscaler target=1 ! video/x-raw,width=640,height=360 ! queue ! mosaic. \
              $(MOSAIC 4) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

IMX390_4CH_TEST_CASE_0002()
{
  echo "" >> $LOG_FILE

  NAME="IMX390_4CH_TEST_CASE_0002"
  TITLE="4x IMX390 2MP @30fps - ISP - MSC - PreProc - 4x DLInferer (detection) - PostProc - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX390 0) ! $(INFER_OD 0) ! queue ! mosaic. \
              $(IMX390 1) ! $(INFER_OD 2) ! queue ! mosaic. \
              $(IMX390 2) ! $(INFER_OD 4 1) ! queue ! mosaic. \
              $(IMX390 3) ! $(INFER_OD 6 1) ! queue ! mosaic. \
              $(MOSAIC 4) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

IMX390_4CH_TEST_CASE_0003()
{
  echo "" >> $LOG_FILE

  NAME="IMX390_4CH_TEST_CASE_0003"
  TITLE="4x IMX390 2MP @30fps - ISP - H.264 Encode"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX390 0) ! $ENCODE_H264 \
              $(IMX390 1) ! $ENCODE_H264 \
              $(IMX390 2) ! $ENCODE_H264 \
              $(IMX390 3) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H264"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

IMX390_4CH_TEST_CASE_0004()
{
  echo "" >> $LOG_FILE

  NAME="IMX390_4CH_TEST_CASE_0004"
  TITLE="4x IMX390 2MP @30fps - ISP - H.265 Encode"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX390 0) ! $ENCODE_H265 \
              $(IMX390 1) ! $ENCODE_H265 \
              $(IMX390 2) ! $ENCODE_H265 \
              $(IMX390 3) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H265"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

IMX390_4CH_TEST_CASE_0005()
{
  echo "" >> $LOG_FILE

  NAME="IMX390_4CH_TEST_CASE_0005"
  TITLE="4x IMX390 2MP @30fps - ISP - MSC - PreProc - 4x DLInferer (detection) - PostProc - H.264 Encode"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX390 0) ! $(INFER_OD 0) ! $ENCODE_H264 \
              $(IMX390 1) ! $(INFER_OD 2) ! $ENCODE_H264 \
              $(IMX390 2) ! $(INFER_OD 4 1) ! $ENCODE_H264 \
              $(IMX390 3) ! $(INFER_OD 6 1) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H264"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

IMX390_4CH_TEST_CASE_0006()
{
  echo "" >> $LOG_FILE

  NAME="IMX390_4CH_TEST_CASE_0006"
  TITLE="4x IMX390 2MP @30fps - ISP - MSC - PreProc - 4x DLInferer (detection) - PostProc - H.265 Encode"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX390 0) ! $(INFER_OD 0) ! $ENCODE_H265 \
              $(IMX390 1) ! $(INFER_OD 2) ! $ENCODE_H265 \
              $(IMX390 2) ! $(INFER_OD 4 1) ! $ENCODE_H265 \
              $(IMX390 3) ! $(INFER_OD 6 1) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H265"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

############### IMX390 6CH ###########################

IMX390_6CH_TEST_CASE_0001()
{
  echo "" >> $LOG_FILE

  NAME="IMX390_6CH_TEST_CASE_0001"
  TITLE="6x IMX390 2MP @30fps - ISP - MSC - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX390 0) ! tiovxmultiscaler target=0 ! video/x-raw,width=640,height=360 ! queue ! mosaic. \
              $(IMX390 1) ! tiovxmultiscaler target=0 ! video/x-raw,width=640,height=360 ! queue ! mosaic. \
              $(IMX390 2) ! tiovxmultiscaler target=0 ! video/x-raw,width=640,height=360 ! queue ! mosaic. \
              $(IMX390 3) ! tiovxmultiscaler target=1 ! video/x-raw,width=640,height=360 ! queue ! mosaic. \
              $(IMX390 4) ! tiovxmultiscaler target=1 ! video/x-raw,width=640,height=360 ! queue ! mosaic. \
              $(IMX390 5) ! tiovxmultiscaler target=1 ! video/x-raw,width=640,height=360 ! queue ! mosaic. \
              $(MOSAIC 8) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

IMX390_6CH_TEST_CASE_0002()
{
  echo "" >> $LOG_FILE

  NAME="IMX390_6CH_TEST_CASE_0002"
  TITLE="6x IMX390 2MP @30fps - ISP - MSC - PreProc - 6x DLInferer (detection) - PostProc - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX390 0) ! $(INFER_OD 0) ! queue ! mosaic. \
              $(IMX390 1) ! $(INFER_OD 2) ! queue ! mosaic. \
              $(IMX390 2) ! $(INFER_OD 4) ! queue ! mosaic. \
              $(IMX390 3) ! $(INFER_OD 6 1) ! queue ! mosaic. \
              $(IMX390 4) ! $(INFER_OD 8 1) ! queue ! mosaic. \
              $(IMX390 5) ! $(INFER_OD 10 1) ! queue ! mosaic. \
              $(MOSAIC 6) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

IMX390_6CH_TEST_CASE_0003()
{
  echo "" >> $LOG_FILE

  NAME="IMX390_6CH_TEST_CASE_0003"
  TITLE="6x IMX390 2MP @30fps - ISP - H.264 Encode"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX390 0) ! $ENCODE_H264 \
              $(IMX390 1) ! $ENCODE_H264 \
              $(IMX390 2) ! $ENCODE_H264 \
              $(IMX390 3) ! $ENCODE_H264 \
              $(IMX390 4) ! $ENCODE_H264 \
              $(IMX390 5) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H264"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

IMX390_6CH_TEST_CASE_0004()
{
  echo "" >> $LOG_FILE

  NAME="IMX390_6CH_TEST_CASE_0004"
  TITLE="6x IMX390 2MP @30fps - ISP - H.265 Encode"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX390 0) ! $ENCODE_H265 \
              $(IMX390 1) ! $ENCODE_H265 \
              $(IMX390 2) ! $ENCODE_H265 \
              $(IMX390 3) ! $ENCODE_H265 \
              $(IMX390 4) ! $ENCODE_H265 \
              $(IMX390 5) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H265"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

IMX390_6CH_TEST_CASE_0005()
{
  echo "" >> $LOG_FILE

  NAME="IMX390_6CH_TEST_CASE_0005"
  TITLE="6x IMX390 2MP @30fps - ISP - MSC - PreProc - 6x DLInferer (detection) - PostProc - H.264 Encode"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX390 0) ! $(INFER_OD 0) ! $ENCODE_H264 \
              $(IMX390 1) ! $(INFER_OD 2) !  $ENCODE_H264 \
              $(IMX390 2) ! $(INFER_OD 4) !  $ENCODE_H264 \
              $(IMX390 3) ! $(INFER_OD 6 1) !  $ENCODE_H264 \
              $(IMX390 4) ! $(INFER_OD 8 1) !  $ENCODE_H264 \
              $(IMX390 5) ! $(INFER_OD 10 1) !  $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H264"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

IMX390_6CH_TEST_CASE_0006()
{
  echo "" >> $LOG_FILE

  NAME="IMX390_6CH_TEST_CASE_0006"
  TITLE="6x IMX390 2MP @30fps - ISP - MSC - PreProc - 6x DLInferer (detection) - PostProc - H.265 Encode"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX390 0) ! $(INFER_OD 0) ! $ENCODE_H265 \
              $(IMX390 1) ! $(INFER_OD 2) ! $ENCODE_H265 \
              $(IMX390 2) ! $(INFER_OD 4) ! $ENCODE_H265 \
              $(IMX390 3) ! $(INFER_OD 6 1) ! $ENCODE_H265 \
              $(IMX390 4) ! $(INFER_OD 8 1) ! $ENCODE_H265 \
              $(IMX390 5) ! $(INFER_OD 10 1) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H265"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

############### IMX390 8CH ###########################

IMX390_8CH_TEST_CASE_0001()
{
  echo "" >> $LOG_FILE

  NAME="IMX390_8CH_TEST_CASE_0001"
  TITLE="8x IMX390 2MP @30fps - ISP - MSC - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX390 0) ! tiovxmultiscaler target=0 ! video/x-raw,width=640,height=360 ! queue ! mosaic. \
              $(IMX390 1) ! tiovxmultiscaler target=0 ! video/x-raw,width=640,height=360 ! queue ! mosaic. \
              $(IMX390 2) ! tiovxmultiscaler target=0 ! video/x-raw,width=640,height=360 ! queue ! mosaic. \
              $(IMX390 3) ! tiovxmultiscaler target=0 ! video/x-raw,width=640,height=360 ! queue ! mosaic. \
              $(IMX390 4) ! tiovxmultiscaler target=1 ! video/x-raw,width=640,height=360 ! queue ! mosaic. \
              $(IMX390 5) ! tiovxmultiscaler target=1 ! video/x-raw,width=640,height=360 ! queue ! mosaic. \
              $(IMX390 6) ! tiovxmultiscaler target=1 ! video/x-raw,width=640,height=360 ! queue ! mosaic. \
              $(IMX390 7) ! tiovxmultiscaler target=1 ! video/x-raw,width=640,height=360 ! queue ! mosaic. \
              $(MOSAIC 8) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

IMX390_8CH_TEST_CASE_0002()
{
  echo "" >> $LOG_FILE

  NAME="IMX390_8CH_TEST_CASE_0002"
  TITLE="8x IMX390 2MP @30fps - ISP - MSC - PreProc - 8x DLInferer (detection) - PostProc - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX390 0) ! $(INFER_OD 0) ! queue ! mosaic. \
              $(IMX390 1) ! $(INFER_OD 2) ! queue ! mosaic. \
              $(IMX390 2) ! $(INFER_OD 4) ! queue ! mosaic. \
              $(IMX390 3) ! $(INFER_OD 6) ! queue ! mosaic. \
              $(IMX390 4) ! $(INFER_OD 8 1) ! queue ! mosaic. \
              $(IMX390 5) ! $(INFER_OD 10 1) ! queue ! mosaic. \
              $(IMX390 6) ! $(INFER_OD 12 1) ! queue ! mosaic. \
              $(IMX390 7) ! $(INFER_OD 14 1) ! queue ! mosaic. \
              $(MOSAIC 8) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

IMX390_8CH_TEST_CASE_0003()
{
  echo "" >> $LOG_FILE

  NAME="IMX390_8CH_TEST_CASE_0003"
  TITLE="8x IMX390 2MP @30fps - ISP - H.264 Encode"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX390 0) ! $ENCODE_H264 \
              $(IMX390 1) ! $ENCODE_H264 \
              $(IMX390 2) ! $ENCODE_H264 \
              $(IMX390 3) ! $ENCODE_H264 \
              $(IMX390 4) ! $ENCODE_H264 \
              $(IMX390 5) ! $ENCODE_H264 \
              $(IMX390 6) ! $ENCODE_H264 \
              $(IMX390 7) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H264"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

IMX390_8CH_TEST_CASE_0004()
{
  echo "" >> $LOG_FILE

  NAME="IMX390_8CH_TEST_CASE_0004"
  TITLE="8x IMX390 2MP @30fps - ISP - H.265 Encode"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX390 0) ! $ENCODE_H265 \
              $(IMX390 1) ! $ENCODE_H265 \
              $(IMX390 2) ! $ENCODE_H265 \
              $(IMX390 3) ! $ENCODE_H265 \
              $(IMX390 4) ! $ENCODE_H265 \
              $(IMX390 5) ! $ENCODE_H265 \
              $(IMX390 6) ! $ENCODE_H265 \
              $(IMX390 7) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H265"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

IMX390_8CH_TEST_CASE_0005()
{
  echo "" >> $LOG_FILE

  NAME="IMX390_8CH_TEST_CASE_0005"
  TITLE="8x IMX390 2MP @30fps - ISP - MSC - PreProc - 8x DLInferer (detection) - PostProc - H.264 Encode"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX390 0) ! $(INFER_OD 0) ! $ENCODE_H264 \
              $(IMX390 1) ! $(INFER_OD 2) !  $ENCODE_H264 \
              $(IMX390 2) ! $(INFER_OD 4) !  $ENCODE_H264 \
              $(IMX390 3) ! $(INFER_OD 6) !  $ENCODE_H264 \
              $(IMX390 4) ! $(INFER_OD 8 1) !  $ENCODE_H264 \
              $(IMX390 5) ! $(INFER_OD 10 1) !  $ENCODE_H264 \
              $(IMX390 6) ! $(INFER_OD 12 1) !  $ENCODE_H264 \
              $(IMX390 7) ! $(INFER_OD 14 1) !  $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H264"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

IMX390_8CH_TEST_CASE_0006()
{
  echo "" >> $LOG_FILE

  NAME="IMX390_8CH_TEST_CASE_0006"
  TITLE="8x IMX390 2MP @30fps - ISP - MSC - PreProc - 8x DLInferer (detection) - PostProc - H.265 Encode"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX390 0) ! $(INFER_OD 0) ! $ENCODE_H265 \
              $(IMX390 1) ! $(INFER_OD 2) ! $ENCODE_H265 \
              $(IMX390 2) ! $(INFER_OD 4) ! $ENCODE_H265 \
              $(IMX390 3) ! $(INFER_OD 6) ! $ENCODE_H265 \
              $(IMX390 4) ! $(INFER_OD 8 1) ! $ENCODE_H265 \
              $(IMX390 5) ! $(INFER_OD 10 1) ! $ENCODE_H265 \
              $(IMX390 6) ! $(INFER_OD 12 1) ! $ENCODE_H265 \
              $(IMX390 7) ! $(INFER_OD 14 1) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H265"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

############### IMX390 12CH ###########################

IMX390_12CH_TEST_CASE_0001()
{
  echo "" >> $LOG_FILE

  NAME="IMX390_12CH_TEST_CASE_0001"
  TITLE="12x IMX390 2MP @30fps - ISP - MSC - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX390 0) ! tiovxmultiscaler target=0 ! video/x-raw,width=480,height=270 ! queue ! mosaic. \
              $(IMX390 1) ! tiovxmultiscaler target=0 ! video/x-raw,width=480,height=270 ! queue ! mosaic. \
              $(IMX390 2) ! tiovxmultiscaler target=0 ! video/x-raw,width=480,height=270 ! queue ! mosaic. \
              $(IMX390 3) ! tiovxmultiscaler target=0 ! video/x-raw,width=480,height=270 ! queue ! mosaic. \
              $(IMX390 4) ! tiovxmultiscaler target=0 ! video/x-raw,width=480,height=270 ! queue ! mosaic. \
              $(IMX390 5) ! tiovxmultiscaler target=0 ! video/x-raw,width=480,height=270 ! queue ! mosaic. \
              $(IMX390 6) ! tiovxmultiscaler target=1 ! video/x-raw,width=480,height=270 ! queue ! mosaic. \
              $(IMX390 7) ! tiovxmultiscaler target=1 ! video/x-raw,width=480,height=270 ! queue ! mosaic. \
              $(IMX390 8) ! tiovxmultiscaler target=1 ! video/x-raw,width=480,height=270 ! queue ! mosaic. \
              $(IMX390 9) ! tiovxmultiscaler target=1 ! video/x-raw,width=480,height=270 ! queue ! mosaic. \
              $(IMX390 10) ! tiovxmultiscaler target=1 ! video/x-raw,width=480,height=270 ! queue ! mosaic. \
              $(IMX390 11) ! tiovxmultiscaler target=1 ! video/x-raw,width=480,height=270 ! queue ! mosaic. \
              $(MOSAIC 12) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

IMX390_12CH_TEST_CASE_0002()
{
  echo "" >> $LOG_FILE

  NAME="IMX390_12CH_TEST_CASE_0002"
  TITLE="12x IMX390 2MP @30fps - ISP - MSC - PreProc - 12x DLInferer (detection) - PostProc - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX390 0) ! $(INFER_OD 0) ! queue ! mosaic. \
              $(IMX390 1) ! $(INFER_OD 2) ! queue ! mosaic. \
              $(IMX390 2) ! $(INFER_OD 4) ! queue ! mosaic. \
              $(IMX390 3) ! $(INFER_OD 6) ! queue ! mosaic. \
              $(IMX390 4) ! $(INFER_OD 8 1) ! queue ! mosaic. \
              $(IMX390 5) ! $(INFER_OD 10 1) ! queue ! mosaic. \
              $(IMX390 6) ! $(INFER_OD 12 1) ! queue ! mosaic. \
              $(IMX390 7) ! $(INFER_OD 14 1) ! queue ! mosaic. \
              $(IMX390 8) ! $(INFER_OD 16 1) ! queue ! mosaic. \
              $(IMX390 9) ! $(INFER_OD 18 1) ! queue ! mosaic. \
              $(IMX390 10) ! $(INFER_OD 20 1) ! queue ! mosaic. \
              $(IMX390 11) ! $(INFER_OD 22 1) ! queue ! mosaic. \
              $(MOSAIC 12) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

IMX390_12CH_TEST_CASE_0003()
{
  echo "" >> $LOG_FILE

  NAME="IMX390_12CH_TEST_CASE_0003"
  TITLE="12x IMX390 2MP @30fps - ISP - H.264 Encode"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX390 0) ! $ENCODE_H264 \
              $(IMX390 1) ! $ENCODE_H264 \
              $(IMX390 2) ! $ENCODE_H264 \
              $(IMX390 3) ! $ENCODE_H264 \
              $(IMX390 4) ! $ENCODE_H264 \
              $(IMX390 5) ! $ENCODE_H264 \
              $(IMX390 6) ! $ENCODE_H264 \
              $(IMX390 7) ! $ENCODE_H264 \
              $(IMX390 8) ! $ENCODE_H264 \
              $(IMX390 9) ! $ENCODE_H264 \
              $(IMX390 10) ! $ENCODE_H264 \
              $(IMX390 11) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H264"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

IMX390_12CH_TEST_CASE_0004()
{
  echo "" >> $LOG_FILE

  NAME="IMX390_12CH_TEST_CASE_0004"
  TITLE="12x IMX390 2MP @30fps - ISP - H.265 Encode"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX390 0) ! $ENCODE_H265 \
              $(IMX390 1) ! $ENCODE_H265 \
              $(IMX390 2) ! $ENCODE_H265 \
              $(IMX390 3) ! $ENCODE_H265 \
              $(IMX390 4) ! $ENCODE_H265 \
              $(IMX390 5) ! $ENCODE_H265 \
              $(IMX390 6) ! $ENCODE_H265 \
              $(IMX390 7) ! $ENCODE_H265 \
              $(IMX390 8) ! $ENCODE_H265 \
              $(IMX390 9) ! $ENCODE_H265 \
              $(IMX390 10) ! $ENCODE_H265 \
              $(IMX390 11) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H265"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

IMX390_12CH_TEST_CASE_0005()
{
  echo "" >> $LOG_FILE

  NAME="IMX390_12CH_TEST_CASE_0005"
  TITLE="12x IMX390 2MP @30fps - ISP - MSC - PreProc - 12x DLInferer (detection) - PostProc - H.264 Encode"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX390 0) ! $(INFER_OD 0) ! $ENCODE_H264 \
              $(IMX390 1) ! $(INFER_OD 2) !  $ENCODE_H264 \
              $(IMX390 2) ! $(INFER_OD 4) !  $ENCODE_H264 \
              $(IMX390 3) ! $(INFER_OD 6) !  $ENCODE_H264 \
              $(IMX390 4) ! $(INFER_OD 8) !  $ENCODE_H264 \
              $(IMX390 5) ! $(INFER_OD 10) !  $ENCODE_H264 \
              $(IMX390 6) ! $(INFER_OD 12 1) !  $ENCODE_H264 \
              $(IMX390 7) ! $(INFER_OD 14 1) !  $ENCODE_H264 \
              $(IMX390 8) ! $(INFER_OD 16 1) !  $ENCODE_H264 \
              $(IMX390 9) ! $(INFER_OD 18 1) !  $ENCODE_H264 \
              $(IMX390 10) ! $(INFER_OD 20 1) !  $ENCODE_H264 \
              $(IMX390 11) ! $(INFER_OD 22 1) !  $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H264"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

IMX390_12CH_TEST_CASE_0006()
{
  echo "" >> $LOG_FILE

  NAME="IMX390_12CH_TEST_CASE_0006"
  TITLE="12x IMX390 2MP @30fps - ISP - MSC - PreProc - 12x DLInferer (detection) - PostProc - H.265 Encode"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(IMX390 0) ! $(INFER_OD 0) ! $ENCODE_H265 \
              $(IMX390 1) ! $(INFER_OD 2) ! $ENCODE_H265 \
              $(IMX390 2) ! $(INFER_OD 4) ! $ENCODE_H265 \
              $(IMX390 3) ! $(INFER_OD 6) ! $ENCODE_H265 \
              $(IMX390 4) ! $(INFER_OD 8) ! $ENCODE_H265 \
              $(IMX390 5) ! $(INFER_OD 10) ! $ENCODE_H265 \
              $(IMX390 6) ! $(INFER_OD 12 1) ! $ENCODE_H265 \
              $(IMX390 7) ! $(INFER_OD 14 1) ! $ENCODE_H265 \
              $(IMX390 8) ! $(INFER_OD 16 1) ! $ENCODE_H265 \
              $(IMX390 9) ! $(INFER_OD 18 1) ! $ENCODE_H265 \
              $(IMX390 10) ! $(INFER_OD 20 1) ! $ENCODE_H265 \
              $(IMX390 11) ! $(INFER_OD 22 1) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H265"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

################################################################################

########################## VIDEO 2CH ######################################

VIDEO_2CH_TEST_CASE_0001()
{
  echo "" >> $LOG_FILE

  NAME="VIDEO_2CH_TEST_CASE_0001"
  TITLE="2x video 2MP @30fps - H.264 Decode - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H264_2MP 0) ! tiovxmultiscaler target=0 ! video/x-raw,width=640,height=360 ! queue ! mosaic. \
              $(VIDEO_H264_2MP 1) ! tiovxmultiscaler target=1 ! video/x-raw,width=640,height=360 ! queue ! mosaic. \
              $(MOSAIC 2) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

VIDEO_2CH_TEST_CASE_0002()
{
  echo "" >> $LOG_FILE

  NAME="VIDEO_2CH_TEST_CASE_0002"
  TITLE="2x video 2MP @30fps - H.265 Decode - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H265_2MP 0) ! tiovxmultiscaler target=0 ! video/x-raw,width=640,height=360 ! queue ! mosaic. \
              $(VIDEO_H265_2MP 1) ! tiovxmultiscaler target=1 ! video/x-raw,width=640,height=360 ! queue ! mosaic. \
              $(MOSAIC 2) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

VIDEO_2CH_TEST_CASE_0003()
{
  echo "" >> $LOG_FILE

  NAME="VIDEO_2CH_TEST_CASE_0003"
  TITLE="2x video 2MP @30fps - H.264 Decode - PreProc - 2x DLInferer (detection) - PostProc - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H264_2MP 0) ! $(INFER_OD 0) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 1) ! $(INFER_OD 2 1) ! queue ! mosaic. \
              $(MOSAIC 2) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

VIDEO_2CH_TEST_CASE_0004()
{
  echo "" >> $LOG_FILE

  NAME="VIDEO_2CH_TEST_CASE_0004"
  TITLE="2x video 2MP @30fps - H.265 Decode - PreProc - 2x DLInferer (detection) - PostProc - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H265_2MP 0) ! $(INFER_OD 0) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 1) ! $(INFER_OD 2 1) ! queue ! mosaic. \
              $(MOSAIC 2) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}


VIDEO_2CH_TEST_CASE_0005()
{
  echo "" >> $LOG_FILE

  NAME="VIDEO_2CH_TEST_CASE_0005"
  TITLE="2x video 2MP @30fps - H.264 Decode - H.264 Encode"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H264_2MP 0) ! $ENCODE_H264 \
              $(VIDEO_H264_2MP 1) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H264"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

VIDEO_2CH_TEST_CASE_0006()
{
  echo "" >> $LOG_FILE

  NAME="VIDEO_2CH_TEST_CASE_0006"
  TITLE="2x video 2MP @30fps - H.265 Decode - H.265 Encode"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H265_2MP 0) ! $ENCODE_H265 \
              $(VIDEO_H265_2MP 1) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H265"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

VIDEO_2CH_TEST_CASE_0007()
{
  echo "" >> $LOG_FILE

  NAME="VIDEO_2CH_TEST_CASE_0007"
  TITLE="2x video 2MP @30fps - H.264 Decode - PreProc - 2x DLInferer (detection) - PostProc - H.264 Encode"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H264_2MP 0) ! $(INFER_OD 0) ! $ENCODE_H264 \
              $(VIDEO_H264_2MP 1) ! $(INFER_OD 2 1) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H264"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

VIDEO_2CH_TEST_CASE_0008()
{
  echo "" >> $LOG_FILE

  NAME="VIDEO_2CH_TEST_CASE_0008"
  TITLE="2x video 2MP @30fps - H.264 Decode - PreProc - 2x DLInferer (detection) - PostProc - H.265 Encode"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H264_2MP 0) ! $(INFER_OD 0) ! $ENCODE_H265 \
              $(VIDEO_H264_2MP 1) ! $(INFER_OD 2 1) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H265"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

VIDEO_2CH_TEST_CASE_0009()
{
  echo "" >> $LOG_FILE

  NAME="VIDEO_2CH_TEST_CASE_0009"
  TITLE="2x video 2MP @30fps - H.265 Decode - PreProc - 2x DLInferer (detection) - PostProc - H.264 Encode"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H265_2MP 0) ! $(INFER_OD 0) ! $ENCODE_H264 \
              $(VIDEO_H265_2MP 1) ! $(INFER_OD 2 1) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H264"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

VIDEO_2CH_TEST_CASE_00010()
{
  echo "" >> $LOG_FILE

  NAME="VIDEO_2CH_TEST_CASE_00010"
  TITLE="2x video 2MP @30fps - H.265 Decode - PreProc - 2x DLInferer (detection) - PostProc - H.265 Encode"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H265_2MP 0) ! $(INFER_OD 0) ! $ENCODE_H265 \
              $(VIDEO_H265_2MP 1) ! $(INFER_OD 2 1) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H265"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

########################## VIDEO 4CH ######################################

VIDEO_4CH_TEST_CASE_0001()
{
  echo "" >> $LOG_FILE

  NAME="VIDEO_4CH_TEST_CASE_0001"
  TITLE="4x video 2MP @30fps - H.264 Decode - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H264_2MP 0) ! tiovxmultiscaler target=0 ! video/x-raw,width=640,height=360 ! queue ! mosaic. \
              $(VIDEO_H264_2MP 1) ! tiovxmultiscaler target=0 ! video/x-raw,width=640,height=360 ! queue ! mosaic. \
              $(VIDEO_H264_2MP 2) ! tiovxmultiscaler target=1 ! video/x-raw,width=640,height=360 ! queue ! mosaic. \
              $(VIDEO_H264_2MP 3) ! tiovxmultiscaler target=1 ! video/x-raw,width=640,height=360 ! queue ! mosaic. \
              $(MOSAIC 4) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

VIDEO_4CH_TEST_CASE_0002()
{
  echo "" >> $LOG_FILE

  NAME="VIDEO_4CH_TEST_CASE_0002"
  TITLE="4x video 2MP @30fps - H.265 Decode - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H265_2MP 0) ! tiovxmultiscaler target=0 ! video/x-raw,width=640,height=360 ! queue ! mosaic. \
              $(VIDEO_H265_2MP 1) ! tiovxmultiscaler target=0 ! video/x-raw,width=640,height=360 ! queue ! mosaic. \
              $(VIDEO_H265_2MP 2) ! tiovxmultiscaler target=1 ! video/x-raw,width=640,height=360 ! queue ! mosaic. \
              $(VIDEO_H265_2MP 3) ! tiovxmultiscaler target=1 ! video/x-raw,width=640,height=360 ! queue ! mosaic. \
              $(MOSAIC 4) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

VIDEO_4CH_TEST_CASE_0003()
{
  echo "" >> $LOG_FILE

  NAME="VIDEO_4CH_TEST_CASE_0003"
  TITLE="4x video 2MP @30fps - H.264 Decode - PreProc - 4x DLInferer (detection) - PostProc - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H264_2MP 0) ! $(INFER_OD 0) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 1) ! $(INFER_OD 2) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 2) ! $(INFER_OD 4 1) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 3) ! $(INFER_OD 6 1) ! queue ! mosaic. \
              $(MOSAIC 4) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

VIDEO_4CH_TEST_CASE_0004()
{
  echo "" >> $LOG_FILE

  NAME="VIDEO_4CH_TEST_CASE_0004"
  TITLE="4x video 2MP @30fps - H.265 Decode - PreProc - 4x DLInferer (detection) - PostProc - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H265_2MP 0) ! $(INFER_OD 0) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 1) ! $(INFER_OD 2) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 2) ! $(INFER_OD 4 1) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 3) ! $(INFER_OD 6 1) ! queue ! mosaic. \
              $(MOSAIC 4) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}


VIDEO_4CH_TEST_CASE_0005()
{
  echo "" >> $LOG_FILE

  NAME="VIDEO_4CH_TEST_CASE_0005"
  TITLE="4x video 2MP @30fps - H.264 Decode - H.264 Encode"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H264_2MP 0) ! $ENCODE_H264 \
              $(VIDEO_H264_2MP 1) ! $ENCODE_H264 \
              $(VIDEO_H264_2MP 2) ! $ENCODE_H264 \
              $(VIDEO_H264_2MP 3) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H264"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

VIDEO_4CH_TEST_CASE_0006()
{
  echo "" >> $LOG_FILE

  NAME="VIDEO_4CH_TEST_CASE_0006"
  TITLE="4x video 2MP @30fps - H.265 Decode - H.265 Encode"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H265_2MP 0) ! $ENCODE_H265 \
              $(VIDEO_H265_2MP 1) ! $ENCODE_H265 \
              $(VIDEO_H265_2MP 2) ! $ENCODE_H265 \
              $(VIDEO_H265_2MP 3) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H265"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

VIDEO_4CH_TEST_CASE_0007()
{
  echo "" >> $LOG_FILE

  NAME="VIDEO_4CH_TEST_CASE_0007"
  TITLE="4x video 2MP @30fps - H.264 Decode - PreProc - 4x DLInferer (detection) - PostProc - H.264 Encode"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H264_2MP 0) ! $(INFER_OD 0) ! $ENCODE_H264 \
              $(VIDEO_H264_2MP 1) ! $(INFER_OD 2) ! $ENCODE_H264 \
              $(VIDEO_H264_2MP 2) ! $(INFER_OD 4 1) ! $ENCODE_H264 \
              $(VIDEO_H264_2MP 3) ! $(INFER_OD 6 1) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H264"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

VIDEO_4CH_TEST_CASE_0008()
{
  echo "" >> $LOG_FILE

  NAME="VIDEO_4CH_TEST_CASE_0008"
  TITLE="4x video 2MP @30fps - H.264 Decode - PreProc - 4x DLInferer (detection) - PostProc - H.265 Encode"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H264_2MP 0) ! $(INFER_OD 0) ! $ENCODE_H265 \
              $(VIDEO_H264_2MP 1) ! $(INFER_OD 2) ! $ENCODE_H265 \
              $(VIDEO_H264_2MP 2) ! $(INFER_OD 4 1) ! $ENCODE_H265 \
              $(VIDEO_H264_2MP 3) ! $(INFER_OD 6 1) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H265"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

VIDEO_4CH_TEST_CASE_0009()
{
  echo "" >> $LOG_FILE

  NAME="VIDEO_4CH_TEST_CASE_0009"
  TITLE="4x video 2MP @30fps - H.265 Decode - PreProc - 4x DLInferer (detection) - PostProc - H.264 Encode"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H265_2MP 0) ! $(INFER_OD 0) ! $ENCODE_H264 \
              $(VIDEO_H265_2MP 1) ! $(INFER_OD 2) ! $ENCODE_H264 \
              $(VIDEO_H265_2MP 2) ! $(INFER_OD 4 1) ! $ENCODE_H264 \
              $(VIDEO_H265_2MP 3) ! $(INFER_OD 6 1) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H264"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

VIDEO_4CH_TEST_CASE_00010()
{
  echo "" >> $LOG_FILE

  NAME="VIDEO_4CH_TEST_CASE_00010"
  TITLE="4x video 2MP @30fps - H.265 Decode - PreProc - 4x DLInferer (detection) - PostProc - H.265 Encode"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H265_2MP 0) ! $(INFER_OD 0) ! $ENCODE_H265 \
              $(VIDEO_H265_2MP 1) ! $(INFER_OD 2) ! $ENCODE_H265 \
              $(VIDEO_H265_2MP 2) ! $(INFER_OD 4 1) ! $ENCODE_H265 \
              $(VIDEO_H265_2MP 3) ! $(INFER_OD 6 1) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H265"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

########################## VIDEO 6CH ######################################

VIDEO_6CH_TEST_CASE_0001()
{
  echo "" >> $LOG_FILE

  NAME="VIDEO_6CH_TEST_CASE_0001"
  TITLE="6x video 2MP @30fps - H.264 Decode - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H264_2MP 0) ! tiovxmultiscaler target=0 ! video/x-raw,width=640,height=360 ! queue ! mosaic. \
              $(VIDEO_H264_2MP 1) ! tiovxmultiscaler target=0 ! video/x-raw,width=640,height=360 ! queue ! mosaic. \
              $(VIDEO_H264_2MP 2) ! tiovxmultiscaler target=0 ! video/x-raw,width=640,height=360 ! queue ! mosaic. \
              $(VIDEO_H264_2MP 3) ! tiovxmultiscaler target=1 ! video/x-raw,width=640,height=360 ! queue ! mosaic. \
              $(VIDEO_H264_2MP 4) ! tiovxmultiscaler target=1 ! video/x-raw,width=640,height=360 ! queue ! mosaic. \
              $(VIDEO_H264_2MP 5) ! tiovxmultiscaler target=1 ! video/x-raw,width=640,height=360 ! queue ! mosaic. \
              $(MOSAIC 6) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

VIDEO_6CH_TEST_CASE_0002()
{
  echo "" >> $LOG_FILE

  NAME="VIDEO_6CH_TEST_CASE_0002"
  TITLE="6x video 2MP @30fps - H.265 Decode - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H265_2MP 0) ! tiovxmultiscaler target=0 ! video/x-raw,width=640,height=360 ! queue ! mosaic. \
              $(VIDEO_H265_2MP 1) ! tiovxmultiscaler target=0 ! video/x-raw,width=640,height=360 ! queue ! mosaic. \
              $(VIDEO_H265_2MP 2) ! tiovxmultiscaler target=0 ! video/x-raw,width=640,height=360 ! queue ! mosaic. \
              $(VIDEO_H265_2MP 3) ! tiovxmultiscaler target=1 ! video/x-raw,width=640,height=360 ! queue ! mosaic. \
              $(VIDEO_H265_2MP 4) ! tiovxmultiscaler target=1 ! video/x-raw,width=640,height=360 ! queue ! mosaic. \
              $(VIDEO_H265_2MP 5) ! tiovxmultiscaler target=1 ! video/x-raw,width=640,height=360 ! queue ! mosaic. \
              $(MOSAIC 6) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

VIDEO_6CH_TEST_CASE_0003()
{
  echo "" >> $LOG_FILE

  NAME="VIDEO_6CH_TEST_CASE_0003"
  TITLE="6x video 2MP @30fps - H.264 Decode - PreProc - 6x DLInferer (detection) - PostProc - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H264_2MP 0) ! $(INFER_OD 0) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 1) ! $(INFER_OD 2) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 2) ! $(INFER_OD 4) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 3) ! $(INFER_OD 6 1) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 4) ! $(INFER_OD 8 1) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 5) ! $(INFER_OD 10 1) ! queue ! mosaic. \
              $(MOSAIC 6) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

VIDEO_6CH_TEST_CASE_0004()
{
  echo "" >> $LOG_FILE

  NAME="VIDEO_6CH_TEST_CASE_0004"
  TITLE="6x video 2MP @30fps - H.265 Decode - PreProc - 6x DLInferer (detection) - PostProc - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H265_2MP 0) ! $(INFER_OD 0) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 1) ! $(INFER_OD 2) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 2) ! $(INFER_OD 4) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 3) ! $(INFER_OD 6 1) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 4) ! $(INFER_OD 8 1) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 5) ! $(INFER_OD 10 1) ! queue ! mosaic. \
              $(MOSAIC 6) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}


VIDEO_6CH_TEST_CASE_0005()
{
  echo "" >> $LOG_FILE

  NAME="VIDEO_6CH_TEST_CASE_0005"
  TITLE="6x video 2MP @30fps - H.264 Decode - H.264 Encode"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H264_2MP 0) ! $ENCODE_H264 \
              $(VIDEO_H264_2MP 1) ! $ENCODE_H264 \
              $(VIDEO_H264_2MP 2) ! $ENCODE_H264 \
              $(VIDEO_H264_2MP 3) ! $ENCODE_H264 \
              $(VIDEO_H264_2MP 4) ! $ENCODE_H264 \
              $(VIDEO_H264_2MP 5) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H264"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

VIDEO_6CH_TEST_CASE_0006()
{
  echo "" >> $LOG_FILE

  NAME="VIDEO_6CH_TEST_CASE_0006"
  TITLE="6x video 2MP @30fps - H.265 Decode - H.265 Encode"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H265_2MP 0) ! $ENCODE_H265 \
              $(VIDEO_H265_2MP 1) ! $ENCODE_H265 \
              $(VIDEO_H265_2MP 2) ! $ENCODE_H265 \
              $(VIDEO_H265_2MP 3) ! $ENCODE_H265 \
              $(VIDEO_H265_2MP 4) ! $ENCODE_H265 \
              $(VIDEO_H265_2MP 5) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H265"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

VIDEO_6CH_TEST_CASE_0007()
{
  echo "" >> $LOG_FILE

  NAME="VIDEO_6CH_TEST_CASE_0007"
  TITLE="6x video 2MP @30fps - H.264 Decode - PreProc - 6x DLInferer (detection) - PostProc - H.264 Encode"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H264_2MP 0) ! $(INFER_OD 0) ! $ENCODE_H264 \
              $(VIDEO_H264_2MP 1) ! $(INFER_OD 2) ! $ENCODE_H264 \
              $(VIDEO_H264_2MP 2) ! $(INFER_OD 4) ! $ENCODE_H264 \
              $(VIDEO_H264_2MP 3) ! $(INFER_OD 6 1) ! $ENCODE_H264 \
              $(VIDEO_H264_2MP 4) ! $(INFER_OD 8 1) ! $ENCODE_H264 \
              $(VIDEO_H264_2MP 5) ! $(INFER_OD 10 1) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H264"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

VIDEO_6CH_TEST_CASE_0008()
{
  echo "" >> $LOG_FILE

  NAME="VIDEO_6CH_TEST_CASE_0008"
  TITLE="6x video 2MP @30fps - H.264 Decode - PreProc - 6x DLInferer (detection) - PostProc - H.265 Encode"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H264_2MP 0) ! $(INFER_OD 0) ! $ENCODE_H265 \
              $(VIDEO_H264_2MP 1) ! $(INFER_OD 2) ! $ENCODE_H265 \
              $(VIDEO_H264_2MP 2) ! $(INFER_OD 4) ! $ENCODE_H265 \
              $(VIDEO_H264_2MP 3) ! $(INFER_OD 6 1) ! $ENCODE_H265 \
              $(VIDEO_H264_2MP 4) ! $(INFER_OD 8 1) ! $ENCODE_H265 \
              $(VIDEO_H264_2MP 5) ! $(INFER_OD 10 1) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H265"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

VIDEO_6CH_TEST_CASE_0009()
{
  echo "" >> $LOG_FILE

  NAME="VIDEO_6CH_TEST_CASE_0009"
  TITLE="6x video 2MP @30fps - H.265 Decode - PreProc - 6x DLInferer (detection) - PostProc - H.264 Encode"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H265_2MP 0) ! $(INFER_OD 0) ! $ENCODE_H264 \
              $(VIDEO_H265_2MP 1) ! $(INFER_OD 2) ! $ENCODE_H264 \
              $(VIDEO_H265_2MP 2) ! $(INFER_OD 4) ! $ENCODE_H264 \
              $(VIDEO_H265_2MP 3) ! $(INFER_OD 6 1) ! $ENCODE_H264 \
              $(VIDEO_H265_2MP 4) ! $(INFER_OD 8 1) ! $ENCODE_H264 \
              $(VIDEO_H265_2MP 5) ! $(INFER_OD 10 1) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H264"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

VIDEO_6CH_TEST_CASE_00010()
{
  echo "" >> $LOG_FILE

  NAME="VIDEO_6CH_TEST_CASE_00010"
  TITLE="6x video 2MP @30fps - H.265 Decode - PreProc - 6x DLInferer (detection) - PostProc - H.265 Encode"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H265_2MP 0) ! $(INFER_OD 0) ! $ENCODE_H265 \
              $(VIDEO_H265_2MP 1) ! $(INFER_OD 2) ! $ENCODE_H265 \
              $(VIDEO_H265_2MP 2) ! $(INFER_OD 4) ! $ENCODE_H265 \
              $(VIDEO_H265_2MP 3) ! $(INFER_OD 6 1) ! $ENCODE_H265 \
              $(VIDEO_H265_2MP 4) ! $(INFER_OD 8 1) ! $ENCODE_H265 \
              $(VIDEO_H265_2MP 5) ! $(INFER_OD 10 1) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H265"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

########################## VIDEO 8CH ######################################

VIDEO_8CH_TEST_CASE_0001()
{
  echo "" >> $LOG_FILE

  NAME="VIDEO_8CH_TEST_CASE_0001"
  TITLE="8x video 2MP @30fps - H.264 Decode - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H264_2MP 0) ! tiovxmultiscaler target=0 ! video/x-raw,width=640,height=360 ! queue ! mosaic. \
              $(VIDEO_H264_2MP 1) ! tiovxmultiscaler target=0 ! video/x-raw,width=640,height=360 ! queue ! mosaic. \
              $(VIDEO_H264_2MP 2) ! tiovxmultiscaler target=0 ! video/x-raw,width=640,height=360 ! queue ! mosaic. \
              $(VIDEO_H264_2MP 3) ! tiovxmultiscaler target=0 ! video/x-raw,width=640,height=360 ! queue ! mosaic. \
              $(VIDEO_H264_2MP 4) ! tiovxmultiscaler target=1 ! video/x-raw,width=640,height=360 ! queue ! mosaic. \
              $(VIDEO_H264_2MP 5) ! tiovxmultiscaler target=1 ! video/x-raw,width=640,height=360 ! queue ! mosaic. \
              $(VIDEO_H264_2MP 6) ! tiovxmultiscaler target=1 ! video/x-raw,width=640,height=360 ! queue ! mosaic. \
              $(VIDEO_H264_2MP 7) ! tiovxmultiscaler target=1 ! video/x-raw,width=640,height=360 ! queue ! mosaic. \
              $(MOSAIC 8) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

VIDEO_8CH_TEST_CASE_0002()
{
  echo "" >> $LOG_FILE

  NAME="VIDEO_8CH_TEST_CASE_0002"
  TITLE="8x video 2MP @30fps - H.265 Decode - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H265_2MP 0) ! tiovxmultiscaler target=0 ! video/x-raw,width=640,height=360 ! queue ! mosaic. \
              $(VIDEO_H265_2MP 1) ! tiovxmultiscaler target=0 ! video/x-raw,width=640,height=360 ! queue ! mosaic. \
              $(VIDEO_H265_2MP 2) ! tiovxmultiscaler target=0 ! video/x-raw,width=640,height=360 ! queue ! mosaic. \
              $(VIDEO_H265_2MP 3) ! tiovxmultiscaler target=0 ! video/x-raw,width=640,height=360 ! queue ! mosaic. \
              $(VIDEO_H265_2MP 4) ! tiovxmultiscaler target=1 ! video/x-raw,width=640,height=360 ! queue ! mosaic. \
              $(VIDEO_H265_2MP 5) ! tiovxmultiscaler target=1 ! video/x-raw,width=640,height=360 ! queue ! mosaic. \
              $(VIDEO_H265_2MP 6) ! tiovxmultiscaler target=1 ! video/x-raw,width=640,height=360 ! queue ! mosaic. \
              $(VIDEO_H265_2MP 7) ! tiovxmultiscaler target=1 ! video/x-raw,width=640,height=360 ! queue ! mosaic. \
              $(MOSAIC 8) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

VIDEO_8CH_TEST_CASE_0003()
{
  echo "" >> $LOG_FILE

  NAME="VIDEO_8CH_TEST_CASE_0003"
  TITLE="8x video 2MP @30fps - H.264 Decode - PreProc - 8x DLInferer (detection) - PostProc - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H264_2MP 0) ! $(INFER_OD 0) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 1) ! $(INFER_OD 2) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 2) ! $(INFER_OD 4) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 3) ! $(INFER_OD 6) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 4) ! $(INFER_OD 8 1) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 5) ! $(INFER_OD 10 1) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 6) ! $(INFER_OD 12 1) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 7) ! $(INFER_OD 14 1) ! queue ! mosaic. \
              $(MOSAIC 8) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

VIDEO_8CH_TEST_CASE_0004()
{
  echo "" >> $LOG_FILE

  NAME="VIDEO_8CH_TEST_CASE_0004"
  TITLE="8x video 2MP @30fps - H.265 Decode - PreProc - 8x DLInferer (detection) - PostProc - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H265_2MP 0) ! $(INFER_OD 0) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 1) ! $(INFER_OD 2) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 2) ! $(INFER_OD 4) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 3) ! $(INFER_OD 6) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 4) ! $(INFER_OD 8 1) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 5) ! $(INFER_OD 10 1) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 6) ! $(INFER_OD 12 1) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 7) ! $(INFER_OD 14 1) ! queue ! mosaic. \
              $(MOSAIC 8) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}


VIDEO_8CH_TEST_CASE_0005()
{
  echo "" >> $LOG_FILE

  NAME="VIDEO_8CH_TEST_CASE_0005"
  TITLE="8x video 2MP @30fps - H.264 Decode - H.264 Encode"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H264_2MP 0) ! $ENCODE_H264 \
              $(VIDEO_H264_2MP 1) ! $ENCODE_H264 \
              $(VIDEO_H264_2MP 2) ! $ENCODE_H264 \
              $(VIDEO_H264_2MP 3) ! $ENCODE_H264 \
              $(VIDEO_H264_2MP 4) ! $ENCODE_H264 \
              $(VIDEO_H264_2MP 5) ! $ENCODE_H264 \
              $(VIDEO_H264_2MP 6) ! $ENCODE_H264 \
              $(VIDEO_H264_2MP 7) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H264"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

VIDEO_8CH_TEST_CASE_0006()
{
  echo "" >> $LOG_FILE

  NAME="VIDEO_8CH_TEST_CASE_0006"
  TITLE="8x video 2MP @30fps - H.265 Decode - H.265 Encode"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H265_2MP 0) ! $ENCODE_H265 \
              $(VIDEO_H265_2MP 1) ! $ENCODE_H265 \
              $(VIDEO_H265_2MP 2) ! $ENCODE_H265 \
              $(VIDEO_H265_2MP 3) ! $ENCODE_H265 \
              $(VIDEO_H265_2MP 4) ! $ENCODE_H265 \
              $(VIDEO_H265_2MP 5) ! $ENCODE_H265 \
              $(VIDEO_H265_2MP 6) ! $ENCODE_H265 \
              $(VIDEO_H265_2MP 7) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H265"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

VIDEO_8CH_TEST_CASE_0007()
{
  echo "" >> $LOG_FILE

  NAME="VIDEO_8CH_TEST_CASE_0007"
  TITLE="8x video 2MP @30fps - H.264 Decode - PreProc - 8x DLInferer (detection) - PostProc - H.264 Encode"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H264_2MP 0) ! $(INFER_OD 0) ! $ENCODE_H264 \
              $(VIDEO_H264_2MP 1) ! $(INFER_OD 2) ! $ENCODE_H264 \
              $(VIDEO_H264_2MP 2) ! $(INFER_OD 4) ! $ENCODE_H264 \
              $(VIDEO_H264_2MP 3) ! $(INFER_OD 6) ! $ENCODE_H264 \
              $(VIDEO_H264_2MP 4) ! $(INFER_OD 8 1) ! $ENCODE_H264 \
              $(VIDEO_H264_2MP 5) ! $(INFER_OD 10 1) ! $ENCODE_H264 \
              $(VIDEO_H264_2MP 6) ! $(INFER_OD 12 1) ! $ENCODE_H264 \
              $(VIDEO_H264_2MP 7) ! $(INFER_OD 14 1) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H264"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

VIDEO_8CH_TEST_CASE_0008()
{
  echo "" >> $LOG_FILE

  NAME="VIDEO_8CH_TEST_CASE_0008"
  TITLE="8x video 2MP @30fps - H.264 Decode - PreProc - 8x DLInferer (detection) - PostProc - H.265 Encode"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H264_2MP 0) ! $(INFER_OD 0) ! $ENCODE_H265 \
              $(VIDEO_H264_2MP 1) ! $(INFER_OD 2) ! $ENCODE_H265 \
              $(VIDEO_H264_2MP 2) ! $(INFER_OD 4) ! $ENCODE_H265 \
              $(VIDEO_H264_2MP 3) ! $(INFER_OD 6) ! $ENCODE_H265 \
              $(VIDEO_H264_2MP 4) ! $(INFER_OD 8 1) ! $ENCODE_H265 \
              $(VIDEO_H264_2MP 5) ! $(INFER_OD 10 1) ! $ENCODE_H265 \
              $(VIDEO_H264_2MP 6) ! $(INFER_OD 12 1) ! $ENCODE_H265 \
              $(VIDEO_H264_2MP 7) ! $(INFER_OD 14 1) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H265"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

VIDEO_8CH_TEST_CASE_0009()
{
  echo "" >> $LOG_FILE

  NAME="VIDEO_8CH_TEST_CASE_0009"
  TITLE="8x video 2MP @30fps - H.265 Decode - PreProc - 8x DLInferer (detection) - PostProc - H.264 Encode"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H265_2MP 0) ! $(INFER_OD 0) ! $ENCODE_H264 \
              $(VIDEO_H265_2MP 1) ! $(INFER_OD 2) ! $ENCODE_H264 \
              $(VIDEO_H265_2MP 2) ! $(INFER_OD 4) ! $ENCODE_H264 \
              $(VIDEO_H265_2MP 3) ! $(INFER_OD 6) ! $ENCODE_H264 \
              $(VIDEO_H265_2MP 4) ! $(INFER_OD 8 1) ! $ENCODE_H264 \
              $(VIDEO_H265_2MP 5) ! $(INFER_OD 10 1) ! $ENCODE_H264 \
              $(VIDEO_H265_2MP 6) ! $(INFER_OD 12 1) ! $ENCODE_H264 \
              $(VIDEO_H265_2MP 7) ! $(INFER_OD 14 1) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H264"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

VIDEO_8CH_TEST_CASE_00010()
{
  echo "" >> $LOG_FILE

  NAME="VIDEO_8CH_TEST_CASE_00010"
  TITLE="8x video 2MP @30fps - H.265 Decode - PreProc - 8x DLInferer (detection) - PostProc - H.265 Encode"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H265_2MP 0) ! $(INFER_OD 0) ! $ENCODE_H265 \
              $(VIDEO_H265_2MP 1) ! $(INFER_OD 2) ! $ENCODE_H265 \
              $(VIDEO_H265_2MP 2) ! $(INFER_OD 4) ! $ENCODE_H265 \
              $(VIDEO_H265_2MP 3) ! $(INFER_OD 6) ! $ENCODE_H265 \
              $(VIDEO_H265_2MP 4) ! $(INFER_OD 8 1) ! $ENCODE_H265 \
              $(VIDEO_H265_2MP 5) ! $(INFER_OD 10 1) ! $ENCODE_H265 \
              $(VIDEO_H265_2MP 6) ! $(INFER_OD 12 1) ! $ENCODE_H265 \
              $(VIDEO_H265_2MP 7) ! $(INFER_OD 14 1) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H265"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}


########################## VIDEO 12CH ######################################

VIDEO_12CH_TEST_CASE_0001()
{
  echo "" >> $LOG_FILE

  NAME="VIDEO_12CH_TEST_CASE_0001"
  TITLE="12x video 2MP @30fps - H.264 Decode - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H264_2MP 0) ! tiovxmultiscaler target=0 ! video/x-raw,width=480,height=270 ! queue ! mosaic. \
              $(VIDEO_H264_2MP 1) ! tiovxmultiscaler target=0 ! video/x-raw,width=480,height=270 ! queue ! mosaic. \
              $(VIDEO_H264_2MP 2) ! tiovxmultiscaler target=0 ! video/x-raw,width=480,height=270 ! queue ! mosaic. \
              $(VIDEO_H264_2MP 3) ! tiovxmultiscaler target=0 ! video/x-raw,width=480,height=270 ! queue ! mosaic. \
              $(VIDEO_H264_2MP 4) ! tiovxmultiscaler target=0 ! video/x-raw,width=480,height=270 ! queue ! mosaic. \
              $(VIDEO_H264_2MP 5) ! tiovxmultiscaler target=0 ! video/x-raw,width=480,height=270 ! queue ! mosaic. \
              $(VIDEO_H264_2MP 6) ! tiovxmultiscaler target=1 ! video/x-raw,width=480,height=270 ! queue ! mosaic. \
              $(VIDEO_H264_2MP 7) ! tiovxmultiscaler target=1 ! video/x-raw,width=480,height=270 ! queue ! mosaic. \
              $(VIDEO_H264_2MP 8) ! tiovxmultiscaler target=1 ! video/x-raw,width=480,height=270 ! queue ! mosaic. \
              $(VIDEO_H264_2MP 9) ! tiovxmultiscaler target=1 ! video/x-raw,width=480,height=270 ! queue ! mosaic. \
              $(VIDEO_H264_2MP 10) ! tiovxmultiscaler target=1 ! video/x-raw,width=480,height=270 ! queue ! mosaic. \
              $(VIDEO_H264_2MP 11) ! tiovxmultiscaler target=1 ! video/x-raw,width=480,height=270 ! queue ! mosaic. \
              $(MOSAIC 12) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

VIDEO_12CH_TEST_CASE_0002()
{
  echo "" >> $LOG_FILE

  NAME="VIDEO_12CH_TEST_CASE_0002"
  TITLE="12x video 2MP @30fps - H.265 Decode - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H265_2MP 0) ! tiovxmultiscaler target=0 ! video/x-raw,width=480,height=270 ! queue ! mosaic. \
              $(VIDEO_H265_2MP 1) ! tiovxmultiscaler target=0 ! video/x-raw,width=480,height=270 ! queue ! mosaic. \
              $(VIDEO_H265_2MP 2) ! tiovxmultiscaler target=0 ! video/x-raw,width=480,height=270 ! queue ! mosaic. \
              $(VIDEO_H265_2MP 3) ! tiovxmultiscaler target=0 ! video/x-raw,width=480,height=270 ! queue ! mosaic. \
              $(VIDEO_H265_2MP 4) ! tiovxmultiscaler target=0 ! video/x-raw,width=480,height=270 ! queue ! mosaic. \
              $(VIDEO_H265_2MP 5) ! tiovxmultiscaler target=0 ! video/x-raw,width=480,height=270 ! queue ! mosaic. \
              $(VIDEO_H265_2MP 6) ! tiovxmultiscaler target=1 ! video/x-raw,width=480,height=270 ! queue ! mosaic. \
              $(VIDEO_H265_2MP 7) ! tiovxmultiscaler target=1 ! video/x-raw,width=480,height=270 ! queue ! mosaic. \
              $(VIDEO_H265_2MP 8) ! tiovxmultiscaler target=1 ! video/x-raw,width=480,height=270 ! queue ! mosaic. \
              $(VIDEO_H265_2MP 9) ! tiovxmultiscaler target=1 ! video/x-raw,width=480,height=270 ! queue ! mosaic. \
              $(VIDEO_H265_2MP 10) ! tiovxmultiscaler target=1 ! video/x-raw,width=480,height=270 ! queue ! mosaic. \
              $(VIDEO_H265_2MP 11) ! tiovxmultiscaler target=1 ! video/x-raw,width=480,height=270 ! queue ! mosaic. \
              $(MOSAIC 12) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

VIDEO_12CH_TEST_CASE_0003()
{
  echo "" >> $LOG_FILE

  NAME="VIDEO_12CH_TEST_CASE_0003"
  TITLE="12x video 2MP @30fps - H.264 Decode - PreProc - 12x DLInferer (detection) - PostProc - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H264_2MP 0) ! $(INFER_OD 0) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 1) ! $(INFER_OD 2) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 2) ! $(INFER_OD 4) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 3) ! $(INFER_OD 6) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 4) ! $(INFER_OD 8) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 5) ! $(INFER_OD 10) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 6) ! $(INFER_OD 12 1) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 7) ! $(INFER_OD 14 1) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 8) ! $(INFER_OD 16 1) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 9) ! $(INFER_OD 18 1) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 10) ! $(INFER_OD 20 1) ! queue ! mosaic. \
              $(VIDEO_H264_2MP 11) ! $(INFER_OD 22 1) ! queue ! mosaic. \
              $(MOSAIC 12) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

VIDEO_12CH_TEST_CASE_0004()
{
  echo "" >> $LOG_FILE

  NAME="VIDEO_12CH_TEST_CASE_0004"
  TITLE="12x video 2MP @30fps - H.265 Decode - PreProc - 12x DLInferer (detection) - PostProc - Mosaic (2MP) - Display"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H265_2MP 0) ! $(INFER_OD 0) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 1) ! $(INFER_OD 2) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 2) ! $(INFER_OD 4) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 3) ! $(INFER_OD 6) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 4) ! $(INFER_OD 8) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 5) ! $(INFER_OD 10) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 6) ! $(INFER_OD 12 1) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 7) ! $(INFER_OD 14 1) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 8) ! $(INFER_OD 16 1) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 9) ! $(INFER_OD 18 1) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 10) ! $(INFER_OD 20 1) ! queue ! mosaic. \
              $(VIDEO_H265_2MP 11) ! $(INFER_OD 22 1) ! queue ! mosaic. \
              $(MOSAIC 12) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $DISPLAY"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}


VIDEO_12CH_TEST_CASE_0005()
{
  echo "" >> $LOG_FILE

  NAME="VIDEO_12CH_TEST_CASE_0005"
  TITLE="12x video 2MP @30fps - H.264 Decode - H.264 Encode"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H264_2MP 0) ! $ENCODE_H264 \
              $(VIDEO_H264_2MP 1) ! $ENCODE_H264 \
              $(VIDEO_H264_2MP 2) ! $ENCODE_H264 \
              $(VIDEO_H264_2MP 3) ! $ENCODE_H264 \
              $(VIDEO_H264_2MP 4) ! $ENCODE_H264 \
              $(VIDEO_H264_2MP 5) ! $ENCODE_H264 \
              $(VIDEO_H264_2MP 6) ! $ENCODE_H264 \
              $(VIDEO_H264_2MP 7) ! $ENCODE_H264 \
              $(VIDEO_H264_2MP 8) ! $ENCODE_H264 \
              $(VIDEO_H264_2MP 9) ! $ENCODE_H264 \
              $(VIDEO_H264_2MP 10) ! $ENCODE_H264 \
              $(VIDEO_H264_2MP 11) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H264"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

VIDEO_12CH_TEST_CASE_0006()
{
  echo "" >> $LOG_FILE

  NAME="VIDEO_12CH_TEST_CASE_0006"
  TITLE="12x video 2MP @30fps - H.265 Decode - H.265 Encode"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H265_2MP 0) ! $ENCODE_H265 \
              $(VIDEO_H265_2MP 1) ! $ENCODE_H265 \
              $(VIDEO_H265_2MP 2) ! $ENCODE_H265 \
              $(VIDEO_H265_2MP 3) ! $ENCODE_H265 \
              $(VIDEO_H265_2MP 4) ! $ENCODE_H265 \
              $(VIDEO_H265_2MP 5) ! $ENCODE_H265 \
              $(VIDEO_H265_2MP 6) ! $ENCODE_H265 \
              $(VIDEO_H265_2MP 7) ! $ENCODE_H265 \
              $(VIDEO_H265_2MP 8) ! $ENCODE_H265 \
              $(VIDEO_H265_2MP 9) ! $ENCODE_H265 \
              $(VIDEO_H265_2MP 10) ! $ENCODE_H265 \
              $(VIDEO_H265_2MP 11) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H265"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

VIDEO_12CH_TEST_CASE_0007()
{
  echo "" >> $LOG_FILE

  NAME="VIDEO_12CH_TEST_CASE_0007"
  TITLE="12x video 2MP @30fps - H.264 Decode - PreProc - 12x DLInferer (detection) - PostProc - H.264 Encode"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H264_2MP 0) ! $(INFER_OD 0) ! $ENCODE_H264 \
              $(VIDEO_H264_2MP 1) ! $(INFER_OD 2) ! $ENCODE_H264 \
              $(VIDEO_H264_2MP 2) ! $(INFER_OD 4) ! $ENCODE_H264 \
              $(VIDEO_H264_2MP 3) ! $(INFER_OD 6) ! $ENCODE_H264 \
              $(VIDEO_H264_2MP 4) ! $(INFER_OD 8) ! $ENCODE_H264 \
              $(VIDEO_H264_2MP 5) ! $(INFER_OD 10) ! $ENCODE_H264 \
              $(VIDEO_H264_2MP 6) ! $(INFER_OD 12 1) ! $ENCODE_H264 \
              $(VIDEO_H264_2MP 7) ! $(INFER_OD 14 1) ! $ENCODE_H264 \
              $(VIDEO_H264_2MP 8) ! $(INFER_OD 16 1) ! $ENCODE_H264 \
              $(VIDEO_H264_2MP 9) ! $(INFER_OD 18 1) ! $ENCODE_H264 \
              $(VIDEO_H264_2MP 10) ! $(INFER_OD 20 1) ! $ENCODE_H264 \
              $(VIDEO_H264_2MP 11) ! $(INFER_OD 22 1) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H264"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

VIDEO_12CH_TEST_CASE_0008()
{
  echo "" >> $LOG_FILE

  NAME="VIDEO_12CH_TEST_CASE_0008"
  TITLE="12x video 2MP @30fps - H.264 Decode - PreProc - 12x DLInferer (detection) - PostProc - H.265 Encode"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H264_2MP 0) ! $(INFER_OD 0) ! $ENCODE_H265 \
              $(VIDEO_H264_2MP 1) ! $(INFER_OD 2) ! $ENCODE_H265 \
              $(VIDEO_H264_2MP 2) ! $(INFER_OD 4) ! $ENCODE_H265 \
              $(VIDEO_H264_2MP 3) ! $(INFER_OD 6) ! $ENCODE_H265 \
              $(VIDEO_H264_2MP 4) ! $(INFER_OD 8) ! $ENCODE_H265 \
              $(VIDEO_H264_2MP 5) ! $(INFER_OD 10) ! $ENCODE_H265 \
              $(VIDEO_H264_2MP 6) ! $(INFER_OD 12 1) ! $ENCODE_H265 \
              $(VIDEO_H264_2MP 7) ! $(INFER_OD 14 1) ! $ENCODE_H265 \
              $(VIDEO_H264_2MP 8) ! $(INFER_OD 16 1) ! $ENCODE_H265 \
              $(VIDEO_H264_2MP 9) ! $(INFER_OD 18 1) ! $ENCODE_H265 \
              $(VIDEO_H264_2MP 10) ! $(INFER_OD 20 1) ! $ENCODE_H265 \
              $(VIDEO_H264_2MP 11) ! $(INFER_OD 22 1) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H265"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

VIDEO_12CH_TEST_CASE_0009()
{
  echo "" >> $LOG_FILE

  NAME="VIDEO_12CH_TEST_CASE_0009"
  TITLE="12x video 2MP @30fps - H.265 Decode - PreProc - 12x DLInferer (detection) - PostProc - H.264 Encode"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H265_2MP 0) ! $(INFER_OD 0) ! $ENCODE_H264 \
              $(VIDEO_H265_2MP 1) ! $(INFER_OD 2) ! $ENCODE_H264 \
              $(VIDEO_H265_2MP 2) ! $(INFER_OD 4) ! $ENCODE_H264 \
              $(VIDEO_H265_2MP 3) ! $(INFER_OD 6) ! $ENCODE_H264 \
              $(VIDEO_H265_2MP 4) ! $(INFER_OD 8) ! $ENCODE_H264 \
              $(VIDEO_H265_2MP 5) ! $(INFER_OD 10) ! $ENCODE_H264 \
              $(VIDEO_H265_2MP 6) ! $(INFER_OD 12 1) ! $ENCODE_H264 \
              $(VIDEO_H265_2MP 7) ! $(INFER_OD 14 1) ! $ENCODE_H264 \
              $(VIDEO_H265_2MP 8) ! $(INFER_OD 16 1) ! $ENCODE_H264 \
              $(VIDEO_H265_2MP 9) ! $(INFER_OD 18 1) ! $ENCODE_H264 \
              $(VIDEO_H265_2MP 10) ! $(INFER_OD 20 1) ! $ENCODE_H264 \
              $(VIDEO_H265_2MP 11) ! $(INFER_OD 22 1) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H264"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}

VIDEO_12CH_TEST_CASE_00010()
{
  echo "" >> $LOG_FILE

  NAME="VIDEO_12CH_TEST_CASE_00010"
  TITLE="12x video 2MP @30fps - H.265 Decode - PreProc - 12x DLInferer (detection) - PostProc - H.265 Encode"
  echo $NAME
  echo "" >> $LOG_FILE

  GST_LAUNCH "$(VIDEO_H265_2MP 0) ! $(INFER_OD 0) ! $ENCODE_H265 \
              $(VIDEO_H265_2MP 1) ! $(INFER_OD 2) ! $ENCODE_H265 \
              $(VIDEO_H265_2MP 2) ! $(INFER_OD 4) ! $ENCODE_H265 \
              $(VIDEO_H265_2MP 3) ! $(INFER_OD 6) ! $ENCODE_H265 \
              $(VIDEO_H265_2MP 4) ! $(INFER_OD 8) ! $ENCODE_H265 \
              $(VIDEO_H265_2MP 5) ! $(INFER_OD 10) ! $ENCODE_H265 \
              $(VIDEO_H265_2MP 6) ! $(INFER_OD 12 1) ! $ENCODE_H265 \
              $(VIDEO_H265_2MP 7) ! $(INFER_OD 14 1) ! $ENCODE_H265 \
              $(VIDEO_H265_2MP 8) ! $(INFER_OD 16 1) ! $ENCODE_H265 \
              $(VIDEO_H265_2MP 9) ! $(INFER_OD 18 1) ! $ENCODE_H265 \
              $(VIDEO_H265_2MP 10) ! $(INFER_OD 20 1) ! $ENCODE_H265 \
              $(VIDEO_H265_2MP 11) ! $(INFER_OD 22 1) ! $PERF name=\"$NAME\" title=\"$TITLE\" ! $ENCODE_H265"

  if [ "$?" != "0" ]; then exit; fi
  echo "" >> $LOG_FILE
}
