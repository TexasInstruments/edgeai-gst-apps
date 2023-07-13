#  Copyright (C) 2021 Texas Instruments Incorporated - http://www.ti.com/
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

import gi

gi.require_version("Gst", "1.0")
gi.require_version("GstApp", "1.0")
from gi.repository import Gst, GstApp, GLib, GObject
from time import sleep, time
import threading
import curses
import signal
import sys
import argparse
import yaml
import os

report_list = []
print_stdout = False
stop_reporting_loop = False


class Parser(argparse.ArgumentParser):
    def error(self, message):
        sys.stderr.write("error: %s\n" % message)
        self.print_help()
        sys.exit(2)


def get_cmdline_args(sysv_args):
    """
    Helper function to parse command line arguments
    """
    global args
    help_str = "Run : " + sysv_args[0] + " -h for help"
    parser = Parser(usage=help_str, formatter_class=argparse.RawTextHelpFormatter)

    help_str_config = (
        "Path to demo config file\n"
        + "    ex: "
        + sysv_args[0]
        + " ../configs/app_config.yaml"
    )
    parser.add_argument("config", help=help_str_config)

    help_str_curses = "Disable curses report\n" + "default: Disabled"
    parser.add_argument(
        "-n", "--no-curses", help=help_str_curses, action="store_true", default=False
    )

    help_str_verbose = (
        "Verbose option to print profile info on stdout\n" + "default: Disabled"
    )
    parser.add_argument(
        "-v", "--verbose", help=help_str_verbose, action="store_true", default=False
    )

    help_str_dump_dot = (
        "Dump option to dump pipeline as dot file\n" + "default: Disabled"
    )
    parser.add_argument(
        "-d", "--dump-dot", help=help_str_dump_dot, action="store_true", default=False
    )

    args = parser.parse_args()
    return args


class Report:
    def __init__(self, flow):
        self._proctime = {}
        self._metrics = {}
        self.frame_count = 0
        self.start_time = 0
        self.flow = flow
        report_list.append(self)

    def report_proctime(self, tag, value):
        """
        Used for reporting the processing time values
        All the values with same tag are automatically averaged
        This information is used when printing the ncurses table

        Args:
            tag (string): unique tag to indicate specific processing entity
            value (float): Current measured processing time in microseconds
        """
        try:
            data = self._proctime[tag]
        except KeyError:
            self._proctime[tag] = (0.0, 0)
        finally:
            avg, n = self._proctime[tag]
            avg = (avg * n + value) / (n + 1)
            n = n + 1
            self._proctime[tag] = (avg, n)
            if print_stdout:
                print(
                    "[UTILS] [%s] Time for '%s': %5.2f ms (avg %5.2f ms)"
                    % (self.flow.model.model_name, tag, value * 1000, avg * 1000)
                )

    def report_frame(self):
        """
        Function to be called at the end of each frame
        used to calculate effective framerate
        """
        if not self.start_time:
            self.start_time = time()
            return
        self.frame_count += 1
        total_time = time() - self.start_time
        avg_time = total_time * 1000 / self.frame_count
        framerate = self.frame_count / total_time
        self._metrics["total time"] = (avg_time, "ms", self.frame_count)
        self._metrics["framerate"] = (framerate, "fps", self.frame_count)
        if print_stdout:
            print(
                "[UTILS] [%s] Metric '%s': %5.2f %s"
                % (
                    self.flow.model.model_name,
                    "total time",
                    self._metrics["total time"][0],
                    self._metrics["total time"][1],
                )
            )
            print(
                "[UTILS] [%s] Metric '%s': %5.2f %s"
                % (
                    self.flow.model.model_name,
                    "framerate",
                    self._metrics["framerate"][0],
                    self._metrics["framerate"][1],
                )
            )


def reporting_loop(demo_title):
    """
    Called from a new thread which periodically prints all the processing
    times gathered by call to report_proctime()
    It uses ncurses to print a nice looking table showcasing current value,
    average value and total samples measured, etc
    """
    global report_list
    stdscr = curses.initscr()
    curses.noecho()
    curses.cbreak()
    y, x = stdscr.getmaxyx()
    last_pos = 76
    for report in report_list:
        if len("Model Name: " + report.flow.model.model_name) + 2 > last_pos:
            last_pos = len("Model Name: " + report.flow.model.model_name) + 2
    stdscr.keypad(True)
    while stop_reporting_loop == False:
        stdscr.clear()
        stdscr.addstr(1, 1, "+%s+" % ("-" * (last_pos - 2)))
        stdscr.addstr(2, 1, "| {:<73s}".format(demo_title))
        stdscr.addstr(2, last_pos, "|")
        stdscr.addstr(3, 1, "+%s+" % ("-" * (last_pos - 2)))
        i = 4
        for report in report_list:
            stdscr.addstr(i, 1, "+%s+" % ("-" * (last_pos - 2)))
            stdscr.addstr(
                i + 1, 1, "| {:<73s}".format("Input Src: " + report.flow.input.source)
            )
            stdscr.addstr(i + 1, last_pos, "|")
            stdscr.addstr(
                i + 2,
                1,
                "| {:<73s}".format("Model Name: " + report.flow.model.model_name),
            )
            stdscr.addstr(i + 2, last_pos, "|")
            stdscr.addstr(
                i + 3,
                1,
                "| {:<73s}".format("Model Type: " + report.flow.model.task_type),
            )
            stdscr.addstr(i + 3, last_pos, "|")
            stdscr.addstr(i + 4, 1, "+%s+" % ("-" * (last_pos - 2)))
            i += 5
            for tag in report._proctime.keys():
                (avg, n) = report._proctime[tag]
                avg = avg * 1000
                stdscr.addstr(i, 1, "| {:<32s} :".format(tag))
                stdscr.addstr(i, 42, "{:>8.2f} ms".format(avg), curses.A_BOLD)
                stdscr.addstr(i, 55, " from {:^5d}  samples ".format(n))
                stdscr.addstr(i, last_pos, "|")
                i = i + 1
            # Throughput
            for tag in report._metrics.keys():
                (val, unit, n) = report._metrics[tag]
                stdscr.addstr(i, 1, "| {:<32s} :".format(tag))
                stdscr.addstr(i, 42, "{:>8.2f} {}".format(val, unit), curses.A_BOLD)
                stdscr.addstr(i, 55, " from {:^5d}  samples ".format(n))
                stdscr.addstr(i, last_pos, "|")
                i = i + 1
            stdscr.addstr(i, 1, "+%s+" % ("-" * (last_pos - 2)))
            if (y - i) < 12:
                break

        stdscr.refresh()
        sleep(1)

    # Cleanup before existing
    curses.nocbreak()
    stdscr.keypad(False)
    curses.echo()
    curses.endwin()
    sys.exit(1)


def enable_curses_reports(demo_title):
    """
    By default, all the processing times are reported on stdout with a single
    print statement. Calling this will start a new thread which uses ncurses
    to display a table with processing times measured for all the tags and
    keeps the table updated periodically.
    This is useful for visualizing the performance of the demo.
    """
    global print_stdout
    print_stdout = False
    thread_report = threading.Thread(target=reporting_loop, args=(demo_title,))
    thread_report.start()


def disable_curses_reports():
    global stop_reporting_loop
    stop_reporting_loop = True


def is_appropriate_value_type(prop):
    """
    This function checks if the type of value of a property is appropriate
    for printing.

    Args:
        prop: Element Property
    """
    types = (
        GObject.TYPE_BOOLEAN,
        GObject.TYPE_STRING,
        GObject.TYPE_CHAR,
        GObject.TYPE_UINT,
        GObject.TYPE_INT,
        GObject.TYPE_INT64,
        GObject.TYPE_UINT64,
        GObject.TYPE_FLOAT,
        GObject.TYPE_DOUBLE,
        GObject.TYPE_LONG,
        GObject.TYPE_ULONG,
    )
    for i in types:
        if GObject.GType.is_a(prop.value_type, i):
            return True
    return False


def get_name_with_prop(element):
    """
    This function is used to get the factory name of the element and its
    properties and caps. Only properties in gst_property_list are parsed

    Args:
        element(GstElement): Gst Element
    """
    element_name = element.get_factory().get_name()
    element_prop = ""
    for i in element.list_properties():
        if (
            i.flags & GObject.ParamFlags.READABLE
            and i.flags & GObject.ParamFlags.WRITABLE
        ):
            try:
                if element_name == "capsfilter" and i.name == "caps":
                    caps = element.get_property("caps")
                    if caps and caps.get_size() > 0:
                        element_prop += " caps="
                        structure = element.get_property("caps").get_structure(0)
                        element_prop += Gst.value_serialize(structure).replace("\\", "")
                elif (
                    i.name == "name"
                    or i.name == "caps"
                    or i.default_value == element.get_property(i.name)
                ):
                    continue
                else:
                    if GObject.GType.is_a(i.value_type, GObject.GEnum):
                        element_prop += " " + i.name + "="
                        element_prop += str(int(element.get_property(i.name)))
                    elif GObject.GType.is_a(i.value_type, GObject.TYPE_BOXED):
                        element_prop += " " + i.name + "="
                        element_prop += "\"" + Gst.Structure.to_string(element.get_property(i.name)) + "\""
                    elif is_appropriate_value_type(i):
                        element_prop += " " + i.name + "="
                        element_prop += str(element.get_property(i.name))
            except:
                continue

    return element_name + element_prop


def print_single_input(pipeline, start_element):
    """
    This function prints a siso or simo gst pipeline

    Args:
        pipeline(GstBin): Gst Pipeline
        start_element(GstElement): The single source element to start from
    """
    data = (start_element, None, None)  # (element,prefix,suffix)
    string = ""
    visited = set()
    stack = [data]
    while len(stack) > 0:
        element, prefix, suffix = stack.pop()
        if element.get_name() not in visited:
            visited.add(element.get_name())
            elem_name = element.get_name()
            elem_klass = element.get_metadata("klass")
            # Wait For Sometime in case source pad not present in element
            t_end = time() + 5
            while (
                not "Sink" in elem_klass and element.numsrcpads == 0 and time() < t_end
            ):
                continue

            if prefix:
                string += "%s ! " % prefix
            if element.numsrcpads == 0:
                string += "%s name=%s\n" % (get_name_with_prop(element), elem_name)
            elif element.numsrcpads == 1:
                string += "%s ! " % get_name_with_prop(element)
            else:
                string += "%s name=%s\n" % (get_name_with_prop(element), elem_name)

            if suffix:
                string += "%s" % suffix
            child = []
            for pad in element.srcpads:
                try:
                    t_end = time() + 5  # Add timeout for saftey
                    while not pad.get_peer() and time() < t_end:  # Hack for qtdemux
                        pass
                    peer_element = pad.get_peer().get_parent()
                    prefix, suffix = None, None
                    if element.numsrcpads > 1:
                        prefix = "%s." % elem_name
                    child.append((peer_element, prefix, suffix))
                except:
                    return string
            stack.extend(reversed(child))
    return string


def print_src_pipeline(pipeline, title=None):
    """
    This function prints the source pipeline

    Args:
        pipeline(GstBin): Gst Pipeline
        title(string): Title given to the flow
    """
    num = 0
    while 1:
        start_element = pipeline.get_by_name("source%d" % (num))
        if not start_element:
            break
        string = print_single_input(pipeline, start_element)
        print(title)
        print(string)
        num += 1
        print()


def print_single_appsrc(pipeline, appsrc, mosaic_list, mosaic_pad_count):
    """
    This function prints a miso or mimo gst pipeline

    Args:
        pipeline(GstBin): Gst Pipeline
        appsrc(GstElement): The single appsrc element to start from
        mosaic_list(list): Holds the mosaic if encountered in the pipeline
        mosaic_pad_count(list): Holds the sink pad count of each mosaic in list
    """
    data = (appsrc, None, None)  # (element,prefix,suffix)
    string = ""
    visited = set()
    stack = [data]
    while len(stack) > 0:
        element, prefix, suffix = stack.pop()
        if element.get_name() not in visited:
            visited.add(element.get_name())
            elem_name = element.get_name()
            elem_klass = element.get_metadata("klass")
            # Wait For Sometime in case source pad not present in element
            t_end = time() + 5
            while (
                not "Sink" in elem_klass and element.numsrcpads == 0 and time() < t_end
            ):
                continue

            if prefix:
                string += "%s ! " % prefix
            if element.numsinkpads == 0:
                string += "%s name=%s ! " % (get_name_with_prop(element), elem_name)
            elif element.numsrcpads == 0:
                string += "%s\n" % get_name_with_prop(element)
            elif element.numsrcpads == 1:
                string += "%s ! " % get_name_with_prop(element)
            else:
                string += "%s name=%s\n" % (get_name_with_prop(element), elem_name)
            if suffix:
                string += "%s" % suffix

            child = []
            for pad in element.srcpads:
                try:
                    t_end = time() + 5  # Add timeout for saftey
                    while not pad.get_peer() and time() < t_end:  # Hack for qtdemux
                        pass
                    peer_element = pad.get_peer().get_parent()
                    peer_element_factory_name = peer_element.get_factory().get_name()
                    if (peer_element_factory_name == "tiovxmosaic"
                        or
                        peer_element_factory_name == "timosaic"):
                        if peer_element not in mosaic_list:
                            mosaic_list.append(peer_element)
                            mosaic_pad_count.append(0)
                        mosaic_idx = mosaic_list.index(peer_element)
                        sink_num = mosaic_pad_count[mosaic_idx]
                        string += "%s.sink_%s\n" % (peer_element.get_name(), sink_num)
                        mosaic_pad_count[mosaic_idx] = sink_num + 1
                    else:
                        prefix, suffix = None, None
                        if element.numsrcpads > 1:
                            prefix = "%s." % elem_name
                        child.append((peer_element, prefix, suffix))
                except:
                    return string
            stack.extend(reversed(child))
    return string


def print_sink_pipeline(pipeline, mosaic_prop, title=None):
    """
    This function prints the sink pipeline

    Args:
        pipeline(GstBin): Gst Pipeline
        mosaic_prop(dict): Dictionary containing mosaic property
        title(string): Title given to the flow
    """
    num = 0
    mosaic_list, mosaic_pad_count = [], []
    while 1:
        appsrc = pipeline.get_by_name("post_%d" % (num))
        if not appsrc:
            break
        string = print_single_appsrc(pipeline, appsrc, mosaic_list, mosaic_pad_count)
        print(string)
        num += 1

    for mosaic in mosaic_list:
        mosaic_name = mosaic.get_name()
        string = "%s name=%s " % (get_name_with_prop(mosaic), mosaic_name)
        string += "src::pool-size=%d\n" % mosaic.srcpads[0].get_property("pool-size")
        for i, (x, y, w, h) in enumerate(mosaic_prop[mosaic_name]):
            if mosaic.get_factory().get_name() == "tiovxmosaic":
                string += 'sink_%d::startx="<%d>" ' % (i, x)
                string += 'sink_%d::starty="<%d>" ' % (i, y)
                string += 'sink_%d::widths="<%d>" ' % (i, w)
                string += 'sink_%d::heights="<%d>"\n' % (i, h)
            else:
                string += 'sink_%d::startx=%d ' % (i, x)
                string += 'sink_%d::starty=%d ' % (i, y)
                string += 'sink_%d::width=%d ' % (i, w)
                string += 'sink_%d::height=%d\n' % (i, h)

        pad = mosaic.srcpads[0]
        element = pad.get_peer().get_parent()
        string += "! "
        while element.numsrcpads > 0:
            string += "%s ! " % get_name_with_prop(element)
            pad = element.srcpads[0]
            element = pad.get_peer().get_parent()

        string += "%s\n" % get_name_with_prop(element)
        print(string)


def to_fraction(num):
    """
    Function to convert numebe to string fraction
    Eg: 0.5 -> "1/2"
    Args:
        num: Number to convert to fraction
    """
    if type(num) == int:
        framerate = "%d/1" % num
        return framerate
    elif type(num) == float:
        num = str(num)
        _, decimal = num.split(".")
        numerator = str(int(num.replace(".", "")))
        denomerator = str(10 ** len(decimal))
        return "%s/%s" % (numerator, denomerator)
    else:
        print("[ERROR] Framerate is not numeric.")
