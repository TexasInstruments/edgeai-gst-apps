from gst_element_map import gst_element_map
import gst_wrapper
import yaml
from post_process import create_title_frame, overlay_model_name
import os
import utils
import debug
import threading
import sys
from fractions import Fraction


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
        self.source = input_config["source"]
        self.width = input_config["width"]
        self.height = input_config["height"]
        self.fps = utils.to_fraction(input_config["framerate"])
        if "index" in input_config:
            self.index = input_config["index"]
        else:
            self.index = 0
        if "format" in input_config:
            self.format = input_config["format"]
        else:
            self.format = "auto"
        if "drop" in input_config:
            self.drop = input_config["drop"]
        else:
            self.drop = True
        if "pattern" in input_config:
            self.pattern = input_config["pattern"]
        else:
            self.pattern = "ball"
        if "loop" in input_config:
            self.loop = input_config["loop"]
        else:
            self.loop = False
        if "subdev-id" in input_config:
            self.subdev_id = input_config["subdev-id"]
        else:
            self.subdev_id = "/dev/v4l-subdev2"
        if "ldc" in input_config:
            self.ldc = input_config["ldc"]
        else:
            self.ldc = False
        if "sen-id" in input_config:
            self.sen_id = input_config["sen-id"]
        else:
            self.sen_id = "imx219"
        self.id = Input.count
        Input.count += 1
        self.split_count = 0
        self.splits = 0
        self.gst_inp_elements = gst_wrapper.get_input_elements(self)

    def increase_split(self):
        self.splits += 1
        self.split_count = int(self.splits / 2)
        if self.splits % 2:
            self.split_count += 1

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
        self.sink = output_config["sink"]
        self.width = output_config["width"]
        self.height = output_config["height"]
        self.fps = 0
        if "connector" in output_config:
            self.connector = output_config["connector"]
        else:
            self.connector = None
        if "port" in output_config:
            self.port = output_config["port"]
        else:
            self.port = 8081
        if "host" in output_config:
            self.host = output_config["host"]
        else:
            self.host = "0.0.0.0"
        if 'encoding' in output_config:
            self.encoding = output_config['encoding']
        else:
            self.encoding = 'h264'
        if "gop-size" in output_config:
            self.gop_size = output_config["gop-size"]
        else:
            self.gop_size = 30
        if "bitrate" in output_config:
            self.bitrate = output_config["bitrate"]
        else:
            self.bitrate = 10000000
        if "overlay-perf-type" in output_config:
            self.overlay_perf_type = output_config["overlay-perf-type"]
        else:
            self.overlay_perf_type = None
        self.mosaic = False
        self.id = Output.count
        self.gst_bkgnd_sink = None
        self.gst_pipe = None
        self.subflows = []
        self.title = title
        self.disp_elements_added_to_bin = False
        Output.count += 1

    def set_mosaic(self):
        self.mosaic = (gst_wrapper.gst_element_map["mosaic"]) != None
        if self.mosaic:
            # Flag to store if mosaic of this output is added to the pipeline.
            self.mosaic_added_to_bin = False
            # Flag to store sink number whose property is to be defined.
            self.num_mosaic_sink = 0
            # Keeps track of mosaic property to print later.
            self.mosaic_prop = {}

            self.gst_bkgnd_sink_name = "background_%d" % self.id
            (
                self.gst_background_elements,
                self.gst_mosaic_elements,
                self.gst_disp_elements,
            ) = gst_wrapper.get_output_elements(self)
            if self.overlay_perf_type != None:
                self.title_frame = create_title_frame(None, self.width, self.height)
            else:
                self.title_frame = create_title_frame(self.title, self.width, self.height)
            self.gst_player = gst_wrapper.add_and_link(self.gst_background_elements)
            self.bg_pipe = gst_wrapper.GstPipe([], self.gst_player)
            self.gst_bkgnd_sink = self.bg_pipe.get_sink(
                self.gst_bkgnd_sink_name, self.width, self.height, self.fps
            )

    def get_disp_id(self, subflow, fps):
        """
        Function to be called by flows which are using this output.
        Args:
            subflow: subflow
            fps: Framerate of the flow input
        """
        if subflow.x_pos == None or subflow.y_pos == None or not self.mosaic:
            if len(self.subflows) == 0:
                self.mosaic = False
                (
                    self.gst_background_elements,
                    self.gst_mosaic_elements,
                    self.gst_disp_elements,
                ) = gst_wrapper.get_output_elements(self)
            else:
                print(
                    "[ERROR] Need mosaic to support multiple subflow"
                    + " with same output"
                )
                sys.exit()
        elif (subflow.x_pos + subflow.width > self.width) or (
            subflow.y_pos + subflow.height > self.height
        ):
            print("[ERROR] Mosaic is not with in the background buffer")
            sys.exit()

        disp_id = len(self.subflows)
        self.subflows.append(subflow)
        if self.mosaic:
            self.title_frame = overlay_model_name(
                self.title_frame,
                subflow.model.model_name,
                subflow.x_pos,
                subflow.y_pos,
                subflow.width,
                subflow.height,
            )
        if float(Fraction(fps)) > float(Fraction(self.fps)):
            self.fps = fps
        return disp_id


class Flow:
    """
    Class to create and manage sub flows
    """

    count = 0

    def __init__(self, input, subflow_list, debug_config):
        """
        Constructor of Flow class.
        Args:
            flow_config: Dictionary of flow params provided in config file
            input: Input object for the flow
            subflow_list: Multi-dimensional list containing subflow info.
        """
        self.id = Flow.count
        self.sub_flows = []
        self.input = input
        self.debug_config = debug_config

        # If the source pad of scaler element is 1, then it is not multiscaler
        scaler_elem = gst_wrapper.gst_element_map["scaler"]["element"]
        self.is_multi_scaler = gst_wrapper.get_num_pads(scaler_elem, "src") != 1

        SubFlow.scaler_split_count = 0

        for s in subflow_list:
            self.sub_flows.append(SubFlow(input, s, self))

        Flow.count += 1


class SubFlow:
    """
    Class to construct a sub flow object combining
    input, model and output
    """

    count = 0
    scaler_split_count = 0

    def __init__(self, input, subflow_list, flow):
        """
        Constructor of SubFlow class.
        Args:
            input: Input object for the flow
            subflow_list: List containing subflow info.
            flow: Parent flow of this subflow
        """
        self.input = input
        self.model = subflow_list[0]
        self.outputs = subflow_list[1]
        self.mosaic_list = subflow_list[2]
        self.id = SubFlow.count

        self.sensor_width = 0
        self.sensor_height = 0
        self.mosaic_info = []

        for i in range(len(self.outputs)):
            self.output = self.outputs[i]
            mosaic = self.mosaic_list[i]
            if mosaic:
                self.x_pos = mosaic[0]
                self.y_pos = mosaic[1]
                self.width = mosaic[2]
                self.height = mosaic[3]
            else:
                self.x_pos = None
                self.y_pos = None
                self.width = self.output.width
                self.height = self.output.height

            self.mosaic_info.append([self.x_pos, self.y_pos, self.width, self.height])
            self.sensor_width = max(self.sensor_width, self.width)
            self.sensor_height = max(self.sensor_height, self.height)

            if self.input.width < self.width or self.input.height < self.height:
                print(
                    "[ERROR] Flow output resolution can not be greater than "
                    + "input resolution"
                )
                sys.exit()
            self.disp_id = self.output.get_disp_id(self, input.fps)

        if self.model.task_type == "classification":
            resize = self.model.resize[0]
            cam_dims = (self.input.width, self.input.height)
            # tiovxmultiscaler dosen't support odd resolutions
            self.pre_proc_resize = (
                ((cam_dims[0] * resize // min(cam_dims)) >> 1) << 1,
                ((cam_dims[1] * resize // min(cam_dims)) >> 1) << 1,
            )
        else:
            self.pre_proc_resize = self.model.resize

        self.id = SubFlow.count
        self.gst_scaler_name = "split_%d%d" % (
            self.input.id,
            SubFlow.scaler_split_count + 1,
        )
        self.gst_scaler_elements = gst_wrapper.get_scaler_elements(
            self, is_multi_src=flow.is_multi_scaler
        )
        self.gst_pre_src_name = "pre_%d" % self.id
        self.gst_pre_proc_elements = gst_wrapper.get_pre_proc_elements(self)
        self.input.increase_split()
        self.gst_sen_src_name = "sen_%d" % self.id
        self.gst_sensor_elements = gst_wrapper.get_sensor_elements(self)
        self.input.increase_split()
        self.gst_post_sink_name = "post_%d" % self.id
        self.gst_post_proc_elements = gst_wrapper.get_post_proc_elements(self)
        self.report = utils.Report(self)
        self.flow = flow
        self.debug_config = None
        if flow.debug_config:
            self.debug_config = debug.DebugConfig(self, flow.debug_config)
        SubFlow.count += 1
        SubFlow.scaler_split_count += 1
