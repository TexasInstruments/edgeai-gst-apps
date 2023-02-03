#detect the target platform and set the env
if grep -q j721e /proc/device-tree/compatible
then
    export SOC=j721e
elif grep -q j721s2 /proc/device-tree/compatible
then
    export SOC=j721s2
elif grep -q j784s4 /proc/device-tree/compatible
then
    export SOC=j784s4
elif grep -q am625 /proc/device-tree/compatible
then
    export SOC=am62
elif grep -q am62a /proc/device-tree/compatible
then
    export SOC=am62a
else
    echo "WARNING: EdgeAI Apps is not supported in this Target"
fi

