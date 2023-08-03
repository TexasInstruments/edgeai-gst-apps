import gi

gi.require_version("Gst", "1.0")
gi.require_version("GstApp", "1.0")
from gi.repository import Gst, GstApp, GLib, GObject
import numpy as np
import os
import sys
import utils
import time
from threading import Lock
from gst_element_map import gst_element_map

Gst.init(None)

preproc_target_idx = 0
isp_target_idx = 0
ldc_target_idx = 0

class GstPipe:
    """
    Class to handle gstreamer pipeline related things
    Exposes apis to get appsrc, appsink and push, pull frames
    to gst pipeline
    """

    def __init__(self, src_pipe, sink_pipe):
        """
        Create a gst pipeline using gst launch string
        Args:
            src_pipe: list of gst pipeline for src (input)
            sink_pipe: gst pipeline for sink (output)
        """
        self.src_pipe = src_pipe
        self.sink_pipe = sink_pipe
        self.mutex = Lock()

    def start(self):
        """
        Start the gst pipeline
        """
        ret = self.sink_pipe.set_state(Gst.State.PLAYING)
        if ret == Gst.StateChangeReturn.FAILURE:
            bus = self.sink_pipe.get_bus()
            msg = bus.timed_pop_filtered(Gst.CLOCK_TIME_NONE, Gst.MessageType.ERROR)
            err, debug_info = msg.parse_error()
            print("[ERROR]", err.message)
            sys.exit(1)

        for src in self.src_pipe:
            ret = src.set_state(Gst.State.PLAYING)
            if ret == Gst.StateChangeReturn.FAILURE:
                bus = src.get_bus()
                msg = bus.timed_pop_filtered(Gst.CLOCK_TIME_NONE, Gst.MessageType.ERROR)
                err, debug_info = msg.parse_error()
                print("[ERROR]", err.message)
                sys.exit(1)

    def get_src(self, name, flow_id):
        """
        get the gst src element by name
        """
        return self.src_pipe[flow_id].get_by_name(name)

    def get_sink(self, name, width, height, fps):
        """
        get the gst sink element by name
        """
        caps = Gst.caps_from_string(
            "video/x-raw, "
            + "width=%d, " % width
            + "height=%d, " % height
            + "format=RGB, "
            + "framerate=%s" % str(fps)
        )
        sink = self.sink_pipe.get_by_name(name)
        sink.set_caps(caps)
        return sink

    def pull_frame(self, src, loop):
        """
        Pull a frame from gst pipeline
        Args:
            src: gst src element from which the frame is pulled
            loop: If src need to be looped after eos
        """
        sample = src.try_pull_sample(5000000000)
        if type(sample) != Gst.Sample:
            if src.is_eos():
                if loop:
                    # Seek can be called from various sources hence putting lock
                    with self.mutex:
                        src.seek_simple(Gst.Format.TIME, Gst.SeekFlags.FLUSH, 0)
                        sample = src.try_pull_sample(5000000000)
                else:
                    return None
            else:
                print("[ERROR] Error pulling frame from GST Pipeline")
                return None
        caps = sample.get_caps()

        struct = caps.get_structure(0)
        width = struct.get_value("width")
        height = struct.get_value("height")

        buffer = sample.get_buffer()
        _, map_info = buffer.map(Gst.MapFlags.READ)
        frame = np.ndarray((height, width, 3), np.uint8, map_info.data)
        buffer.unmap(map_info)

        return frame

    def pull_tensor(self, src, loop, width, height, layout, data_type):
        """
        Pull a frame from gst pipeline
        Args:
            src: gst src element from which the frame is pulled
            loop: If src need to be looped after eos
            width: width of the tensor
            height: height of the tensor
            layout: data layout (NHWC or NCHW)
            data_type: data type of the tensor
        """
        sample = src.try_pull_sample(5000000000)
        if type(sample) != Gst.Sample:
            if src.is_eos():
                if loop:
                    # Seek can be called from various sources hence putting lock
                    with self.mutex:
                        src.seek_simple(Gst.Format.TIME, Gst.SeekFlags.FLUSH, 0)
                        sample = src.try_pull_sample(5000000000)
                else:
                    return None
            else:
                print("[ERROR] Error pulling tensor from GST Pipeline")
                return None
        buffer = sample.get_buffer()
        _, map_info = buffer.map(Gst.MapFlags.READ)
        if layout == "NHWC":
            frame = np.ndarray((1, height, width, 3), data_type, map_info.data)
        elif layout == "NCHW":
            frame = np.ndarray((1, 3, height, width), data_type, map_info.data)
        buffer.unmap(map_info)

        return frame

    def push_frame(self, frame, sink):
        """
        Push a frame from gst pipeline
        Args:
            frame: output frame to be pushed
            sink: gst sink element to which the frame is pushed
        """
        buffer = Gst.Buffer.new_wrapped(frame.tobytes())
        sink.push_buffer(buffer)

    def send_eos(self, sink):
        """
        Send EOS singnal to the sink
        Args:
            sink: gst sink element to which EOS is sent
        """
        sink.end_of_stream()

    def free(self):
        """
        Free the gst pipeline
        """
        # wait for EOS in sink pipeline
        bus = self.sink_pipe.get_bus()
        msg = bus.timed_pop_filtered(
            Gst.CLOCK_TIME_NONE, Gst.MessageType.ERROR | Gst.MessageType.EOS
        )
        if msg:
            if msg.type == Gst.MessageType.ERROR:
                err, debug_info = msg.parse_error()
                print("[ERROR]", err.message)
        self.sink_pipe.set_state(Gst.State.NULL)
        for src in self.src_pipe:
            src.set_state(Gst.State.NULL)


def dump_dot_file(data, prefix):
    """
    Function to save gstreamer pipelines as dot file
    Args:
        dara: List of Gst Pipeline to be saved as dot
        prefix: Prefix Given to the dot file name
    """
    directory = os.environ.get("GST_DEBUG_DUMP_DOT_DIR")
    if not directory:
        print(
            "\n[SKIPPING] .dot of pipeline cannot be dumped.You need to define the GST_DEBUG_DUMP_DOT_DIR env var to dump a .dot graph of the running pipeline"
        )
        return -1
    elif not os.path.isdir(directory):
        print(
            "\n[WARNING]%s defined by GST_DEBUG_DUMP_DOT_DIR env var does not exist. Creating it..."
            % directory
        )
        try:
            os.mkdir(directory)
            print("[SUCCESS]Created %s" % directory)
        except:
            print("[ERROR]Creation of %s failed." % directory)
            return -1

    if type(data) != list:
        data = [data]

    config_file_name = os.path.split(utils.args.config)[-1]
    config_file_name = config_file_name.split(".")[0]

    for index, i in enumerate(data):
        filename = "%s_%s%d" % (config_file_name, prefix, index)
        dotfile = os.path.join(directory, "{0}.dot".format(filename))
        if os.path.isfile(dotfile):
            os.remove(dotfile)
        Gst.debug_bin_to_dot_file(i, Gst.DebugGraphDetails.ALL, filename)
    return 0


def get_caps(element, pad_name):
    """
    Returns caps of an element
    Args:
        element: GstElement
        pad_name: caps of which pad
    """
    pad = element.get_static_pad(pad_name)
    caps = pad.get_current_caps()
    if not caps:
        caps = pad.get_allowed_caps()
    return caps


def get_pad_info(element_factory, pad_name, info_type):
    """
    Returns info about a pad
    Args:
        element_factory: GstElementFactory
        pad_name: GstPad
        info_type: "caps" or "presence"
    """
    pads = element_factory.get_static_pad_templates()
    for pad in pads:
        padtemplate = pad.get()

        if pad.direction == Gst.PadDirection.SRC and pad_name == "src":
            if info_type == "caps":
                return padtemplate.get_caps()
            elif info_type == "presence":
                return padtemplate.presence

        elif pad.direction == Gst.PadDirection.SINK and pad_name == "sink":
            if info_type == "caps":
                return padtemplate.get_caps()
            elif info_type == "presence":
                return padtemplate.presence
    return None


def get_pad_format(element_factory, pad_name):
    """
    Returns list of format supported by pad of an element
    Args:
        element_factory: GstElementFactory
        pad_name: GstPad
    """
    data = []
    caps = get_pad_info(element_factory, pad_name, "caps")
    if caps.is_any():
        return 1
    prop_list = caps.get_structure(0).get_list("format").array
    for i in range(prop_list.n_values):
        data.append(prop_list.get_nth(i))
    return data


def get_num_pads(element_name, pad_name):
    """
    Returns number of pads of an element
    Args:
        element_name: factory name of gst element
        pad_name: GstPad
    """
    elem = Gst.ElementFactory.make(element_name)
    num_pad = None
    if pad_name == "src":
        num_pad = elem.numsrcpads
    elif pad_name == "sink":
        num_pad = elem.numsinkpads
    del elem
    return num_pad


def get_format_string(element, pad_name):
    """
    Returns format of element as string
    Args:
        element: Gst element
        pad_name: GstPad
    """
    pad = element.get_static_pad(pad_name)
    if not pad:
        return None
    caps = pad.get_current_caps()
    if not caps:
        caps = pad.get_allowed_caps()
    if not caps or caps.is_empty():
        return None
    if caps.is_any():
        return 1
    if caps.get_size() > 0:
        try:
            return caps.get_structure(0).get_value("format")
        except:
            return None


def get_format(pipeline, input_elements):
    """
    Returns the format of last element in pipeline after caps negotiation
    Args:
        pipeline: Gst Pipeline
        format_name: format or tensor-format
    """
    src_element = input_elements[0]
    last_element = input_elements[-1]

    # Check if last element is capsfilter and format is already defined
    if last_element.get_factory().get_name() == "capsfilter":
        caps = last_element.get_property("caps")
        if caps and caps.get_size() > 0:
            structure = last_element.get_property("caps").get_structure(0)
            format = structure.get_value("format")
            if format != None:
                return format

    last_element_klass = last_element.get_metadata("klass")
    fakesink = None
    # Add fakesink at the end if last element is not sink
    if "Sink" not in last_element_klass:
        fakesink = Gst.ElementFactory.make("fakesink", "fakesink")
        pipeline.add(fakesink)
        last_element.link(fakesink)
    else:
        last_element = last_element.sinkpads[0].get_peer().get_parent()

    if src_element.get_factory().get_name() == "multifilesrc":
        default_buffers = int(src_element.get_property("num-buffers"))
        src_element.set_property("num-buffers", 1)

    format = None

    bus = pipeline.get_bus()
    pipeline.set_state(Gst.State.PLAYING)
    terminate = False

    t_end = time.time() + 3
    while time.time() < t_end:
        try:
            msg = bus.timed_pop_filtered(
                0.5 * Gst.SECOND, Gst.MessageType.STATE_CHANGED
            )
            if msg:
                if msg.src == pipeline:
                    old, new, pending = msg.parse_state_changed()
                    if old == Gst.State.READY and new == Gst.State.PAUSED:
                        format = get_format_string(last_element, "src")
                        if format:
                            break
                    if (
                        not format
                        and old == Gst.State.PAUSED
                        and new == Gst.State.PLAYING
                    ):
                        format = get_format_string(last_element, "src")
                        break
        except:
            format = None

    pipeline.set_state(Gst.State.NULL)


    if src_element.get_factory().get_name() == "multifilesrc":
        src_element.set_property("num-buffers", default_buffers)

    if fakesink != None:
        last_element.unlink(fakesink)
        pipeline.remove(fakesink)

    return format


def make_element(config, property=None, caps=None):
    """
    Make a GST Element and set property and caps
    Args:
        name: factory name of the element
        property: property of the element if any
        caps: capsfilter if any
    """
    if type(config) is str:
        element = Gst.ElementFactory.make(config)
    else:
        if not config or "element" not in config or config["element"] == None:
            print("[ERROR] Element cannot be NULL. Please check plugins_map file.")
            sys.exit()
        element = Gst.ElementFactory.make(config["element"])

    if not element:
        if type(config) is str:
            print("[ERROR] %s is not a gstreamer element" % config)
        else:
            print("[ERROR] %s is not a gstreamer element" % config["element"])
        sys.exit()

    if property != None:
        for prop_name, prop_value in property.items():
            element.set_property(prop_name, prop_value)
        property.clear()

    if caps != None:
        caps = Gst.caps_from_string(caps)
        caps_filter = Gst.ElementFactory.make("capsfilter")
        caps_filter.set_property("caps", caps)
        return [element, caps_filter]

    return [element]


def link_elements(element1, element2):
    """
    This function links two gstreamer element.
    Raises an error if linking fails.
    """
    try:
        element1.link(element2)
    except:
        print(
            "[ERROR] Could'nt link %s to %s"
            % (element1.get_name(), element2.get_name())
        )
        sys.exit()


def on_new_src_pad_added(element, new_pad, peer_element):
    """
    Callback function for linking elements with sometimes source pads
    Args:
        element: GstElement
        new_pad: GstPad
        peer_element: GstElement to link to
    """
    peer_sink_pad = peer_element.get_static_pad("sink")
    if peer_sink_pad.is_linked():
        return
    else:
        if not (new_pad.is_linked()):
            if peer_sink_pad.is_linked():
                peer_sink_pad.get_peer().unlink(peer_sink_pad)

            if not (new_pad.link(peer_sink_pad)):
                peer_sink_pad.set_active(True)

            else:
                new_pad.set_active(True)
    return


def add_and_link(elements_list, player=None):
    """
    Function to add multiple gst element to a player and link them
    Args:
        elements_list: list of GstElement to link
        player: GstPipeline
    """
    if player == None:
        player = Gst.Pipeline()

    if (
        get_pad_info(elements_list[-1].get_factory(), "src", "presence")
        == Gst.PadPresence.SOMETIMES
    ):
        elements_list += make_element("identity")

    for elem in elements_list:
        player.add(elem)

    for i in range(len(elements_list) - 1):
        link_elements(elements_list[i], elements_list[i + 1])
        # Check if sometimes pad (Example in case of demux)
        if (
            get_pad_info(elements_list[i].get_factory(), "src", "presence")
            == Gst.PadPresence.SOMETIMES
        ):
            elements_list[i].connect(
                "pad-added", on_new_src_pad_added, elements_list[i + 1]
            )

    return player


def get_input_elements(input):
    """
    Construct the list of gst input elements
    Args:
        input: input configuration
    """
    input_element_list = []
    image_fmt = {".jpg": "jpeg", ".png": "png"}
    image_dec = {".jpg": "jpegdec", ".png": "pngdec"}
    video_ext = {
        ".mp4": "qtdemux",
        ".mov": "qtdemux",
        ".avi": "avidemux",
        ".mkv": "matroskademux",
    }

    video_dec = {
        "h264": [["h264parse", None, None]],  # [Name,property,caps]
        "h265": [["h265parse", None, None]],
        "auto": [["decodebin", None, None]],
    }

    # Add decoder and caps if defined
    if gst_element_map["h264dec"]["element"] == "v4l2h264dec":
        property = {}
        if "property" in gst_element_map["h264dec"]:
            if "capture-io-mode" in gst_element_map["h264dec"]["property"]:
                property["capture-io-mode"] = \
                            gst_element_map["h264dec"]["property"]["capture-io-mode"]
        video_dec["h264"].append(
            [gst_element_map["h264dec"]["element"], property, None]
        )
        property = {"pool-size": 12}
        caps = "video/x-raw, format=NV12"
        video_dec["h264"].append(["tiovxmemalloc", property, caps])
    else:
        video_dec["h264"].append([gst_element_map["h264dec"]["element"], None, None])

    if gst_element_map["h265dec"]["element"] == "v4l2h265dec":
        property = {}
        if "property" in gst_element_map["h265dec"]:
            if "capture-io-mode" in gst_element_map["h265dec"]["property"]:
                property["capture-io-mode"] = \
                            gst_element_map["h265dec"]["property"]["capture-io-mode"]
        video_dec["h265"].append(
            [gst_element_map["h265dec"]["element"], property, None]
        )
        property = {"pool-size": 12}
        caps = "video/x-raw, format=NV12"
        video_dec["h265"].append(["tiovxmemalloc", property, caps])
    else:
        video_dec["h265"].append([gst_element_map["h265dec"]["element"], None, None])

    source_ext = os.path.splitext(input.source)[1]
    status = 0
    stop_index = -1
    if input.source.startswith("/dev/video"):
        if not os.path.exists(input.source):
            status = "no file"
        source = "camera"
    elif input.source.startswith("http"):
        if source_ext not in video_ext:
            status = "fmt err"
        source = "http"
    elif input.source.startswith("rtsp"):
        source = "rtsp"
    elif os.path.isfile(input.source):
        if (source_ext == ".h264" or source_ext == ".h265"):
            source = 'raw_video'
            stop_index = 0
        elif source_ext in video_ext:
            source = "video"
        elif source_ext in image_dec:
            source = "image"
            stop_index = 0
        else:
            status = "fmt err"
    elif "%" in input.source:
        if not os.path.exists(input.source % input.index):
            status = "no file"
            input.source = input.source % input.index
        elif not (source_ext in image_dec):
            status = "fmt err"
        else:
            source = "image"
    elif input.source == "videotestsrc":
        source = "videotestsrc"
    else:
        status = "no file"

    if status:
        if status == "fmt err":
            print("Invalid Input Format")
            print("Supported Image input formats : ", [i for i in image_dec.keys()])
            print("Supported video input formats : ", [i for i in video_ext.keys()])
        else:
            print("Invalid Input")
            print('"', input.source, "\" doesn't exist")
        sys.exit(1)

    source_name = "source0"

    if source == "camera":

        if input.format == "jpeg":

            property = {"device": input.source, "name": source_name}
            caps = "image/jpeg, width=%d, height=%d" % (input.width, input.height)
            element = make_element("v4l2src", property=property, caps=caps)
            input_element_list += element

            element = make_element("jpegdec")
            input_element_list += element

        elif input.format.startswith("rggb") or input.format.startswith("bggi"):
            property = {"device": input.source, "io-mode": 5, "name": source_name}
            element = make_element("v4l2src", property=property)
            input_element_list += element
            property = {"leaky": 2}
            caps = "video/x-bayer, width=%d, height=%d, format=%s" % (
                input.width,
                input.height,
                input.format,
            )
            element = make_element("queue", property=property, caps=caps)
            input_element_list += element

            if input.sen_id == "imx219":
                sen_name = "SENSOR_SONY_IMX219_RPI"
                format_msb = 7
            elif input.sen_id == "imx390":
                sen_name = "SENSOR_SONY_IMX390_UB953_D3"
                format_msb = 11
            elif input.sen_id == "ov2312":
                sen_name = "SENSOR_OV2312_UB953_LI"
                format_msb = 9
            # TODO - Take sensor name and subdev as params
            property = {
                "sensor-name": sen_name,
                "dcc-isp-file": "/opt/imaging/%s/linear/dcc_viss.bin" % input.sen_id,
                "format-msb": format_msb,
            }

            global isp_target_idx
            if "property" in gst_element_map["isp"]:
                if "target" in gst_element_map["isp"]["property"]:
                    property["target"] = gst_element_map["isp"]["property"]["target"][isp_target_idx]
                    isp_target_idx += 1
                    if isp_target_idx >= len(gst_element_map["isp"]["property"]["target"]):
                        isp_target_idx = 0

            caps = "video/x-raw, format=NV12"
            element = make_element(gst_element_map["isp"], property=property, caps=caps)
            input_element_list += element
            if input.ldc:
                property = {
                    "sensor-name": sen_name,
                    "dcc-file": "/opt/imaging/%s/linear/dcc_ldc.bin" % input.sen_id,
                }

                global ldc_target_idx
                if "property" in gst_element_map["ldc"]:
                    if "target" in gst_element_map["ldc"]["property"]:
                        property["target"] = gst_element_map["ldc"]["property"]["target"][ldc_target_idx]
                        ldc_target_idx += 1
                        if ldc_target_idx >= len(gst_element_map["ldc"]["property"]["target"]):
                            ldc_target_idx = 0

                caps = "video/x-raw, format=NV12, width=1920, height=1080"
                element = make_element(
                    gst_element_map["ldc"], property=property, caps=caps
                )
                input_element_list += element
                input.width = 1920
                input.height = 1080

        else:
            property = {"device": input.source, "name": source_name}
            caps = "video/x-raw, width=%d, height=%d" % (input.width, input.height)
            element = make_element("v4l2src", property=property, caps=caps)
            input_element_list += element

    elif source == "http":
        if not (input.format in video_dec):
            input.format = "auto"
        property = {"location": input.source, "name": source_name}
        proxy = os.getenv("http_proxy", default=None)
        if proxy:
            property["proxy"] = proxy

        element = make_element("souphttpsrc", property=property)
        input_element_list += element

        element = make_element(video_ext[source_ext])
        input_element_list += element

        for i in video_dec[input.format]:
            element = make_element(i[0], property=i[1], caps=i[2])
            input_element_list += element

    elif source == "rtsp":
        property = {
            "location": input.source,
            "latency": 0,
            "buffer-mode": 3,
            "name": source_name,
        }
        element = make_element("rtspsrc", property=property)
        input_element_list += element
        element = make_element("rtph264depay")
        input_element_list += element
        for i in video_dec["h264"]:
            element = make_element(i[0], property=i[1], caps=i[2])
            input_element_list += element

    elif source == "image":
        property = {
            "location": input.source,
            "index": input.index,
            "stop-index": stop_index,
            "name": source_name,
        }

        if input.loop == True:
            property["loop"] = True

        caps_string = "image/" + image_fmt[source_ext] + ",framerate=%s" % (input.fps)
        property["caps"] = Gst.caps_from_string(caps_string)
        element = make_element("multifilesrc", property=property)
        input_element_list += element

        element = make_element(image_dec[source_ext])
        input_element_list += element

        caps = "video/x-raw, width=%d, height=%d" % (input.width, input.height)
        element = make_element("videoscale", caps=caps)
        input_element_list += element

    if source == "raw_video":
        if not (input.format in video_dec):
            input.format = "auto"
        property = {
            "location": input.source,
            "stop-index": stop_index,
            "name": source_name,
        }
        if input.loop == True:
            property["loop"] = True

        #Set caps only in case of hardware decoder
        if ((input.format == "h264" and gst_element_map["h264dec"]["element"] == "v4l2h264dec") or
            (input.format == "h265" and gst_element_map["h264dec"]["element"] == "v4l2h264dec")):
            caps_string = "video/x-" + input.format
            caps_string += ",width=%d,height=%d,framerate=%s" % (input.width,input.height,input.fps)
            property["caps"] = Gst.caps_from_string(caps_string)
        element = make_element("multifilesrc", property=property)
        input_element_list += element
        for i in video_dec[input.format]:
            input_element_list += make_element(i[0], property=i[1], caps=i[2])


    elif source == "video":
        if not (input.format in video_dec):
            input.format = "auto"

        property = {"location": input.source, "name": source_name}
        element = make_element("filesrc", property=property)
        input_element_list += element

        element = make_element(video_ext[source_ext])
        input_element_list += element

        for i in video_dec[input.format]:
            input_element_list += make_element(i[0], property=i[1], caps=i[2])

    elif source == "videotestsrc":
        property = {"pattern": input.pattern, "name": source_name}
        if input.format == "auto":
            input.format = "NV12"
        caps = "video/x-raw, width=%d, height=%d, format=%s" % (
            input.width,
            input.height,
            input.format,
        )
        element = make_element("videotestsrc", property=property, caps=caps)
        input_element_list += element

    return input_element_list


def get_scaler_elements(flow, is_multi_src):
    """
    Construct the list of scaler element

    It returns list in this format:
    [[Multiscaler is present],
     [first few element in sensor path],
     [first few element in dl path]]

    If multisrc -> [[Multiscaler],[queue,capsfilter],[queue,capsfilter,...]]
    If not ->      [[queue,videoscale,capsfilter],[queue,videoscale,capsfilter]]

    Args:
        input: input configuration
        is_multi_src: Does the scaler element used supports multiple src pads
    """
    pipe = []
    sensor_list, dl_list = [], []
    sensor_scaler_caps = "video/x-raw, width=%d, height=%d" % (
        flow.sensor_width,
        flow.sensor_height,
    )
    if is_multi_src == False:
        sensor_list += make_element("queue")  # Sensor_Path
        sensor_list += make_element(gst_element_map["scaler"], caps=sensor_scaler_caps)
        dl_list += make_element("queue")  # DL_PATH
        dl_list += get_dl_scaler_elements(flow, is_multi_src=False)

    else:
        element = make_element(
            gst_element_map["scaler"],
            property={"name": flow.gst_scaler_name},
        )
        pipe += element
        sensor_list += make_element("queue", caps=sensor_scaler_caps)
        dl_list = get_dl_scaler_elements(flow, is_multi_src)

    pipe.append(sensor_list)
    pipe.append(dl_list)

    return pipe


def get_dl_scaler_elements(flow, is_multi_src):
    """
    Construct the list of scaler element for dl path
    Args:
        input: input configuration
        is_multi_src: Does the scaler element used supports multiple src pads
    """
    resize = flow.pre_proc_resize
    dl_scaler_caps = "video/x-raw, width=%d, height=%d" % tuple(resize)
    scale_element = None

    if is_multi_src == False:
        element = make_element(gst_element_map["scaler"], caps=dl_scaler_caps)
        return element

    # tiovxmultiscaler dose not support upscaling and downscaling with scaling
    # factor < 1/4, So use "videoscale" insted
    else:
        if (
            float(flow.input.width) / resize[0] > 4
            or float(flow.input.height) / resize[1] > 4
        ):
            # width = max(flow.input.width // 4, resize[0])
            # height = max(flow.input.height // 4, resize[1])
            width = (flow.input.width + resize[0]) // 2
            height = (flow.input.height + resize[1]) // 2

            if width % 2 != 0:
                width += 1
            if height % 2 != 0:
                height += 1

            caps = "video/x-raw, width=%d, height=%d" % (width, height)

            queue_element = make_element("queue", caps=caps)
            scale_element = make_element(
                gst_element_map["scaler"], property={"target": 1}, caps=dl_scaler_caps
            )

        elif flow.input.width / resize[0] < 1 or flow.input.height / resize[1] < 1:
            caps = "video/x-raw, width=%d, height=%d" % (
                flow.input.width,
                flow.input.height,
            )
            queue_element = make_element("queue", caps=caps)
            scale_element = make_element("videoscale", caps=dl_scaler_caps)

        else:
            queue_element = make_element("queue", caps=dl_scaler_caps)

        elem_list = queue_element

        if scale_element != None:
            elem_list += scale_element

        return elem_list


def get_output_elements(output):
    """
    Construct the list of gst output elements
    Args:
        output: output configuration
    """

    prop_str = "video_bitrate=%d,video_gop_size=%d" \
                                              % (output.bitrate,output.gop_size)
    enc_extra_ctrl = "controls,frame_level_rate_control_enable=1," + prop_str

    video_enc = {
        ".mov": [
            ["h264parse", None],
            ["qtmux", None],
        ],
        ".mp4": [
            ["h264parse", None],
            ["mp4mux", None],
        ],
        ".mkv": [
            ["h264parse", None],
            ["matroskamux", None],
        ],
    }

    sink_elements = []
    bg_elements = []
    mosaic_elements = []

    if output.overlay_perf_type != None:
        sink_elements += make_element("queue")
        property = {"title":output.title,
                    "overlay-type":output.overlay_perf_type}
        sink_elements += make_element("tiperfoverlay",property=property)

    sink_ext = os.path.splitext(output.sink)[1]
    status = 0
    if output.sink == "kmssink":
        sink = "display"
    elif output.sink == "remote":
        sink = "remote"
    elif os.path.isdir(os.path.dirname(output.sink)) or not os.path.dirname(
        output.sink
    ):
        if sink_ext in video_enc:
            sink = "video"
        elif sink_ext == ".jpg":
            sink = "image"
        else:
            sink = "others"
    else:
        sink = "others"

    sink_name = "sink%d" % (output.id)

    if sink == "display":
        property = {"sync": False, "driver-name": "tidss", "name": sink_name, "force-modesetting": True}
        if output.connector:
            property["connector-id"] = output.connector
        sink_elements += make_element("kmssink", property=property)

    elif sink == "image":
        sink_elements += make_element(gst_element_map["jpegenc"])
        sink_elements += make_element(
            "multifilesink", property={"location": output.sink, "name": sink_name}
        )

    elif sink == "video":
        property = {}
        if (gst_element_map["h264enc"]["element"] == "v4l2h264enc"):
            property = {"extra-controls": Gst.Structure.from_string(enc_extra_ctrl)[0]}

        sink_elements += make_element(gst_element_map["h264enc"], property=property)

        for i in video_enc[sink_ext]:
            sink_elements += make_element(i[0], property=i[1])

        property={"location": output.sink, "name": sink_name}
        sink_elements += make_element("filesink", property=property)

    elif sink == "remote":
        property = {}

        # MP4 or H264 encoding
        if output.encoding == "mp4" or output.encoding == "h264":
            if (gst_element_map["h264enc"]["element"] == "v4l2h264enc"):
                property = {"extra-controls": Gst.Structure.from_string(enc_extra_ctrl)[0]}

            sink_elements += make_element(gst_element_map["h264enc"], property=property)

            sink_elements += make_element("h264parse")

            if output.encoding == "mp4":
                property = {"fragment-duration":1}
                sink_elements += make_element("mp4mux", property=property)
            elif output.encoding == "h264":
                sink_elements += make_element("rtph264pay")

        # Jpeg encoding
        elif output.encoding == "jpeg":

            sink_elements += make_element(gst_element_map["jpegenc"])

            property = {"boundary":"spionisto"}
            sink_elements += make_element("multipartmux",property=property)

            property = {"max":65000}
            sink_elements += make_element("rndbuffersize", property=property)

        else:
            print("[ERROR] Wrong encoding [%s] defined for remote output.", output.encoding)
            sys.exit()

        property = {
            "host": output.host,
            "port": output.port,
            "sync": False,
            "name": sink_name,
        }
        sink_elements += make_element("udpsink", property=property)

    elif sink == "others":
        sink_elements += make_element(output.sink, property={"name": sink_name})

    if output.mosaic:
        property = {
            "format": 3,
            "block": True,
            "num-buffers": 1,
            "name": output.gst_bkgnd_sink_name,
        }

        bg_elements += make_element("appsrc", property=property)

        caps = "video/x-raw,format=NV12"

        bg_elements += make_element(gst_element_map["dlcolorconvert"], caps=caps)

        bg_elements += make_element("queue")
        property = {"location": "/tmp/" + output.gst_bkgnd_sink_name}
        bg_elements += make_element("filesink", property=property)

        background = "/tmp/" + output.gst_bkgnd_sink_name
        property = {
            "name": "mosaic_" + str(output.id),
            "background": background,
        }

        if gst_element_map["mosaic"]["element"] == "tiovxmosaic":
            property["target"] = 1

        caps = "video/x-raw,format=NV12, width=%d, height=%d" % (
            output.width,
            output.height,
        )
        mosaic_elements += make_element(
            gst_element_map["mosaic"], property=property, caps=caps
        )
    return bg_elements, mosaic_elements, sink_elements


def get_pre_proc_elements(flow):
    """
    Construct the list of gst elements for pre-process
    Args:
        flow: flow configuration
    """
    global preproc_target_idx
    pre_proc_element_list = []

    if flow.model.task_type == "classification":
        left = (flow.pre_proc_resize[0] - flow.model.crop[0]) // 2
        right = flow.pre_proc_resize[0] - flow.model.crop[0] - left
        top = (flow.pre_proc_resize[1] - flow.model.crop[1]) // 2
        bottom = flow.pre_proc_resize[1] - flow.model.crop[1] - top
        property = {"left": left, "right": right, "top": top, "bottom": bottom}
        element = make_element("videobox", property=property)
        pre_proc_element_list += element

    layout = 0 if flow.model.data_layout == "NCHW" else 1
    tensor_fmt = "bgr" if (flow.model.reverse_channels) else "rgb"

    if flow.model.input_tensor_types[0] == np.int8:
        data_type = 2
    elif flow.model.input_tensor_types[0] == np.uint8:
        data_type = 3
    elif flow.model.input_tensor_types[0] == np.int16:
        data_type = 4
    elif flow.model.input_tensor_types[0] == np.uint16:
        data_type = 5
    elif flow.model.input_tensor_types[0] == np.int32:
        data_type = 6
    elif flow.model.input_tensor_types[0] == np.uint32:
        data_type = 7
    elif flow.model.input_tensor_types[0] == np.float32:
        data_type = 10
    else:
        print("[ERROR] Unsupported data type for input tensor")
        sys.exit(1)

    property = {}

    if gst_element_map["dlpreproc"]:
        property = {
            "data-type": data_type,
            "channel-order": layout,
        }

        if flow.model.mean:
            property["mean-0"], property["mean-1"], property["mean-2"] = tuple(
                flow.model.mean
            )

        if flow.model.scale:
            property["scale-0"], property["scale-1"], property["scale-2"] = tuple(
                flow.model.scale
            )

        property["tensor-format"] = tensor_fmt
  
        if "property" in gst_element_map["dlpreproc"]:
            if "target" in gst_element_map["dlpreproc"]["property"]:
                property["target"] = gst_element_map["dlpreproc"]["property"]["target"][preproc_target_idx]
                preproc_target_idx += 1
                if preproc_target_idx >= len(gst_element_map["dlpreproc"]["property"]["target"]):
                    preproc_target_idx = 0

            if "out-pool-size" in gst_element_map["dlpreproc"]["property"]:
                property["out-pool-size"] = gst_element_map["dlpreproc"]["property"][
                    "out-pool-size"
                ]

        caps = "application/x-tensor-tiovx"

        element = make_element(
            gst_element_map["dlpreproc"], property=property, caps=caps
        )
        pre_proc_element_list += element

    max_app_sink_buffer = 2
    if "out-pool-size" in property:
        max_app_sink_buffer = max(2, property["out-pool-size"] - 2)
    property = {"name": flow.gst_pre_src_name, "max-buffers": max_app_sink_buffer}
    if flow.input.drop == True:
        property["drop"] = True

    element = make_element("appsink", property=property)
    pre_proc_element_list += element

    return pre_proc_element_list


def get_sensor_elements(flow):
    """
    Construct the list of gst elements for sensor input
    Args:
        flow: flow configuration
    """
    max_app_sink_buffer = 2
    if "property" in gst_element_map["dlcolorconvert"]:
        if "out-pool-size" in gst_element_map["dlcolorconvert"]["property"]:
            max_app_sink_buffer = max(
                2, gst_element_map["dlcolorconvert"]["property"]["out-pool-size"] - 2
            )

    property = {"name": flow.gst_sen_src_name, "max-buffers": max_app_sink_buffer}
    if flow.input.drop == True:
        property["drop"] = True
    sen_elem_list = make_element("appsink", property=property)

    return sen_elem_list


def get_post_proc_elements(flow):
    """
    Construct the list of gst elements for post-processing
    Args:
        flow: flow configuration
    """
    post_proc_elements = []
    property = {
        "format": 3,
        #    "is-live": True,
        "block": True,
        "do-timestamp": True,
        "name": flow.gst_post_sink_name,
    }
    element = make_element("appsrc", property=property)
    post_proc_elements += element

    caps = "video/x-raw, format=NV12, width=%d, height=%d" % (
        flow.sensor_width,
        flow.sensor_height,
    )
    element = make_element(gst_element_map["dlcolorconvert"], caps=caps)
    post_proc_elements += element

    if len(flow.outputs) > 1:
        tee_name = "output_tee_split%d" % (flow.id)
        element = make_element("tee", property={"name": tee_name})
        post_proc_elements += element

    return post_proc_elements


def get_color_convert_config(input_format, output_format):
    """
    Helper function to give appropriate colorconvert element
    based on plugins available and inputs and outputs can
    be supported
    Args:
        input_format: Input format
        output_format: Output format
    """
    tiovxdlcc_combimations = {
        "NV12": ["RGB", "I420"],
        "NV21": ["RGB", "I420"],
        "RGB": ["NV12"],
        "I420": ["NV12"],
        "UYVY": ["NV12"],
        "YUY2": ["NV12"],
        "GRAY8": ["NV12"]
    }

    dl_color_convert_element_factory = Gst.ElementFactory.find(
        gst_element_map["dlcolorconvert"]["element"]
    )
    color_convert_element_factory = Gst.ElementFactory.find(
        gst_element_map["colorconvert"]["element"]
    )
    video_convert_element_factory = Gst.ElementFactory.find("videoconvert")

    dlcc_sink_list = get_pad_format(dl_color_convert_element_factory, "sink")
    cc_sink_list = get_pad_format(color_convert_element_factory, "sink")
    vc_sink_list = get_pad_format(video_convert_element_factory, "sink")

    dlcc_src_list = get_pad_format(dl_color_convert_element_factory, "src")
    cc_src_list = get_pad_format(color_convert_element_factory, "src")
    vc_src_list = get_pad_format(video_convert_element_factory, "src")

    if input_format in dlcc_sink_list and output_format in dlcc_src_list:
        if dl_color_convert_element_factory.get_name() == "tiovxdlcolorconvert":
            # Check combination
            if output_format.upper() in tiovxdlcc_combimations[input_format.upper()]:
                return gst_element_map["dlcolorconvert"]
        else:
            return gst_element_map["dlcolorconvert"]

    if input_format in cc_sink_list and output_format in cc_src_list:
        return gst_element_map["colorconvert"]

    if input_format == 1 or (
        input_format in vc_sink_list and output_format in vc_src_list
    ):
        return {"element": "videoconvert"}

    print(
        "[ERROR] %s->%s not supported by available colorconvert elements."
        % (input_format, output_format)
    )
    sys.exit(1)


def get_gst_pipe(flows, outputs):
    """
    Construct the src and sink pipelines.
    This function connects the input,scaler,sensor and dl paths and adds
    appropriate color convert when connecting the if necessary.
    This also constructs the sink pipeline.
    Args:
        flows: List of flows
        outputs: List of outputs
    """

    scaler_element_factory = Gst.ElementFactory.find(
        gst_element_map["scaler"]["element"]
    )
    scaler_format_list = get_pad_format(scaler_element_factory, "sink")

    dl_color_convert_element_factory = Gst.ElementFactory.find(
        gst_element_map["dlcolorconvert"]["element"]
    )
    dl_color_convert_format_list = get_pad_format(
        dl_color_convert_element_factory, "sink"
    )

    color_convert_element_factory = Gst.ElementFactory.find(
        gst_element_map["colorconvert"]["element"]
    )
    color_convert_format_list = get_pad_format(color_convert_element_factory, "sink")

    src_players = []
    sink_player = None

    for index, f in enumerate(flows):
        # ====================== SOURCE ===========================

        # ========================= INPUT =========================
        gst_player = add_and_link(f.input.gst_inp_elements)

        # Handle TIOVXISP
        # sink property are exposed only once element is added to bin and linked
        for elem in f.input.gst_inp_elements:
            if elem.get_factory().get_name() == "tiovxisp":
                dcc_2a_file = "/opt/imaging/%s/linear/dcc_2a.bin" % f.input.sen_id
                Gst.ChildProxy.set_property(elem, "sink_0::dcc-2a-file", dcc_2a_file)
                if not f.input.format.startswith("bggi"):
                    Gst.ChildProxy.set_property(elem, "sink_0::device", f.input.subdev_id)

        # Get format of last input element after caps negotiation
        input_format = get_format(gst_player, f.input.gst_inp_elements)
        if not input_format:
            last_element_index = len(f.input.gst_inp_elements) - 1
            while (
                last_element_index > 0
                and f.input.gst_inp_elements[last_element_index]
                .get_factory()
                .get_name()
                == "capsfilter"
            ):
                last_element_index -= 1
            input_format = get_pad_format(
                f.input.gst_inp_elements[last_element_index].get_factory(), "src"
            )
            if input_format != 1:
                input_format = input_format[0]

        # Add color convert if input format isnt supported by scaler
        if input_format not in scaler_format_list:
            # Assuming that colorconvert supports NV12 on srcpad
            color_convert_element = get_color_convert_config(input_format, "NV12")

            caps = "video/x-raw, format=NV12"
            element = make_element(color_convert_element, caps=caps)
            gst_player = add_and_link(element, player=gst_player)
            # Link last element of inp pipe to colorconvert
            link_elements(f.input.gst_inp_elements[-1], element[0])
            f.input.gst_inp_elements += element
            input_format = "NV12"

        last_inp_element = f.input.gst_inp_elements[-1]
        # =========================================================

        # ========================= SCALER ========================
        # Add tee element if not multiscaler or subflows > 2 since tiovxmultiscaler only supports upto 4 srcs (actually 5)
        if (
            not f.is_multi_scaler or len(f.sub_flows) > 1
        ):  # Change to > 2 if you want to give upto 4 inp to MS
            name = "tee_split%d" % f.input.id
            property = {"name": name}
            element = make_element("tee", property=property)
            gst_player = add_and_link(element, player=gst_player)
            # Link last element of inp (Can be colorcvt) to tee
            link_elements(last_inp_element, element[0])
            last_inp_element = element[-1]
        # =========================================================

        # ======================== SUBFLOW ========================
        for s_index, s in enumerate(f.sub_flows):
            # ====================== DL-PATH ======================
            expected_end_format = "RGB"
            dl = s.gst_scaler_elements.pop()
            pre_proc_elem_factory = s.gst_pre_proc_elements[0].get_factory()
            pre_proc_elem_format = get_pad_format(pre_proc_elem_factory, "sink")
            subflow_format = input_format

            # get_pad_format returns 1 in case if element supports any format (For Example: Appsink)
            if pre_proc_elem_format == 1 and subflow_format != expected_end_format:
                # Add colorconvert
                color_convert_element = get_color_convert_config(
                    subflow_format, expected_end_format
                )

                caps = "video/x-raw, format=%s" % expected_end_format
                property = {}
                if "property" in color_convert_element:
                    prop = color_convert_element["property"]
                    if "out-pool-size" in prop:
                        property["out-pool-size"] = prop["out-pool-size"]

                dl += make_element(
                    color_convert_element,
                    property=property,
                    caps=caps,
                )
                subflow_format = expected_end_format

            # If caps is not any and the input_format is not supported by first element in pre_proc_element_list
            elif (
                pre_proc_elem_format != 1 and subflow_format not in pre_proc_elem_format
            ):
                common_formats = set(pre_proc_elem_format)
                # choose best_format and make element
                best_guess = [expected_end_format, "NV12", "NV21", "I420"]
                flag_format = None
                for i in best_guess:
                    if i in common_formats:
                        flag_format = i
                        break
                if not flag_format:
                    print(
                        "[ERROR] %s does not support ['%s' , 'NV12', 'NV21', 'I420']"
                        % (expected_end_format, pre_proc_elem_factory.get_name())
                    )
                    sys.exit(1)

                color_convert_element = get_color_convert_config(
                    subflow_format, flag_format
                )

                caps = "video/x-raw, format=%s" % flag_format
                property = {}
                if "property" in color_convert_element:
                    prop = color_convert_element["property"]
                    if "out-pool-size" in prop:
                        property["out-pool-size"] = prop["out-pool-size"]

                dl += make_element(
                    color_convert_element,
                    property=property,
                    caps=caps,
                )
                subflow_format = flag_format

            # Put everythin in pre_proc_element list except appsink
            dl += s.gst_pre_proc_elements[:-1]
            gst_player = add_and_link(dl, player=gst_player)
            last_dl_element = dl[-1]
            last_dl_element_caps = get_caps(last_dl_element, "sink")
            latest_format = None
            if last_dl_element_caps and last_dl_element_caps.get_size() > 0:
                latest_format = last_dl_element_caps.get_structure(0).get_name()
            if latest_format != "application/x-tensor-tiovx":
                latest_format = subflow_format  # This isnt tested xD
                if latest_format != expected_end_format:
                    # Add colorconvert
                    color_convert_element = get_color_convert_config(
                        latest_format, expected_end_format
                    )

                    caps = "video/x-raw, format=%s" % expected_end_format
                    property = {}
                    if "property" in color_convert_element:
                        prop = color_convert_element["property"]
                        if "out-pool-size" in prop:
                            property["out-pool-size"] = prop["out-pool-size"]

                    colorconvert_element = make_element(
                        color_convert_element,
                        property=property,
                        caps=caps,
                    )
                    gst_player = add_and_link(colorconvert_element, player=gst_player)
                    # Link last element in dl path before appsink to colorconvert
                    # and ultimately link colorcvt to appsink
                    link_elements(last_dl_element, colorconvert_element[0])
                    last_dl_element = colorconvert_element[-1]
                    dl += colorconvert_element

            dl_appsink = s.gst_pre_proc_elements[-1]
            gst_player.add(dl_appsink)
            # Link last element in dl path (Can be Colorcvt) to appsink
            link_elements(last_dl_element, dl_appsink)
            dl.append(dl_appsink)
            # =========================================================
            # ====================== SENSOR ===========================

            sensor = s.gst_scaler_elements.pop()
            if input_format != "RGB":
                # Add colorconvert
                color_convert_element = get_color_convert_config(input_format, "RGB")

                property = {}
                if "property" in color_convert_element:
                    if "target" in color_convert_element["property"]:
                        property["target"] = color_convert_element["property"][
                            "target"
                        ][-1]
                    if "out-pool-size" in color_convert_element["property"]:
                        property["out-pool-size"] = color_convert_element["property"][
                            "out-pool-size"
                        ]
                # Assuming that colorconvert supports RGB
                caps = "video/x-raw,format=RGB"
                sensor += make_element(
                    color_convert_element,
                    property=property,
                    caps=caps,
                )

            sensor += s.gst_sensor_elements
            gst_player = add_and_link(sensor, player=gst_player)
            # =========================================================

            if s.flow.is_multi_scaler == False:
                """
                No multiscaler element
                Connect last element in input path (tee in this case)
                to dirst element in sensor and dl path
                """

                link_elements(last_inp_element, sensor[0])
                link_elements(last_inp_element, dl[0])
            else:
                if len(f.sub_flows) > 1:
                    """
                    Add queue before tiovxmultiscaler only when it connects
                    to tee before it. Tee element will only be present when
                    theres two multiscaler needed i.e when there are more
                    than 2 subflows
                    """
                    queue_element = make_element("queue")
                    gst_scaler_elements = queue_element + s.gst_scaler_elements
                else:
                    gst_scaler_elements = s.gst_scaler_elements

                gst_player = add_and_link(gst_scaler_elements, player=gst_player)

                link_elements(last_inp_element, gst_scaler_elements[0])
                link_elements(gst_scaler_elements[-1], sensor[0])
                link_elements(gst_scaler_elements[-1], dl[0])

        src_players.append(gst_player)

        # ====================== SINK ===========================
        for s_index, s in enumerate(f.sub_flows):
            sink_player = add_and_link(s.gst_post_proc_elements, player=sink_player)
            for index, o in enumerate(s.outputs):
                if o.mosaic:
                    queue_element = make_element("queue")
                    sink_player = add_and_link(queue_element, player=sink_player)
                    link_elements(s.gst_post_proc_elements[-1], queue_element[0])

                    mosaic = o.gst_mosaic_elements[0]
                    mosaic_name = mosaic.get_name()
                    # Skip adding to bin if mosaic is alread added and linked
                    if not o.mosaic_added_to_bin:
                        o.mosaic_added_to_bin = True
                        o.mosaic_prop[mosaic_name] = []
                        sink_player = add_and_link(
                            o.gst_mosaic_elements, player=sink_player
                        )

                    link_elements(queue_element[-1], mosaic)

                    mosaic_x = s.mosaic_info[index][0]
                    mosaic_y = s.mosaic_info[index][1]
                    mosaic_w = s.mosaic_info[index][2]
                    mosaic_h = s.mosaic_info[index][3]

                    o.mosaic_prop[mosaic_name].append(
                        (mosaic_x, mosaic_y, mosaic_w, mosaic_h)
                    )

                    # Set Mosaic Property
                    if gst_element_map["mosaic"]["element"] == "tiovxmosaic":
                        startx = GObject.ValueArray()
                        startx.append(GObject.Value(GObject.TYPE_INT, mosaic_x))
                        starty = GObject.ValueArray()
                        starty.append(GObject.Value(GObject.TYPE_INT, mosaic_y))
                        widths = GObject.ValueArray()
                        widths.append(GObject.Value(GObject.TYPE_INT, mosaic_w))
                        heights = GObject.ValueArray()
                        heights.append(GObject.Value(GObject.TYPE_INT, mosaic_h))
                        Gst.ChildProxy.set_property(
                            mosaic, "sink_%d::widths" % o.num_mosaic_sink, widths
                        )
                        Gst.ChildProxy.set_property(
                            mosaic, "sink_%d::heights" % o.num_mosaic_sink, heights
                        )

                    else:
                        startx = GObject.Value(GObject.TYPE_INT, mosaic_x)
                        starty = GObject.Value(GObject.TYPE_INT, mosaic_y)
                        width = GObject.Value(GObject.TYPE_INT, mosaic_w)
                        height = GObject.Value(GObject.TYPE_INT, mosaic_h)
                        Gst.ChildProxy.set_property(
                            mosaic, "sink_%d::width" % o.num_mosaic_sink, width
                        )
                        Gst.ChildProxy.set_property(
                            mosaic, "sink_%d::height" % o.num_mosaic_sink, height
                        )

                    Gst.ChildProxy.set_property(
                        mosaic, "sink_%d::startx" % o.num_mosaic_sink, startx
                    )
                    Gst.ChildProxy.set_property(
                        mosaic, "sink_%d::starty" % o.num_mosaic_sink, starty
                    )

                    # Increase mosaic sink count for this output by 1
                    o.num_mosaic_sink += 1

                    if not o.disp_elements_added_to_bin:
                        o.disp_elements_added_to_bin = True
                        sink_player = add_and_link(
                            o.gst_disp_elements, player=sink_player
                        )
                    link_elements(o.gst_mosaic_elements[-1], o.gst_disp_elements[0])

                    if (o.overlay_perf_type != None
                        and
                        gst_element_map["mosaic"]["element"] == "tiovxmosaic"):
                        Gst.ChildProxy.set_property(mosaic, "src::pool-size", 4)

                else:
                    """
                    Use Scaler if expected output dimension does'nt match the
                    sensor path dimension of this subflow
                    """
                    if o.width != s.sensor_width or o.height != s.sensor_height:
                        scaler_caps = "video/x-raw, width=%d, height=%d" % (
                            o.width,
                            o.height,
                        )
                        if s.flow.is_multi_scaler:

                            """
                            Running these extra multiscalers on
                            target = 1 (where mosaic is also running).
                            If any issue with target,change in
                            get_dl_scaler_elements() as well.
                            """
                            scaler_element = []
                            if (
                                s.sensor_width / o.width > 4
                                or s.sensor_height / o.height > 4
                            ):
                                # width = max(s.sensor_width//4, o.width)
                                # height = max(s.sensor_height//4, o.height)
                                width = (s.sensor_width + o.width) // 2
                                height = (s.sensor_height + o.height) // 2
                                if width % 2 != 0:
                                    width += 1
                                if height % 2 != 0:
                                    height += 1

                                intermediate_caps = (
                                    "video/x-raw, width=%d, height=%d" % (width, height)
                                )

                                scaler_element = make_element(
                                    gst_element_map["scaler"],
                                    property={"target": 1},
                                    caps=intermediate_caps,
                                )

                            scaler_element += make_element(
                                gst_element_map["scaler"],
                                property={"target": 1},
                                caps=scaler_caps,
                            )
                        else:
                            scaler_element = make_element(
                                gst_element_map["scaler"], caps=scaler_caps
                            )
                        o.gst_disp_elements = scaler_element + o.gst_disp_elements

                    if len(s.outputs) > 1:
                        o.gst_disp_elements = (
                            make_element("queue") + o.gst_disp_elements
                        )

                    sink_player = add_and_link(o.gst_disp_elements, player=sink_player)
                    link_elements(s.gst_post_proc_elements[-1], o.gst_disp_elements[0])
    return src_players, sink_player
