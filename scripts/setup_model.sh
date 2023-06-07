#!/bin/bash

if [  -f barcode-modelartifacts.tar.gz ] ; then 
    echo "model already downloaded"
else 
    wget https://software-dl.ti.com/jacinto7/esd/edgeai-marketplace/barcode-reader/barcode-modelartifacts.tar.gz
    if [ "$?" -ne "0" ]; then
        unset HTTPS_PROXY HTTP_PROXY https_proxy http_proxy
        if [ "$?" -ne "0" ]; then
        wget https://software-dl.ti.com/jacinto7/esd/edgeai-marketplace/barcode-reader/barcode-modelartifacts.tar.gz
            echo "Failed to download model; check proxy settings/environment variables. Alternatively, download the model on a PC and transfer to this directory"
        fi
    fi
fi

mkdir -p /opt/model_zoo/barcode-modelartifacts
tar -xf barcode-modelartifacts.tar.gz -C /opt/model_zoo/barcode-modelartifacts --warning=no-timestamp