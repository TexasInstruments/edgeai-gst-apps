Steps to get the CPU, DDR and HWA loading
=========================================

1. Navigate to /opt/edgeai-gst-apps/scripts/perf_stats folder
```
cd /opt/edgeai-gst-apps/scripts/perf_stats
```
2. Build the tool
```
root@j7-evm:/opt/edgeai-gst-apps/scripts/perf_stats# mkdir build && cd build

# The following command builds the tool in Release mode. The binary
# will be located under ../bin/Release directory.
root@j7-evm:/opt/edgeai-gst-apps/scripts/perf_stats/build# cmake .. && make

# The following command builds the tool in Debug mode. The binary
# will be located under ../bin/Debug directory.
root@j7-evm:/opt/edgeai-gst-apps/scripts/perf_stats/build# cmake -DCMAKE_BUILD_TYPE=Debug .. && make
```
3. Run the app to get stats on the terminal. In the following
command, the binary is assumed to be built in Release mode.
```
# The following will run the tool with the output sent to the terminal.
root@j7-evm:/opt/edgeai-gst-apps/scripts/perf_stats/build# ../bin/Release/perf_stats
```
4. You should see the stats printed
on the terminal like shown below, it will refresh every 1 second
```text
	Summary of CPU load,
	====================

	CPU: mpu1_0: TOTAL LOAD =  12.21 % ( HWI =   0.24 %, SWI =   0. 0 % )
	CPU: mcu2_0: TOTAL LOAD =   1. 0 % ( HWI =   0. 0 %, SWI =   0. 0 % )
	CPU: mcu2_1: TOTAL LOAD =   1. 0 % ( HWI =   0. 0 %, SWI =   0. 0 % )
	CPU:  c6x_1: TOTAL LOAD =  62.79 % ( HWI =   0.51 %, SWI =   0. 7 % )
	CPU:  c6x_2: TOTAL LOAD =   0. 5 % ( HWI =   0. 2 %, SWI =   0. 1 % )
	CPU:  c7x_1: TOTAL LOAD =   0. 8 % ( HWI =   0. 4 %, SWI =   0. 2 % )


	HWA performance statistics,
	===========================

	HWA:   MSC0: LOAD =  13.33 % ( 79 MP/s )


	DDR performance statistics,
	===========================

	DDR: READ  BW: AVG =    849 MB/s, PEAK =    849 MB/s
	DDR: WRITE BW: AVG =    354 MB/s, PEAK =    354 MB/s
	DDR: TOTAL BW: AVG =   1203 MB/s, PEAK =   1203 MB/s
```
5. Run your application in another terminal to get the stats
