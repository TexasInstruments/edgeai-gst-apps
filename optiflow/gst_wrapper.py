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

import os
import numpy as np
import utils
import sys
import time
import math
from pathlib import Path
abspath = Path(__file__).parent.absolute()
sys.path.insert(0,os.path.join(abspath,'../apps_python'))
from gst_element_map import gst_element_map, SOC
import gi

gi.require_version("Gst", "1.0")
gi.require_version("GstApp", "1.0")
from gi.repository import Gst

Gst.init(None)

tidl_target_idx = 0
preproc_target_idx = 0
isp_target_idx = 0
ldc_target_idx = 0
msc_target_idx = 0

class GstPipe:
    """
    Class to handle gstreamer pipeline related things
    to gst pipeline
    """

    def __init__(self, pipeline):
        """
        Create a gst pipeline using gst launch string
        Args:
            pipeline: Gstreamer pipeline string
        """
        self.pipeline = Gst.parse_launch(pipeline)

    def run(self):
        """
        Run the gst pipeline
        """
        bus = self.pipeline.get_bus()
        ret = self.pipeline.set_state(Gst.State.PLAYING)
        if ret == Gst.StateChangeReturn.FAILURE:
            msg = self.bus.timed_pop_filtered(Gst.CLOCK_TIME_NONE, Gst.MessageType.ERROR)
            err, debug_info = msg.parse_error()
            print("[ERROR]", err.message)
            sys.exit(1)
        try:
            while True:
                if bus.have_pending():
                    message = bus.pop()
                    if message.type == Gst.MessageType.EOS or message.type == Gst.MessageType.ERROR:
                        break
                time.sleep(0.01)
        except KeyboardInterrupt:
            pass
        finally:
            self.pipeline.set_state(Gst.State.NULL)

def get_input_str(input):
    """
    Construct the gst input string
    Args:
        input: input configuration
    """
    image_fmt = {'.jpg':'jpeg', '.png':'png'}
    image_dec = {'.jpg':' ! jpegdec ' , '.png':' ! pngdec '}
    video_ext = {
        ".mp4": " ! qtdemux",
        ".mov": " ! qtdemux",
        ".avi": " ! avidemux",
        ".mkv": " ! matroskademux",
    }

    video_dec = {'h264':' ! h264parse',
                'h265':' ! h265parse',
                'auto':' ! decodebin ! ' + \
                       gst_element_map["dlcolorconvert"]["element"] + \
                       ' ! video/x-raw, format=NV12 '}
    

    if gst_element_map["h264dec"]["element"] == "v4l2h264dec":
        video_dec["h264"] += " ! v4l2h264dec"

        if "property" in gst_element_map["h264dec"]:
            if "capture-io-mode" in gst_element_map["h264dec"]["property"]:
                video_dec["h264"] += " capture-io-mode=%s" % \
                       gst_element_map["h264dec"]["property"]["capture-io-mode"]

        video_dec["h264"] += " ! tiovxmemalloc pool-size=12" + \
                             " ! video/x-raw, format=NV12"
    else:
        video_dec["h264"] += " ! " + gst_element_map["h264dec"]["element"]
    
    if gst_element_map["h265dec"]["element"] == "v4l2h265dec":
        video_dec["h265"] += " ! v4l2h265dec"
        if "property" in gst_element_map["h265dec"]:
            if "capture-io-mode" in gst_element_map["h265dec"]["property"]:
                video_dec["h265"] += " capture-io-mode=%s" % \
                       gst_element_map["h265dec"]["property"]["capture-io-mode"]
        video_dec["h265"] += " ! tiovxmemalloc pool-size=12" + \
                             " ! video/x-raw, format=NV12"
    else:
        video_dec["h265"] += " ! " + gst_element_map["h265dec"]["element"]

    source_ext = os.path.splitext(input.source)[1]
    status = 0
    stop_index = -1
    if (input.source.startswith('/dev/video')):
        if (not os.path.exists(input.source)):
            status = 'no file'
        source = 'camera'
    elif (input.source.startswith('http')):
        if (source_ext not in video_ext):
            status = 'fmt err'
        source = 'http'
    elif (input.source.startswith('rtsp')):
        source = 'rtsp'
    elif (os.path.isfile(input.source)):
        if (source_ext == ".h264" or source_ext == ".h265"):
            source = 'raw_video'
        elif (source_ext in video_ext):
            source = 'video'
        elif (source_ext in image_dec):
            source = 'image'
            stop_index = 0
        else:
            status = 'fmt err'
    elif ('%' in input.source):
        if (not os.path.exists(input.source % input.index)):
            status = 'no file'
            input.source = input.source % input.index
        elif (not (source_ext in image_dec)):
            status = 'fmt err'
        else:
            source = 'image'
    elif (input.source == 'videotestsrc'):
        source = 'videotestsrc'
    else:
        status = 'no file'

    if (status):
        if (status == 'fmt err'):
            print("Invalid Input Format")
            print("Supported Image input formats : ", \
                                                  [i for i in image_dec.keys()])
            print("Supported video input formats : ", \
                                                  [i for i in video_ext.keys()])
        else:
            print("Invalid Input")
            print('"',input.source, '" doesn\'t exist')
        sys.exit(1)

    if (source == 'camera'):
        if input.format == 'jpeg':
            source_cmd = 'v4l2src device=%s io-mode=2 ! ' % input.source
            source_cmd += 'image/jpeg, width=%d, height=%d ! ' % \
                                                     (input.width, input.height)
            source_cmd += 'jpegdec ! '
            source_cmd += gst_element_map["dlcolorconvert"]["element"] + ' ! video/x-raw, format=NV12 ! '
        
        elif input.format == 'NV12':
            source_cmd = 'v4l2src device=%s ! ' % input.source
            source_cmd += 'video/x-raw, width=%d, height=%d, format=NV12 !' % \
                                                     (input.width, input.height)
        
        elif input.format.startswith('rggb') or input.format.startswith("bggi"):
            source_cmd = 'v4l2src device=%s io-mode=5 ! queue leaky=2 ! ' % input.source
            source_cmd += 'video/x-bayer, width=%d, height=%d, format=%s !' % \
                                       (input.width, input.height, input.format)
            if input.sen_id == "imx219":
                sen_name = "SENSOR_SONY_IMX219_RPI"
                format_msb = 7
            elif input.sen_id == "imx390":
                sen_name = "SENSOR_SONY_IMX390_UB953_D3"
                format_msb = 11
            elif input.sen_id == "ov2312":
                sen_name = "SENSOR_OV2312_UB953_LI"
                format_msb = 9
           
            source_cmd += ' tiovxisp sensor-name=%s' % sen_name + \
                          ' dcc-isp-file=/opt/imaging/%s/linear/dcc_viss.bin'% \
                            input.sen_id + \
                          ' format-msb=%d' % \
                            format_msb + \
                          ' sink_0::dcc-2a-file=/opt/imaging/%s/linear/dcc_2a.bin' % \
                            input.sen_id
            if (input.format.startswith('rggb')):
                source_cmd += ' sink_0::device=%s' % input.subdev_id
            
            global isp_target_idx
            if "property" in gst_element_map["isp"]:
                if "target" in gst_element_map["isp"]["property"]:
                    source_cmd += ' target=%s' % \
                        gst_element_map["isp"]["property"]["target"][isp_target_idx]
                    isp_target_idx += 1
                    if isp_target_idx >= len(gst_element_map["isp"]["property"]["target"]):
                        isp_target_idx = 0

            source_cmd += ' ! video/x-raw, format=NV12 ! '

            if input.ldc:
                source_cmd += ' tiovxldc' + \
                              ' dcc-file=/opt/imaging/%s/linear/dcc_ldc.bin' % \
                                input.sen_id + \
                              ' sensor-name=%s' % sen_name

                global ldc_target_idx
                if "property" in gst_element_map["ldc"]:
                    if "target" in gst_element_map["ldc"]["property"]:
                        source_cmd += ' target=%s' % \
                            gst_element_map["ldc"]["property"]["target"][ldc_target_idx]
                        ldc_target_idx += 1
                        if ldc_target_idx >= len(gst_element_map["ldc"]["property"]["target"]):
                            ldc_target_idx = 0

                source_cmd += ' ! video/x-raw,format=NV12,width=1920,height=1080 ! '
                input.width = 1920
                input.height = 1080
        else:
            source_cmd = 'v4l2src device=%s ! ' % input.source
            source_cmd += 'video/x-raw, width=%d, height=%d ! ' % \
                                                     (input.width, input.height)
            source_cmd += gst_element_map["dlcolorconvert"]["element"] + ' ! video/x-raw, format=NV12 ! '

    elif (source == 'http'):
        if not(input.format in video_dec):
            input.format = "auto"
        source_cmd = 'souphttpsrc location=' + input.source + \
                                 video_ext[source_ext] + video_dec[input.format]
        source_cmd += ' !'

    elif (source == 'rtsp'):
        source_cmd = 'rtspsrc location=' + input.source + \
                     ' latency=0 buffer-mode=auto ! rtph264depay' + \
                     video_dec["h264"] + ' ! '

    elif (source == 'image'):
        source_cmd = 'multifilesrc location=' + input.source
        source_cmd += ' loop=true' if input.loop else '' + \
                           ' index=%d stop-index=%d' % (input.index, stop_index)
        source_cmd += ' caps=image/' + image_fmt[source_ext] + ',framerate=1/1 '
        source_cmd += image_dec[source_ext]
        source_cmd += ' ! videoscale ! video/x-raw, width=%d, height=%d ! ' % \
                                                     (input.width, input.height)
        source_cmd += gst_element_map["dlcolorconvert"]["element"] + \
                      ' ! video/x-raw, format=NV12 ! '

    elif (source == 'raw_video'):
        source_cmd = 'multifilesrc location=' + input.source
        source_cmd += ' loop=true stop-index=-1' if input.loop else ' loop=false stop-index=0'

        # Set caps only in case of hardware decoder
        if ((input.format == "h264" and gst_element_map["h264dec"]["element"] == "v4l2h264dec") or
            (input.format == "h265" and gst_element_map["h264dec"]["element"] == "v4l2h264dec")):
            source_cmd += ' caps=video/x-' + input.format
            source_cmd += ',width=%d,height=%d,framerate=%d/1' % (input.width,input.height,input.fps)

        source_cmd +=  video_dec[input.format]
        source_cmd += ' ! '

    elif (source == 'video'):
        if not(input.format in video_dec):
            input.format = "auto"
        source_cmd = 'filesrc location=' + input.source + video_ext[source_ext]\
                                                       + video_dec[input.format]
        source_cmd += ' ! '

    elif (source == 'videotestsrc'):
        source_cmd = 'videotestsrc pattern=%s ' % input.pattern
        source_cmd += '! video/x-raw, width=%d, height=%d, format=%s ! ' % \
                                       (input.width, input.height, input.format)
        if input.format != 'NV12':
            source_cmd += gst_element_map["dlcolorconvert"]["element"] + \
                          ' ! video/x-raw, format=NV12 ! '
    return source_cmd

def get_input_split_str(input,flow):

    global msc_target_idx

    if gst_element_map["scaler"]["element"] == "tiovxmultiscaler":
        crop_startx = (((flow.model.resize[0] - flow.model.crop[0])/2)/flow.model.resize[0]) * flow.input.width
        crop_startx = int(crop_startx)
        crop_starty = (((flow.model.resize[1] - flow.model.crop[1])/2)/flow.model.resize[1]) * flow.input.height
        crop_starty = int(crop_starty)
        crop_width = flow.input.width - (2*crop_startx)
        crop_height = flow.input.height - (2*crop_starty)
        if ((input.splits - 1) // 2) % 2 == 0:
            src_pad = 0
        else:
            src_pad = 2
        if input.splits % 2 == 0:
            input.roi_string += " src_%d::roi-startx=%d" % (src_pad,crop_startx)
            input.roi_string += " src_%d::roi-starty=%d" % (src_pad,crop_starty)
            input.roi_string += " src_%d::roi-width=%d" % (src_pad,crop_width)
            input.roi_string += " src_%d::roi-height=%d" % (src_pad,crop_height)

        # Load-balancing the msc targets
        if input.msc_target_string == '':
            if "property" in gst_element_map["scaler"]:
                if "target" in gst_element_map["scaler"]["property"]:
                    target = gst_element_map["scaler"]["property"]["target"][msc_target_idx]
                    msc_target_idx += 1
                    if msc_target_idx >= len(gst_element_map["scaler"]["property"]["target"]):
                        msc_target_idx = 0
                    input.msc_target_string = 'target=%d' % target

        if input.split_count == 1:
            source_cmd = 'tiovxmultiscaler name=split_%d%d ' % \
                                                   (input.id, input.split_count)
            source_cmd += input.msc_target_string + ' \\\n'
        else:
            source_cmd = 'tee name=tee_split%d \\\n' % input.id
            for i in range(input.split_count):
                source_cmd += \
                    'tee_split%d. ! queue ! tiovxmultiscaler name=split_%d%d ' % \
                                                       (input.id, input.id, i+1)
                source_cmd += input.msc_target_string + ' \\\n'
    else:
        source_cmd = 'tee name=tee_split%d \\\n' % input.id

    return source_cmd

def get_output_str(output):
    """
    Construct the gst output strings
    Args:
        output: output configuration
    """
    video_enc = {'.mov':' ! h264parse ! qtmux ! ', \
                 '.mp4':' ! h264parse ! mp4mux ! ', \
                 '.mkv':' ! h264parse ! matroskamux ! '}

    sink_ext = os.path.splitext(output.sink)[1]
    status = 0
    if (output.sink == 'kmssink'):
        sink = 'display'
    elif (output.sink == 'remote'):
        sink = 'remote'
    elif (os.path.isdir(os.path.dirname(output.sink)) or \
                                    not os.path.dirname(output.sink)):
        if (sink_ext in video_enc):
            sink = 'video'
        elif (sink_ext == ".jpg"):
            sink = 'image'
        else:
            sink = 'others'
    else:
        sink = 'others'

    if (sink == 'display'):
        sink_cmd = ''
        if output.overlay_perf_type != None:
            sink_cmd += ' queue ! tiperfoverlay overlay-type=%s !' % output.overlay_perf_type
        sink_cmd += ' kmssink driver-name=tidss sync=false'
        #HACK - without this some models in am62a results in display flicker
        if (SOC == "am62a"):
            sink_cmd += ' force-modesetting=true'
        if (output.connector):
                sink_cmd += ' connector-id=%d' % output.connector
    elif (sink == 'image'):
        sink_cmd = ' ' + gst_element_map["jpegenc"]["element"] + ' !' + \
                                    ' multifilesink location=' + output.sink
    elif (sink == 'video'):
        sink_cmd = ''
        if output.overlay_perf_type != None:
            sink_cmd += ' queue ! tiperfoverlay overlay-type=%s !' % output.overlay_perf_type

        sink_cmd += ' ' + gst_element_map["h264enc"]["element"]

        if (gst_element_map["h264enc"]["element"] == "v4l2h264enc"):
            prop_str = "video_bitrate=%d, video_gop_size=%d" \
                                              % (output.bitrate,output.gop_size)
            enc_extra_ctrl = "extra-controls=\"controls, " + \
                            "frame_level_rate_control_enable=1, " + \
                            prop_str + \
                            "\""
            sink_cmd += ' ' + enc_extra_ctrl

        sink_cmd += video_enc[sink_ext] + 'filesink location=' + output.sink

    elif (sink == 'remote'):
        sink_cmd = ''
        if output.overlay_perf_type != None:
            sink_cmd += ' queue ! tiperfoverlay overlay-type=%s !' % output.overlay_perf_type

        if output.encoding == "mp4" or output.encoding == "h264":

            sink_cmd += ' ' + gst_element_map["h264enc"]["element"]

            if (gst_element_map["h264enc"]["element"] == "v4l2h264enc"):
                prop_str = "video_bitrate=%d, video_gop_size=%d" \
                                              % (output.bitrate,output.gop_size)
                enc_extra_ctrl = "extra-controls=\"controls, " + \
                                "frame_level_rate_control_enable=1, " + \
                                prop_str + \
                                "\""
                sink_cmd +=  ' ' + enc_extra_ctrl

            sink_cmd += ' ! h264parse !'

            if output.encoding == "mp4":
                sink_cmd += ' mp4mux fragment-duration=1 !'
            elif output.encoding == "h264":
                sink_cmd += ' rtph264pay !'

        elif output.encoding == "jpeg":
            sink_cmd += ' ' + gst_element_map["jpegenc"]["element"] + ' ! multipartmux boundary=spionisto ! rndbuffersize max=65000 !'

        else:
            print("[ERROR] Wrong encoding [%s] defined for remote output.", output.encoding)
            sys.exit()

        sink_cmd += ' udpsink host=%s port=%d sync=false' % (output.host,output.port)

    elif (sink == 'others'):
        sink_cmd = ''
        if output.overlay_perf_type != None:
            sink_cmd += ' queue ! tiperfoverlay overlay-type=%s !' % output.overlay_perf_type
        sink_cmd += ' ' + output.sink

    if (output.mosaic):
        sink_cmd = '! video/x-raw,format=NV12, width=%d, height=%d ' % (output.width,output.height) + '!' + sink_cmd
        mosaic_cmd = gst_element_map["mosaic"]["element"] + ' name=mosaic_%d' % (output.id)
        if gst_element_map["mosaic"]["element"] == "tiovxmosaic":
            mosaic_cmd += ' target=1 src::pool-size=4'
        mosaic_cmd += ' \\\n'
    else:
        mosaic_cmd = ''

    return mosaic_cmd, sink_cmd

def get_pre_proc_str(flow):
    """
    Construct the gst string for pre-process
    Args:
        flow: flow configuration
    """
    global preproc_target_idx, tidl_target_idx
    cmd = ''

    resize = flow.model.resize
    crop = flow.model.crop

    crop_startx = (((resize[0] - crop[0])/2)/resize[0]) * flow.input.width
    crop_startx = int(crop_startx)
    crop_starty = (((resize[1] - crop[1])/2)/resize[1]) * flow.input.height
    crop_starty = int(crop_starty)
    crop_width = flow.input.width - (2*crop_startx)
    crop_height = flow.input.height - (2*crop_starty)


    if (gst_element_map["scaler"]["element"] == "tiovxmultiscaler"):
        #tiovxmultiscaler dose not support upscaling and downscaling with scaling
        #factor < 1/4, So use "videoscale" insted
        if (float(crop_width)/crop[0] > 4 or \
                                            float(crop_height)/crop[0] > 4):
            width = max(crop[0], math.ceil(crop_width / 4))
            height = max(crop[1], math.ceil(crop_height / 4))
            if width % 2 != 0:
                width += 1
            if height % 2 != 0:
                height += 1     
            cmd += 'video/x-raw, width=%d, height=%d ! tiovxmultiscaler ! ' % \
                                                                  (width,height)

        elif (crop_width/crop[0] < 1 or crop_height/crop[1] < 1):
            cmd += 'video/x-raw, width=%d, height=%d ! videoscale ! ' % \
                                                       (crop_width, crop_height)

        cmd += 'video/x-raw, width=%d, height=%d ! ' % tuple(crop)
    
    elif (gst_element_map["scaler"]["element"] == "tiscaler"):
        roi_string = ' roi-startx=%d roi-starty=%d roi-width=%d roi-height=%d' % \
                                (crop_startx,crop_starty,crop_width,crop_height)

        cmd += gst_element_map["scaler"]["element"] + '%s ! ' % roi_string
        cmd += 'video/x-raw, width=%d, height=%d ! ' % tuple(crop)

    else:
        cmd += gst_element_map["scaler"]["element"] + \
               ' ! video/x-raw, width=%d, height=%d ! ' % tuple(resize)

        if (flow.model.task_type == 'classification'):
            cmd += gst_element_map["dlcolorconvert"]["element"]
            if "property" in gst_element_map["dlcolorconvert"]:
                if "out-pool-size" in gst_element_map["dlcolorconvert"]["property"]:
                    cmd += ' out-pool-size=%d' % gst_element_map["dlcolorconvert"]["property"]["out-pool-size"]

            cmd += ' ! video/x-raw, format=RGB ! '

            left = (resize[0] - flow.model.crop[0])//2
            right = resize[0] - flow.model.crop[0] - left
            top = (resize[1] - flow.model.crop[1])//2
            bottom = resize[1] - flow.model.crop[1] - top
            cmd += 'videobox left=%d right=%d top=%d bottom=%d ! ' % \
                                                        (left, right, top, bottom)

    if not gst_element_map["dlpreproc"]:
        print("[ERROR] Need dlpreproc element for end-to-end pipeline")
        sys.exit()

    cmd += gst_element_map["dlpreproc"]["element"] + ' model=%s ' % flow.model.path

    target = None
    if "property" in gst_element_map["dlpreproc"]:
        if "target" in gst_element_map["dlpreproc"]["property"]:
            target = gst_element_map["dlpreproc"]["property"]["target"][preproc_target_idx]
            preproc_target_idx += 1
            if preproc_target_idx >= len(gst_element_map["dlpreproc"]["property"]["target"]):
                preproc_target_idx = 0
            cmd += 'target=%d ' % target

        if "out-pool-size" in gst_element_map["dlpreproc"]["property"]:
            cmd += ' out-pool-size=%d ' % gst_element_map["dlpreproc"]["property"]["out-pool-size"]

    cmd += '! application/x-tensor-tiovx ! '

    split_name = flow.input.get_split_name(flow)

    if (gst_element_map["scaler"]["element"] != "tiovxmultiscaler"):
        split_name = "tee_split%d" % (flow.input.id)

    '''
        set secondary msc target if present
        secondary multiscaler target will always be complimentary of primary.
        For ex: msc_targets=[0,1,2,3]
            If primary msc target is 0, secondary will be 1
            If primary msc target is 1, secondary will be 2
            ..and so on
    '''
    if 'tiovxmultiscaler' in cmd:
        input_target = None
        for i in flow.input.gst_split_str.split("!"):
            if 'tiovxmultiscaler' in i:
                for j in i.split(" "):
                    if 'target' in j:
                        input_target = int(j.split("=")[-1].strip())
        if (input_target != None):
            msc_targets = gst_element_map["scaler"]["property"]["target"]
            target_idx = len(msc_targets) - msc_targets.index(input_target) - 1
            replacement_string = 'tiovxmultiscaler target=%d' % msc_targets[target_idx]
            cmd = cmd.replace('tiovxmultiscaler' , replacement_string )

    # Set dl_inferer core number
    target_str = ''
    if "core-id" in gst_element_map["inferer"]:
        target = gst_element_map["inferer"]["core-id"][tidl_target_idx]
        tidl_target_idx += 1
        if tidl_target_idx >= len(gst_element_map["inferer"]["core-id"]):
            tidl_target_idx = 0
        target_str = 'target=%d ' % target

    cmd =   split_name + '. ! queue ! ' + cmd + \
            'tidlinferer %s model=%s ! %s.tensor ' % (target_str, flow.model.path, flow.gst_post_name)

    return cmd

def get_sensor_str(flow):
    """
    Construct the gst string for sensor input
    Args:
        flow: flow configuration
    """
    split_name = flow.input.get_split_name(flow)
    if (gst_element_map["scaler"]["element"] != "tiovxmultiscaler"):
        split_name = "tee_split%d" % (flow.input.id)

    cmd = 'video/x-raw, width=%d, height=%d ! %s.sink ' % (flow.width, flow.height, flow.gst_post_name)
    if (gst_element_map["scaler"]["element"] == "tiovxmultiscaler"):
        cmd = split_name + '. ! queue ! ' + cmd
    else:
        cmd = split_name + '. ! queue ! ' + gst_element_map["scaler"]["element"] + ' ! ' + cmd
    return cmd

def get_post_proc_str(flow):
    cmd = 'tidlpostproc name=%s model=%s alpha=%f viz-threshold=%f top-N=%d display-model=true ! ' % \
          (flow.gst_post_name, flow.model.path, flow.model.alpha, flow.model.viz_threshold, flow.model.topN)

    if (flow.output.mosaic):
        cmd += "queue ! mosaic_%d. " % (flow.output.id)    
    
    return cmd

def get_gst_str(flows, outputs):
    """
    Construct the src and sink string
    Args:
        inputs: List of inputs
        flows: List of flows
        outputs: List of outputs
    """
    src_strs = []

    for f in flows:
        src_str = f.input.gst_str
        if (f.input.input_format != "NV12"):
            src_str += gst_element_map["dlcolorconvert"]["element"] + \
                       " ! video/x-raw,format=NV12 ! "

        if len(f.input.roi_strings) != f.input.split_count:
            f.input.roi_strings.append(f.input.roi_string)
        for i,roi_str in enumerate(f.input.roi_strings):
            actual_string = "tiovxmultiscaler name=split_%d%d" %  (f.input.id,(i+1))
            replacement_string = actual_string + roi_str
            f.input.gst_split_str = f.input.gst_split_str.replace(actual_string,replacement_string)

        mosaic = True
        for s in f.sub_flows:
            if not s.output.mosaic:
                mosaic = False

        if not mosaic:
            if gst_element_map["scaler"]["element"] == "tiovxmultiscaler":
                sink_property = ""
                for i in range(1,f.input.splits,2):
                    sink_property += "src_%d::pool-size=4 " % i
                sink_property = sink_property.strip()
                replacement_string = "tiovxmultiscaler " + sink_property
                f.input.gst_split_str = f.input.gst_split_str.replace("tiovxmultiscaler",replacement_string)
            else:
                #Increase Post Proce Sink Pool size
                pass

        src_str += '\\\n' + f.input.gst_split_str + '\\\n'

        for s in f.sub_flows:
            src_str += s.gst_pre_proc_str + '\\\n'
            src_str += s.gst_sensor_str + '\\\n'
            src_str += s.gst_post_proc_str + "\\\n"

            if (os.path.splitext(s.input.source)[1] in ['.jpg','.jpeg','.png']):
                s.output.gst_disp_str = s.output.gst_disp_str.replace("sync=false","sync=true")

            if s.output.mosaic:
                src_str += "\\\n"
            else:
                src_str += s.output.gst_disp_str.strip() +" \\\n\\\n"
        src_strs.append(src_str)

    sink_str = ''
    for i,o in enumerate(outputs.values()):
        if not o.mosaic:
            continue
        sink_str +=  "\\\n" + o.gst_mosaic_str + o.gst_disp_str + " \\\n"
    return src_strs , sink_str
