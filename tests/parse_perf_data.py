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

test_name = sys.argv[1]
stdout = sys.argv[2]
stderr = sys.argv[3]
test_status = sys.argv[4]
cpuload = sys.argv[5]

data = {}
metrics = [ "framerate", "cpuload", "total time", "dl-inference" ]

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
                #print("avg time for %s is %s" % (tag, avgtime))
                data[tag] = avgtime

        match = re.match(".*Metric '(.*)': *(.*) .*", line)
        if (match):
                (tag, metric) = match.groups(0)
                #print("metric for %s is %s" % (tag, metric))
                data[tag] = metric

data["cpuload"] = cpuload
#print(data)

rst_name = "performance_%s.rst" % test_suit
rst_file = open(rst_name, 'a')

# Generate the RST table row for this model
table_row =  "| %s | %s |" % (demo_type, model)
try:
        for i in metrics:
                table_row += " %s |" % data[i]
        table_row += "\n+----------------+-------+-----------+--------------+-----------------+------------------+\n"
except KeyError:
        print("[PERF] ERROR: Failed to parse performance information from the log")
        exit(2)

rst_file.write(table_row)
rst_file.close()

