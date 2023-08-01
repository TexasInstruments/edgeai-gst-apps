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

# This script is intented to work with single container.

# Number container exist
cont_count=`docker ps -aq | wc -l`

SOC=$SOC
PYTHONPATH=$PYTHONPATH
EDGEAI_GST_APPS_PATH=$EDGEAI_GST_APPS_PATH
EDGEAI_DATA_PATH=$EDGEAI_DATA_PATH
OOB_DEMO_ASSETS_PATH=$OOB_DEMO_ASSETS_PATH
MODEL_ZOO_PATH=$MODEL_ZOO_PATH
EDGEAI_VERSION=$EDGEAI_VERSION
EDGEAI_SDK_VERSION=$EDGEAI_SDK_VERSION

#If no container exist, then create the container.
if [ $cont_count -eq 0 ]
then
    docker run -it \
        -v /dev:/dev \
        -v /opt:/opt \
        -v /:/host \
        --privileged \
        --network host \
         --env USE_PROXY=$USE_PROXY \
        edge_ai_kit $SOC $PYTHONPATH $EDGEAI_GST_APPS_PATH $EDGEAI_DATA_PATH \
        $OOB_DEMO_ASSETS_PATH $MODEL_ZOO_PATH $EDGEAI_VERSION $EDGEAI_SDK_VERSION
# If one container exist, execute that container.
elif [ $cont_count -eq 1 ]
then
    cont_id=`docker ps -q -l`
    docker start $cont_id
    docker exec -it \
        --env SOC=$SOC \
        --env PYTHONPATH=$PYTHONPATH \
        --env EDGEAI_GST_APPS_PATH=$EDGEAI_GST_APPS_PATH \
        --env EDGEAI_DATA_PATH=$EDGEAI_DATA_PATH \
        --env OOB_DEMO_ASSETS_PATH=$OOB_DEMO_ASSETS_PATH \
        --env MODEL_ZOO_PATH=$MODEL_ZOO_PATH \
        --env EDGEAI_VERSION=$EDGEAI_VERSION \
        --env EDGEAI_SDK_VERSION=$EDGEAI_SDK_VERSION \
        $cont_id /bin/bash

else
    echo -e "\nMultiple containers are present, so exiting"
    echo -e "To run existing container, use [docker start] and [docker exec] command"
    echo -e "To run the new container, use [docker run] command\n"
fi
