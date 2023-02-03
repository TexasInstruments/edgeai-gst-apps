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
3. Run the app to get stats on the terminal. The tools could be invoked
with different command line switches. By default, the display to the terminal
is enabled and this can be turned off by using "-n" switch. In the following
commands, the binary is assumed to be built in Release mode.
```
# The following usage will show the available command line switches
root@j7-evm:/opt/edgeai-gst-apps/scripts/perf_stats/build# ../bin/Release/perf_stats -h

# The following will run the tool with the output logged to the files and
# no output is sent to the terminal
root@j7-evm:/opt/edgeai-gst-apps/scripts/perf_stats/build# ../bin/Release/perf_stats -n -l

# The following will run the tool with the output sent to the terminal and
# at the same time logs to files under ``../perf_logs`` directory.
root@j7-evm:/opt/edgeai-gst-apps/scripts/perf_stats/build# ../bin/Release/perf_stats -l

# The following will run the tool with the output logged to the files and
# no output is sent to the terminal. The files will be under ``../perf_logs/run1`` directory.
root@j7-evm:/opt/edgeai-gst-apps/scripts/perf_stats/build# ../bin/Release/perf_stats -l -d run1

# The following will run the tool with the output sent to the terminal only.
root@j7-evm:/opt/edgeai-gst-apps/scripts/perf_stats/build# ../bin/Release/perf_stats
```
4. If display to the terminal is enabled, then you should see the stats printed
on the terminal like shown below, it will refresh every 2 seconds
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
