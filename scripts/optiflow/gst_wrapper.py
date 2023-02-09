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
from pathlib import Path
abspath = Path(__file__).parent.absolute()
sys.path.insert(0,os.path.join(abspath,'../../apps_python'))
from gst_element_map import gst_element_map

target_idx = 0

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
        video_dec["h264"] += " ! v4l2h264dec capture-io-mode=5 " + \
                             " ! tiovxmemalloc pool-size=8 " + \
                             " ! video/x-raw, format=NV12 "
    else:
        video_dec["h264"] += " ! " + gst_element_map["h264dec"]["element"] + " "  
    
    if gst_element_map["h265dec"]["element"] == "v4l2h265dec":
        video_dec["h265"] += " ! v4l2h265dec capture-io-mode=5 " + \
                             " ! tiovxmemalloc pool-size=8 " + \
                             " ! video/x-raw, format=NV12 "
    else:
        video_dec["h265"] += " ! " + gst_element_map["h265dec"]["element"] + " "

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
        if (source_ext in video_ext):
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
           
            #TODO - Take sensor name and subdev as params
            source_cmd += ' tiovxisp sensor-name=%s' % sen_name + \
                          ' dcc-isp-file=/opt/imaging/%s/dcc_viss.bin'% \
                            input.sen_id + \
                          ' format-msb=%d' % \
                            format_msb + \
                          ' sink_0::dcc-2a-file=/opt/imaging/%s/dcc_2a.bin' % \
                            input.sen_id
            if (input.format.startswith('rggb')):
                source_cmd += ' sink_0::device=/dev/v4l-subdev%d' % \
                              input.subdev_id
            
            source_cmd += ' ! video/x-raw, format=NV12 ! '

            if input.ldc:
                source_cmd += ' tiovxldc' + \
                              ' dcc-file=/opt/imaging/%s/dcc_ldc.bin' % \
                                input.sen_id + \
                              ' sensor-name=%s !' % sen_name + \
                              ' video/x-raw, format=NV12,' + \
                              ' width=1920, height=1080 ! '
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
                     video_dec["h264"]

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

def get_input_split_str(input):
    if gst_element_map["scaler"]["element"] == "tiovxmultiscaler":
        if input.split_count == 1:
            source_cmd = 'tiovxmultiscaler name=split_%d%d \\\n' % \
                                                    (input.id, input.split_count)
        else:
            source_cmd = 'tee name=tee_split%d \\\n' % input.id
            for i in range(input.split_count):
                source_cmd += \
                    'tee_split%d. ! queue ! tiovxmultiscaler name=split_%d%d \\\n' % \
                                                        (input.id, input.id, i+1)
    else:
        source_cmd = 'tee name=tee_split%d \\\n' % input.id

    return source_cmd

def get_output_str(output):
    """
    Construct the gst output strings
    Args:
        output: output configuration
    """
    image_enc = {'.jpg':' jpegenc ! '}
    video_enc = {'.mov':' v4l2h264enc bitrate=10000000 ! h264parse ! qtmux ! ', \
                 '.mp4':' v4l2h264enc bitrate=10000000 ! h264parse ! mp4mux ! ', \
                 '.mkv':' v4l2h264enc bitrate=10000000 ! h264parse ! matroskamux ! '}

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
        elif (sink_ext in image_enc):
            sink = 'image'
        else:
            sink = 'others'
    else:
        sink = 'others'

    if (sink == 'display'):
        sink_cmd = ' queue ! tiperfoverlay ! kmssink sync=false driver-name=tidss'
        if (output.connector):
                sink_cmd += ' connector-id=%d' % output.connector
    elif (sink == 'image'):
        sink_cmd = image_enc[sink_ext] + \
                                    ' multifilesink location=' + output.sink
    elif (sink == 'video'):
        sink_cmd = ' queue ! tiperfoverlay !' + video_enc[sink_ext] + 'filesink location=' + output.sink

    elif (sink == 'remote'):
        sink_cmd = ' queue ! tiperfoverlay ! v4l2h264enc gop-size=30 bitrate=10000000 ! h264parse ! rtph264pay ! udpsink host=%s port=%d sync=false' % (output.host,output.port)

    elif (sink == 'others'):
        sink_cmd = ' queue ! tiperfoverlay ! ' + output.sink

    if (output.mosaic):
        sink_cmd = '! video/x-raw,format=NV12, width=%d, height=%d ' % (output.width,output.height) + '!' + sink_cmd
        mosaic_cmd = 'tiovxmosaic target=1 name=mosaic_%d' % (output.id) + ' \\\n'
    else:
        mosaic_cmd = ''

    return mosaic_cmd, sink_cmd

def get_pre_proc_str(flow):
    """
    Construct the gst string for pre-process
    Args:
        flow: flow configuration
    """
    global target_idx
    cmd = ''

    if (flow.model.task_type == 'classification'):
        resize = flow.model.resize[0]
        cam_dims = (flow.input.width, flow.input.height)
        #tiovxmultiscaler dosen't support odd resolutions
        if (gst_element_map["scaler"]["element"] == "tiovxmultiscaler"):
            resize = (((cam_dims[0]*resize//min(cam_dims)) >> 1) << 1, \
                      ((cam_dims[1]*resize//min(cam_dims)) >> 1) << 1)
    else:
        resize = flow.model.resize

    if (gst_element_map["scaler"]["element"] == "tiovxmultiscaler"):
        #tiovxmultiscaler dose not support upscaling and downscaling with scaling
        #factor < 1/4, So use "videoscale" insted
        if (float(flow.input.width)/resize[0] > 4 or \
                                            float(flow.input.height)/resize[1] > 4):
            width = (flow.input.width + resize[0]) // 2
            height = (flow.input.height + resize[1]) // 2
            if width % 2 != 0:
                width += 1
            if height % 2 != 0:
                height += 1     
            cmd += 'video/x-raw, width=%d, height=%d ! tiovxmultiscaler target=1 ! ' % \
                                                                    (width,height)
        
    
        elif (flow.input.width/resize[0] < 1 or flow.input.height/resize[1] < 1):
            cmd += 'video/x-raw, width=%d, height=%d ! videoscale ! ' % \
                                        (flow.input.width, flow.input.height)

        cmd += 'video/x-raw, width=%d, height=%d ! ' % tuple(resize)
    
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

    layout = 0 if flow.model.data_layout == "NCHW"  else 1
    tensor_fmt = "bgr" if (flow.model.reverse_channels) else "rgb"

    if   (flow.model.data_type == np.int8):
        data_type = 2
    elif (flow.model.data_type == np.uint8):
        data_type = 3
    elif (flow.model.data_type == np.int16):
        data_type = 4
    elif (flow.model.data_type == np.uint16):
        data_type = 5
    elif (flow.model.data_type == np.int32):
        data_type = 6
    elif (flow.model.data_type == np.uint32):
        data_type = 7
    elif (flow.model.data_type == np.float32):
        data_type = 10
    else:
        print("[ERROR] Unsupported data type for input tensor")
        sys.exit(1)

    cmd += 'tiovxdlpreproc data-type=%d ' % data_type + \
           'channel-order=%d ' % layout

    target = None
    if "target" in gst_element_map["dlpreproc"]["property"]:
        target = gst_element_map["dlpreproc"]["property"]["target"][target_idx]
        target_idx += 1
        if target_idx >= len(gst_element_map["dlpreproc"]["property"]["target"]):
            target_idx = 0

    if target != None:
        cmd += 'target=%d ' % target

    if (flow.model.mean):
        cmd += 'mean-0=%f mean-1=%f mean-2=%f ' % tuple(flow.model.mean)

    if (flow.model.scale):
        cmd += 'scale-0=%f scale-1=%f scale-2=%f ' % tuple(flow.model.scale)

    cmd += 'tensor-format=%s ' % tensor_fmt + \
           'out-pool-size=4 ! application/x-tensor-tiovx ! '

    split_name = flow.input.get_split_name()
    if (gst_element_map["scaler"]["element"] != "tiovxmultiscaler"):
        split_name = "tee_split%d" % (flow.input.id)

    cmd =   split_name + '. ! queue ! ' + cmd + \
            'tidlinferer model=%s ! %s.tensor ' % (flow.model.path, flow.gst_post_name)

    return cmd

def get_sensor_str(flow):
    """
    Construct the gst string for sensor input
    Args:
        flow: flow configuration
    """
    split_name = flow.input.get_split_name()
    if (gst_element_map["scaler"]["element"] != "tiovxmultiscaler"):
        split_name = "tee_split%d" % (flow.input.id)

    cmd = 'video/x-raw, width=%d, height=%d ! %s.sink ' % (flow.width, flow.height, flow.gst_post_name)
    if (gst_element_map["scaler"]["element"] == "tiovxmultiscaler"):
        cmd = split_name + '. ! queue ! ' + cmd
    else:
        cmd = split_name + '. ! ' + gst_element_map["scaler"]["element"] + ' ! queue ! ' + cmd
    return cmd

def get_post_proc_str(flow):
    cmd = 'tidlpostproc name=%s model=%s alpha=%f viz-threshold=%f top-N=%d ! ' % \
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

        src_str += '\\\n' + f.input.gst_split_str

        for s in f.sub_flows:
            src_str += s.gst_pre_proc_str + '\\\n'
            src_str += s.gst_sensor_str + '\\\n'
            src_str += s.gst_post_proc_str + "\\\n"

            if ("multifilesrc" in s.input.gst_str):
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