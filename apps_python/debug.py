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

from pathlib import Path
import sys

class DebugConfig:
    """
    Class to parse and store debug parameters
    """

    def __init__(self, flow, debug_config):
        """
        Constructor of DebugConfig class
        Args:
            flow: Parent flow object
            debug_config: Dictionary of input params provided in config file
        """
        self.flow = flow

        self.pre_proc = False
        self.inference = False
        self.post_proc = False
        if "enable_mask" in debug_config:
            enable_mask = debug_config["enable_mask"]
            if enable_mask & 1:
                self.pre_proc = True
            if enable_mask & 2:
                self.inference = True
            if enable_mask & 4:
                self.post_proc = True

        out_dir = "./debug_out"
        if "out_dir" in debug_config:
            out_dir = debug_config["out_dir"]

        # create output directory if dose not exist
        self.output_dir = (
            out_dir + "/python/" + flow.input.name + "/" + flow.model.model_name
        )
        Path(self.output_dir).mkdir(parents=True, exist_ok=True)

        self.start_frame = 0
        if "start_frame" in debug_config:
            self.start_frame = debug_config["start_frame"]

        self.end_frame = sys.maxsize
        if "end_frame" in debug_config:
            self.end_frame = debug_config["end_frame"]


class Debug:
    """
    Class to manage debug dump at diffent points
    like pre process, post process and inference
    """

    def __init__(self, debug_config, prefix):
        """
        Constructor of Debug class
        Args:
            debug_config: debug config object
            prefix: prefix to append to dump files
        """
        self.frame_count = 1
        self.config = debug_config
        self.file = (
            debug_config.output_dir
            + "/"
            + prefix
            + "_%d.txt"
        )

    def log(self, log_str):
        """
        Dump the given string in dump file
        Args:
            log_str: string to be dumped
        """
        if (
            self.frame_count >= self.config.start_frame
            and self.frame_count <= self.config.end_frame
        ):
            fp = open(self.file % self.frame_count, "w+")
            fp.write(log_str)
            fp.close()
        self.frame_count += 1
