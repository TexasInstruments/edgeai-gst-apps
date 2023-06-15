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

cd $(dirname $0)
WGET="wget --proxy off"
URL_MODEL="https://software-dl.ti.com/jacinto7/esd/edgeai-marketplace/defect-detection/defect-detection-modelartifacts.tar.gz"
URL_TEST="https://software-dl.ti.com/jacinto7/esd/edgeai-marketplace/defect-detection/defect-detection-test.tar.gz"


# download and setup model artifacts
if [  -f defect-detection-modelartifacts.tar.gz ] ; then 
    echo "model is already downloaded"
else 
    $WGET $URL_MODEL
    if [ "$?" -ne "0" ]; then
		echo "Failed to download model; check proxy settings/environment variables. Alternatively, download the model on a PC and transfer to this directory"
    fi
fi

tar -xf defect-detection-modelartifacts.tar.gz -C /opt/model_zoo/ --warning=no-timestamp

# download and setup pre-recorded test video
if [  -f defect-detection-test.tar.gz ] ; then 
    echo "test video is already downloaded"
else 
    $WGET $URL_TEST
    if [ "$?" -ne "0" ]; then
		echo "Failed to download test video; check proxy settings/environment variables. Alternatively, download the video on a PC and transfer to this directory"
    fi
fi
tar -xf defect-detection-test.tar.gz -C /opt/edgeai-test-data/videos/ --warning=no-timestamp