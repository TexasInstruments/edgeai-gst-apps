#!/usr/bin/python3

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
import re
import yaml
import os

test_name = sys.argv[1]
stdout = sys.argv[2]
stderr = sys.argv[3]
test_status = sys.argv[4]

data = {}
metrics = [ "framerate", "total time", "dl-inference", "mpu1_0", \
            "READ BW", "WRITE BW", "TOTAL BW", \
            "c7x_1", "c6x_1", "c6x_2", "mcu2_0", "mcu2_1", \
            "MSC0", "MSC1", "VISS", "NF", "LDC", "SDE", "DOF" ]

logfile = open(stdout, 'r')
lines = logfile.readlines()
command = lines[0]

# Extract the model and demo_type from command
test_suit = test_name.split('_')[0]
config_file =  command.split()[-1]
with open(config_file, 'r') as f:
    config = yaml.safe_load(f)
model_path = config['models']['dl_model']['model_path']
model = model_path.split('/')[-1]
with open(model_path + '/param.yaml', 'r') as f:
    param = yaml.safe_load(f)
demo_type = param['task_type']

# Parse the output logs to store the performance numbers
for line in lines:
    if "[UTILS]" not in line:
        continue

    match = re.match(".*Time for '(.*)':.*avg *(.*) ms.*", line)
    if (match):
        (tag, avgtime) = match.groups(0)
        data[tag] = avgtime

    match = re.match(".*Metric '(.*)': *(.*) .*", line)
    if (match):
        (tag, metric) = match.groups(0)
        data[tag] = metric

max = 0
for root, dirs, files in os.walk("../perf_logs/", topdown=False):
    for name in files:
        index = int(re.match("Log([0-9]*)\.md", name).groups(0)[0])
        if (index > max):
            max = index

log_file = open("../perf_logs/Log%d.md" % (max - 5))

data["mpu1_0"] = "0"
data["READ BW"] = "0"
data["WRITE BW"] = "0"
data["TOTAL BW"] = "0"
data["c7x_1"] = "0"
data["c6x_1"] = "0"
data["c6x_2"] = "0"
data["mcu2_0"] = "0"
data["mcu2_1"] = "0"
data["MSC0"] = "0"
data["MSC1"] = "0"
data["VISS"] = "0"
data["NF"] = "0"
data["LDC"] = "0"
data["SDE"] = "0"
data["DOF"] = "0"

for line in log_file.readlines():
    for key in metrics:
        match = re.match(" *" + key + " *\| *([0-9]*\.?[ *]?[0-9]*)", line)
        if (match):
            data[key] = match.groups(0)[0].replace(" ", "")
            break;

rst_name = "data_sheet_%s.rst" % test_suit
rst_file = open(rst_name, 'a')

# Generate the RST table row for this model
table_row =  "    %s" % model
try:
        for i in metrics:
                table_row += ",%s" % data[i]
        table_row += "\n"
except KeyError:
        print("[PERF] ERROR: Failed to parse performance information from the log")
        exit(2)

rst_file.write(table_row)
rst_file.close()
os.system("rm -rf ../perf_logs/")
