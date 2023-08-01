#!/bin/bash

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

#define SOC env var in docker
export SOC=$1

#setup TI procesor SDK environment
/usr/bin/setup_ti_processor_sdk.sh

#setup proxy as required
/usr/bin/setup_proxy.sh

# Set Current date and Time using NTP
chronyd 2>/dev/null

# Update bashrc to set the PS1 prompt if already not done
cat ~/.bashrc  | grep PS1 | grep docker >/dev/null
if [ "$?" -ne "0" ]; then
	echo 'export PS1="\[\e[40;1;35m\][docker] \[\e[40;0;34m\]\u@\h:\[\e[40;0;32m\]\w#\[\e[m\] "' >> ~/.bashrc
	echo cd /opt/edgeai-gst-apps >> ~/.bashrc
fi

# Add ENV Variables
export PYTHONPATH=$2
export EDGEAI_GST_APPS_PATH=$3
export EDGEAI_DATA_PATH=$4
export OOB_DEMO_ASSETS_PATH=$5
export MODEL_ZOO_PATH=$6
export EDGEAI_VERSION=$7
export EDGEAI_SDK_VERSION=$8

# Spawn a shell
bash
