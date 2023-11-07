#detect the target platform and set the env
if grep -q j721e /proc/device-tree/compatible
then
    export SOC=j721e
    export DEVICE_NAME=TDA4VM
elif grep -q j721s2 /proc/device-tree/compatible
then
    export SOC=j721s2
    export DEVICE_NAME=AM68A
elif grep -q j784s4 /proc/device-tree/compatible
then
    export SOC=j784s4
    export DEVICE_NAME=AM69A
elif grep -q j722s /proc/device-tree/compatible
then
    export SOC=j722s
    export DEVICE_NAME=AM67A
elif grep -q am625 /proc/device-tree/compatible
then
    export SOC=am62x
    export DEVICE_NAME=AM62X
elif grep -q am62a /proc/device-tree/compatible
then
    export SOC=am62a
    export DEVICE_NAME=AM62A
elif grep -q am62p /proc/device-tree/compatible
then
    export SOC=am62p
    export DEVICE_NAME=AM62P
else
    echo "WARNING: EdgeAI Apps is not supported in this Target"
fi

