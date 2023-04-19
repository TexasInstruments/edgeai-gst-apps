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

import sys
import argparse
import yaml
import os
import time
import gi
gi.require_version("Gst", "1.0")
gi.require_version("GstApp", "1.0")
from gi.repository import Gst

class Parser(argparse.ArgumentParser):
    def error(self, message):
        sys.stderr.write("error: %s\n" % message)
        self.print_help()
        sys.exit(2)

def get_cmdline_args(sysv_args):
    '''
    Helper function to parse command line arguments
    '''
    global args
    help_str = "Run : " + sysv_args[0] + " -h for help"
    parser = Parser(usage = help_str, \
                formatter_class=argparse.RawTextHelpFormatter)

    help_str_config = "Path to demo config file\n" + \
               "    ex: " + sysv_args[0] + " ../configs/app_config.yaml"
    parser.add_argument("config", help = help_str_config)

    help_str_terminal = "Just print the pipeline (Enabling this option will not run the pipeline)\n" + "default: Disabled"
    parser.add_argument(
        "-t", "--terminal", help=help_str_terminal, action="store_true", default=False
    )

    args = parser.parse_args()
    return args

def get_format_string(element, pad_name):
    """
    Returns format of element as string
    Args:
        element: Gst element
        pad_name: GstPad
    """
    pad = element.get_static_pad(pad_name)
    ret = None
    if pad:
        caps = pad.get_current_caps()
        if not caps:
            caps = pad.get_allowed_caps()
        if caps:
            if caps.is_any():
                ret = 1
            elif caps.get_size() > 0:
                try:
                    ret = caps.get_structure(0).get_value("format")
                except:
                    ret = None
    del element
    return ret

def get_format(pipeline_string):
    """
    Returns the format of last element in pipeline after caps negotiation
    Args:
        pipeline: Gst Pipeline
        format_name: format or tensor-format
    """
    format = None
    
    pipeline_str = pipeline_string.strip()

    if pipeline_str[-1] != "!":
        pipeline_str += " ! fakesink name=fakesink"
    else:
        pipeline_str += " fakesink name=fakesink"

    if "multifilesrc" in pipeline_str.split("!")[0]:
        pipeline_str = pipeline_str.replace("multifilesrc","multifilesrc num-buffers=1")

    pipeline = Gst.parse_launch(pipeline_str)

    bus = pipeline.get_bus()
    pipeline.set_state(Gst.State.PLAYING)
    terminate = False

    last_element = pipeline.get_by_name("fakesink")

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
                        format = get_format_string(last_element, "sink")
                        if format:
                            break
                    if ( not format
                        and old == Gst.State.PAUSED
                        and new == Gst.State.PLAYING
                    ):
                        format = get_format_string(last_element, "sink")
                        break
        except:
            format = None

    pipeline.set_state(Gst.State.NULL)
    del pipeline

    return format