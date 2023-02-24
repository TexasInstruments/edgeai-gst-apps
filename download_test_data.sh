#!/bin/bash

#  Copyright (C) 2023 Texas Instruments Incorporated - http://www.ti.com/
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
BASE_DIR=`pwd`

WGET="wget --proxy off"
TEST_DATA_URL="https://software-dl.ti.com/jacinto7/esd/edgeai-test-data/$EDGEAI_SDK_VERSION/edgeai-test-data.tar.gz"
OOB_ASSETS_URL="https://software-dl.ti.com/jacinto7/esd/edgeai-test-data/$EDGEAI_SDK_VERSION/$SOC-oob-demo-assets.tar.gz"

cd ${EDGEAI_DATA_PATH%/*}
$WGET $TEST_DATA_URL
tar xf edgeai-test-data.tar.gz
rm -rf edgeai-test-data.tar.gz

cd ${OOB_DEMO_ASSETS_PATH%/*}
$WGET $OOB_ASSETS_URL
tar xf $SOC-oob-demo-assets.tar.gz
rm -rf $SOC-oob-demo-assets.tar.gz
rm -rf $OOB_DEMO_ASSETS_PATH
mv $SOC-oob-demo-assets $OOB_DEMO_ASSETS_PATH
ln -sf $OOB_DEMO_ASSETS_PATH/*.h264 $EDGEAI_DATA_PATH/videos/

cd $BASE_DIR
