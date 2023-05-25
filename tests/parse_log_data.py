#!/usr/bin/python3

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
import time
import sys
import argparse

def error_in_logfile(log_file):
    pass_flag = False
    exit_code = 0

    if not os.path.isfile(log_file):
        print ("[LOG-PARSE] FAIL - Log file %s does not exist." % log_file)
        sys.exit(1)

    if os.path.getsize(log_file) == 0:
        print ("[LOG-PARSE] FAIL - Log file empty.")
        sys.exit(1)

    with open(log_file) as out_obj:
        stdout_lines = out_obj.readlines()
        ignore_tags = [
            "VX_ZONE_ERROR:Enabled",
            "ERROR:Enabled",
            "VX_ZONE_ERROR:[tivxObjectDeInit"
        ]

        for line in stdout_lines:
            line = line.strip()
            if "VX_ZONE_ERROR" in line:
                if any( True for error in ignore_tags if error in line):
                    continue
                else:
                    print ("[LOG-PARSE] FAIL - %s" % line)
                    exit_code = 1
                    break

            if "ERROR" in line or "error" in line or "Error" in line:
                if "No metadata file" in line:
                    continue
                if "No valid frames found" in line:
                    continue
                if any( True for error in ignore_tags if error in line):
                    continue
                else:
                    print ("[LOG-PARSE] FAIL - %s" % line)
                    exit_code = 1
                    break

            if "dumped core" in line or "core dump" in line:
                print ("[LOG-PARSE] FAIL - %s" % line)
                exit_code = 1
                break

            if "Segmentation fault" in line:
                print ("[LOG-PARSE] FAIL - %s" % line)
                exit_code = 1
                break

            if "FileNotFoundError" in line:
                print ("[LOG-PARSE] FAIL - %s" % line)
                exit_code = 1
                break

            if "GStreamer-CRITICAL **" in line:
                print ("[LOG-PARSE] FAIL - %s" % line)
                exit_code = 1
                break

            if "Traceback" in line:
                if not pass_flag:
                    print ("[LOG-PARSE] FAIL - %s" % line)
                    exit_code = 1
                    break

            if "FAILED" in line:
                print ("[LOG-PARSE] FAIL - %s" % line)
                exit_code = 1
                break

            if "OPTIFLOW" in log_file:
                if "Reference is NULL" in line:
                    print ("[LOG-PARSE] FAIL - %s" % line)
                    exit_code = 1
                    break
                if arm_mode or "Deinit" in line:
                    pass_flag = True
            else:
                if "[UTILS] " in line:
                    pass_flag = True
                if "GPIO" in line or "PWM" in line:
                    pass_flag = True
    
    if exit_code == 0:
        if not pass_flag:
            if "OPTIFLOW" in log_file:
                print ("[LOG-PARSE] FAIL - Keyword(Deinit) not found in log.")
            else:
                print ("[LOG-PARSE] FAIL - Keyword(UTILS/GPIO/PWN) not found in log.")
            exit_code = 1
        else:
            print ("[LOG-PARSE] PASS")
            exit_code = 0

    sys.exit(exit_code)

parser = argparse.ArgumentParser()
parser.add_argument('path', action='store', type=str, help='The text to parse.')
args = parser.parse_args()

soc = os.getenv("SOC")
arm_mode = False
if soc.lower() not in ("j721e","j721s2","j784s4","am62a"):
    arm_mode = True

error_in_logfile(args.path)