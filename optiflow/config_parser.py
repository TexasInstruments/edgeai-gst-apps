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

import gst_wrapper
import utils
import sys
import os
from gst_element_map import gst_element_map

class Input:
    """
    Class to parse and store input parameters
    """
    count = 0
    def __init__(self, input_config):
        """
        Constructor of Input class
        Args:
            input_config: Dictionary of input params provided in config file
        """
        self.source = input_config['source']
        self.width = input_config['width']
        self.height = input_config['height']
        self.fps = input_config['framerate']
        if 'index' in input_config:
            self.index = input_config['index']
        else:
            self.index = 0
        if 'format' in input_config:
            self.format = input_config['format']
        else:
            self.format = 'auto'
        if 'drop' in input_config:
            self.drop = input_config['drop']
        else:
            self.drop = True
        if 'pattern' in input_config:
            self.pattern = input_config['pattern']
        else:
            self.pattern = "ball"
        if 'loop' in input_config:
            self.loop = input_config['loop']
        else:
            self.loop = False
        if 'subdev-id' in input_config:
            self.subdev_id = input_config['subdev-id']
        else:
            self.subdev_id = "/dev/v4l-subdev2"
        if 'ldc' in input_config:
            self.ldc = input_config['ldc']
        else:
            self.ldc = False
        if 'sen-id' in input_config:
            self.sen_id = input_config['sen-id']
        else:
            self.sen_id = 'imx219'
        self.id = Input.count
        Input.count += 1
        self.split_count = 0
        self.splits = 0
        self.roi_strings = []
        self.roi_string = ''
        self.msc_target_string = ''
        self.gst_str = gst_wrapper.get_input_str(self)
        self.input_format = utils.get_format(self.gst_str)

    def get_split_name(self,flow):
        if self.splits % 4 == 0:
            if self.roi_string != '':
                self.roi_strings.append(self.roi_string)
            self.roi_string = ''
        self.splits += 1
        self.split_count = int(self.splits/4)
        if self.splits % 4:
            self.split_count += 1
        self.gst_split_str = gst_wrapper.get_input_split_str(self,flow)
        return 'split_%d%d' % (self.id, self.split_count)

class Output:
    """
    Class to parse and store output parameters
    """
    count = 0
    def __init__(self, output_config, title):
        """
        Constructor of Output class.
        Args:
            output_config: Dictionary of output params provided in config file
            title: Title of the demo to be added in the output
        """
        self.sink = output_config['sink']
        self.width = output_config['width']
        self.height = output_config['height']
        self.fps = 0
        self.title = ""
        if 'connector' in output_config:
            self.connector = output_config['connector']
        else:
            self.connector = None
        if 'port' in output_config:
            self.port = output_config['port']
        else:
            self.port = 8081
        if 'host' in output_config:
            self.host = output_config['host']
        else:
            self.host = '0.0.0.0'
        if 'encoding' in output_config:
            self.encoding = output_config['encoding']
        else:
            self.encoding = 'h264'
        if 'gop-size' in output_config:
            self.gop_size = output_config['gop-size']
        else:
            self.gop_size = 30
        if 'bitrate' in output_config:
            self.bitrate = output_config['bitrate']
        else:
            self.bitrate = 10000000
        if 'overlay-perf-type' in output_config:
            self.overlay_perf_type = output_config['overlay-perf-type']
        else:
            self.overlay_perf_type = None
        self.mosaic = False
        self.id = Output.count
        self.subflows = []
        Output.count += 1

    def set_mosaic(self):
        self.mosaic = (gst_element_map["mosaic"]) != None
        self.gst_mosaic_str, self.gst_disp_str = gst_wrapper.get_output_str(self)

    def get_disp_id(self, subflow, fps):
        """
        Function to be called by flows which are using this output.
        Args:
            x_pos: Horizontal Position of the flow output in final frame
            y_pos: Vertical Position of the flow output in final frame
            width: Width of the flow output
            height: Height of the flow output
            fps: Framerate of the flow input
        """
        if (subflow.x_pos == None or subflow.y_pos == None or not self.mosaic):
            if (len(self.subflows) == 0):
                self.mosaic = False
                self.gst_mosaic_str,self.gst_disp_str = gst_wrapper.get_output_str(self)
            else:
                print("[ERROR] Need mosaic to support multiple subflow" + \
                                                           " with same output")
                sys.exit()
        elif (subflow.x_pos + subflow.width > self.width) or \
                                 (subflow.y_pos + subflow.height > self.height):
            print("[ERROR] Mosaic is not with in the background buffer")
            sys.exit()

        disp_id = len(self.subflows)
        self.subflows.append(subflow)
        if (self.mosaic):
            if gst_element_map["mosaic"]["element"] == "tiovxmosaic":
                self.gst_mosaic_str = self.gst_mosaic_str + \
                            'sink_%d::startx="<%d>" ' % (disp_id, subflow.x_pos) + \
                            'sink_%d::starty="<%d>" ' % (disp_id, subflow.y_pos) + \
                            'sink_%d::widths="<%d>" ' % (disp_id, subflow.width) + \
                            'sink_%d::heights="<%d>" ' % (disp_id, subflow.height) + \
                            '\\\n'
            else:
                self.gst_mosaic_str = self.gst_mosaic_str + \
                            'sink_%d::startx=%d ' % (disp_id, subflow.x_pos) + \
                            'sink_%d::starty=%d ' % (disp_id, subflow.y_pos) + \
                            'sink_%d::width=%d ' % (disp_id, subflow.width) + \
                            'sink_%d::height=%d ' % (disp_id, subflow.height) + \
                            '\\\n'
        if fps > self.fps:
            self.fps = fps
        return disp_id


class Flow:
    """
    Class to create and manage sub flows
    """
    count = 0
    def __init__(self, input, subflow_list):
        self.id = Flow.count
        self.sub_flows = []
        self.input = input
        for s in subflow_list:
            if s[2]:
                for pos in s[2]:
                    self.sub_flows.append(SubFlow(input, s[0], s[1], pos, self))
            else:
                self.sub_flows.append(SubFlow(input, s[0], s[1], None, self))
        
        Flow.count += 1

class SubFlow:
    """
    Class to construct a sub flow object combining
    input, model and output
    """
    count = 0
    def __init__(self, input, model, output, pos, flow):
        """
        Constructor of SubFlow class.
        Args:
            input: Input object for the flow
            model: Model object for the flow
            output: Output object for the flow
            pos: Position of the flow output in the final frame
        """
        self.input = input
        self.model = model
        self.output = output
        if (pos):
            self.x_pos = pos[0]
            self.y_pos = pos[1]
            self.width = pos[2]
            self.height = pos[3]
        else:
            self.x_pos = None
            self.y_pos = None
            self.width = output.width
            self.height = output.height

        if (self.input.width < self.width or self.input.height < self.height):
            print("[ERROR] Flow output resolution can not be greater than " + \
                                                             "input resolution")
            sys.exit()

        self.disp_id = output.get_disp_id(self, input.fps)
        self.id = SubFlow.count
        self.gst_pre_src_name = 'pre_%d' % self.id
        self.gst_post_name = 'post_%d' % self.id
        self.gst_sen_src_name = 'sen_%d' % self.id
        self.gst_pre_proc_str = gst_wrapper.get_pre_proc_str(self)
        self.gst_sensor_str = gst_wrapper.get_sensor_str(self)
        self.gst_post_proc_str = gst_wrapper.get_post_proc_str(self)
        self.flow = flow
        SubFlow.count += 1
