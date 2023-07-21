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

# Link libraries for TFLite delegate
ln -snf /host/usr/lib/libtidl_tfl_delegate.so /usr/lib/libtidl_tfl_delegate.so
ln -snf /host/usr/lib/libtidl_tfl_delegate.so.1.0 /usr/lib/libtidl_tfl_delegate.so.1.0

# Link libraries for ONNX delegate
ln -snf /host/usr/lib/libtidl_onnxrt_EP.so /usr/lib/libtidl_onnxrt_EP.so
ln -snf /host/usr/lib/libtidl_onnxrt_EP.so.1.0 /usr/lib/libtidl_onnxrt_EP.1.0

# Link TI specific headers and libraries
ln -snf /host/usr/lib/libvx_tidl_rt.so /usr/lib/libvx_tidl_rt.so
ln -snf /host/usr/lib/libvx_tidl_rt.so.1.0 /usr/lib/libvx_tidl_rt.so.1.0
ln -snf /host/usr/include/processor_sdk /usr/include/processor_sdk
ln -snf /host/usr/lib/libIL.so.1 /usr/lib/libIL.so.1
ln -snf /host/usr/lib/libILU.so.1 /usr/lib/libILU.so.1
ln -snf /host/usr/lib/libtivision_apps.so /usr/lib/libtivision_apps.so
ln -snf /host/usr/lib/libtivision_apps.so.9.0.0 /usr/lib/libtivision_apps.so.9.0.0
ln -snf /host/usr/lib/libti_rpmsg_char.so.0 /usr/lib/libti_rpmsg_char.so.0

# Softlink update required for v4l2h264enc
rm /usr/lib/aarch64-linux-gnu/gstreamer-1.0/libgstvideo4linux2.so
ln -snf /host/usr/lib/gstreamer-1.0/libgstvideo4linux2.so /usr/lib/aarch64-linux-gnu/gstreamer-1.0/libgstvideo4linux2.so

# Remove non-lib files from /usr/lib
rm -rf /usr/lib/libvx_tidl_rt.so.map
rm -rf /usr/lib/libtidl_onnxrt_EP.so.map
rm -rf /usr/lib/libtidl_tfl_delegate.so.map

# Export LD_PRELOAD to GLdispatch and set LD_LIBRARY_PATH
echo export LD_PRELOAD=/usr/lib/aarch64-linux-gnu/libGLdispatch.so.0 >> ~/.bashrc
echo export LD_LIBRARY_PATH=/usr/lib:/usr/lib/aarch64-linux-gnu:/usr/lib/edgeai-tiovx-modules:/usr/lib/aarch64-linux-gnu/gstreamer-1.0 >> ~/.bashrc

ldconfig

# Disable Neo-DLR phone-home feature
echo '{"enable_phone_home": false}' > /usr/local/lib/python3.10/dist-packages/dlr/counter/ccm_config.json
