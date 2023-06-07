#!/bin/bash

echo "Setup Zbar"
./scripts/setup_zbar.sh
if [ "$?" -ne "0" ]; then
    exit_setup
fi


echo "Setup Model"
./scripts/setup_model.sh
if [ "$?" -ne "0" ]; then
    exit_setup
fi


ldconfig

echo "Build C++ apps"
./scripts/compile_cpp_apps.sh $*
if [ "$?" -ne "0" ]; then
    exit_setup
fi

ldconfig 
sync