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

# Number of process to build OpenCV application
NPROC=1

mkdir -p /opt/proxy
mkdir -p ./proxy

if [ -d "/opt/proxy" ]; then
    cp -r /opt/proxy ./
fi

# modify the server and proxy URLs as requied
if [ "${USE_PROXY}" -ne "0" ]; then
    REPO_LOCATION=
    HTTP_PROXY=
else
    REPO_LOCATION=
fi
echo "USE_PROXY = $USE_PROXY"
echo "REPO_LOCATION = $DOCKER_REPO_INTERNAL"

# Build docker image
docker build \
    -f Dockerfile \
    -t edge_ai_kit \
    --build-arg USE_PROXY=$USE_PROXY \
    --build-arg REPO_LOCATION=$DOCKER_REPO_INTERNAL \
    --build-arg HTTP_PROXY=$HTTP_PROXY \
    --build-arg NPROC=$NPROC .
