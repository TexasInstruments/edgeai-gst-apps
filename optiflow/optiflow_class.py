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

import config_parser
import gst_wrapper
from edgeai_dl_inferer import ModelConfig
import sys
from gst_element_map import gst_element_map

class OptiFlowClass:

    def __init__(self, config):
        """
        Constructor of EdgeAIDemo class
        Args:
            config: Dictionary of params pased from config file
        """
        self.config = config
        self.models = {}
        self.inputs = {}
        self.outputs = {}
        self.flows = []
        self.title = config["title"]

        for f in config["flows"]:
            flow = config["flows"][f]

            """
            flow is a list containing atleast 3 elements:
                [INPUT,MODEL,OUTPUT]
            It may contain 2 additional elements:
                [INPUT,MODEL,OUTPUT,[MOSAIC_PROPERTY],DEBUG]
            If those elements are missing it is considered to be null.
            """

            if len(flow) < 3:
                print(
                    "[ERROR] "
                    + str(f)
                    + " seems incomplete."
                    + " Follow the format [INPUT, MODEL, OUTPUT, MOSAIC[x,y,w,h]"
                    + "(optional)]."
                )
                sys.exit()

            input = flow[0]
            model = flow[1]
            output = flow[2]

            # Parse Input/Model/Output Objects
            if model not in self.models:
                model_config =  config["models"][model]
                model_path = model_config["model_path"]

                # Make model Config. This class is present in edgeai_dl_inferer
                # Enable TIDL here doesnt matter since we are not going to
                # use python runtime anyway. We will use tidlinferer plugin
                model_obj = ModelConfig(model_path,False,1)

                # task specific params
                if "alpha" in model_config:
                    model_obj.alpha = model_config["alpha"]
                if "viz_threshold" in model_config:
                    model_obj.viz_threshold = model_config["viz_threshold"]
                if "topN" in model_config:
                    model_obj.topN = model_config["topN"]

                self.models[model] = model_obj

            if input not in self.inputs:
                input_config = config["inputs"][input]
                input_obj = config_parser.Input(input_config)
                input_obj.name = input
                self.inputs[input] = input_obj

            if output not in self.outputs:
                output_config = config["outputs"][output]
                output_obj = config_parser.Output(output_config, self.title)
                self.outputs[output] = output_obj

            # Set mosaic and start bg_pipeline
            if len(flow) > 3 and flow[3] and not self.outputs[output].mosaic:
                self.outputs[output].set_mosaic()

        for input in self.inputs:
            input_obj = self.inputs[input]
            subflow_dictionary = {}
            subflow_list = []
            
            for i in config["flows"]:
                flow = config["flows"][i]
                if flow[0] != input:
                    continue

                model = flow[1]
                output = flow[2]
                mosaic_info = None
                if len(flow) > 3:
                    mosaic_info = flow[3]

                key = str(model)+"%"+str(output)
                if key not in subflow_dictionary:
                    subflow_dictionary[key] = [
                        mosaic_info
                        ]
                else:
                    subflow_dictionary[key].append(mosaic_info)

            for key in subflow_dictionary:
                model,output = key.strip().split("%")
                model_obj = self.models[model]
                output_obj = self.outputs[output]
                mosaic_list = subflow_dictionary[key]
                subflow_list.append([model_obj, output_obj, mosaic_list])

            self.flows.append(config_parser.Flow(input_obj, subflow_list))
        self.src_strs,self.sink_str = gst_wrapper.get_gst_str(self.flows, self.outputs)

        self.pipeline = ""
        for s in self.src_strs:
            self.pipeline += s
        self.pipeline += self.sink_str
        self.pipeline = self.pipeline.strip()
        idx = len(self.pipeline) - 1
        while (self.pipeline[idx] == "\\" or self.pipeline[idx]==" " or self.pipeline[idx]=="\n"):
            idx -= 1
        self.pipeline = self.pipeline[:idx+1]
        if self.title:
            self.pipeline = self.pipeline.replace('tiperfoverlay',
                                                  'tiperfoverlay title="%s"' % self.title)
    def get_pipeline(self):
        """
        Member function to get the pipeline as str
        """
        return self.pipeline
    
    def run(self):
        """
        Member function to run the pipeline
        """
        pipeline = self.pipeline.replace("\\","")
        pipeline = pipeline.replace("\n","")
        self.gst_pipe = gst_wrapper.GstPipe(pipeline)
        print(f"\n{self.pipeline}\n")
        self.gst_pipe.run()

