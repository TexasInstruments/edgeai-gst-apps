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

ARG USE_PROXY
ARG HTTP_PROXY
ARG REPO_LOCATION=arm64v8
ARG DEBIAN_FRONTEND=noninteractive
ARG NPROC=1
ARG PROJECT_NAME=edgeai-gst-apps

#=========================================================================
# The environment variable REPO_LOCATION is set from outside as needed,
# based on network
FROM ${REPO_LOCATION}/ubuntu:22.04 AS base-0

#=========================================================================
FROM base-0 AS base-1
ARG USE_PROXY
ENV USE_PROXY=${USE_PROXY}
ARG HTTP_PROXY
ENV http_proxy=${HTTP_PROXY}
ENV https_proxy=${HTTP_PROXY}

#=========================================================================
FROM base-${USE_PROXY} AS ubuntu-stage1
ARG DEBIAN_FRONTEND

# Setup proxy settings
ADD entrypoint.sh setup_proxy.sh setup_ti_processor_sdk.sh /usr/bin/
ADD proxy /root/proxy
RUN /usr/bin/setup_proxy.sh

RUN apt-get update -y && apt-get dist-upgrade -y && apt-get install -y \
    glib-2.0-dev \
    ncurses-dev \
    libv4l-dev \
    libopencv-core-dev \
    libopencv-imgproc-dev \
    libopencv-imgcodecs-dev \
    libyaml-cpp-dev \
    libboost-all-dev \
    libglvnd-dev

RUN apt-get install -y \
    build-essential \
    cmake \
    ninja-build \
    git \
    wget \
    unzip \
    pkg-config \
    gfortran \
    openexr

# Install python and pip
RUN apt-get install -y \
    python3 \
    python3-dev \
    python3-opencv \
    python3-pip && \
    pip3 install \
        pycparser \
        streamlit \
        plotly==5.1.0 \
        jupyterlab \
        meson \
        PyYAML

# Install miscellaneous packages
RUN apt-get install -y \
    vim \
    rsync \
    strace \
    sysstat \
    gdb \
    net-tools \
    dialog \
    chrony \
    nfs-common \
    corkscrew

# Install gstreamer and opencv dependencies
RUN apt-get install -y \
    libgstreamer1.0-0 \
    libgstreamer1.0-dev \
    libgstreamer-plugins-base1.0-dev \
    gstreamer1.0-plugins-base \
    gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad \
    gstreamer1.0-libav \
    gstreamer1.0-tools \
    gir1.2-gst-rtsp-server-1.0 && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

#setup entrypoint to run the demo application
ENTRYPOINT ["/usr/bin/entrypoint.sh"]

