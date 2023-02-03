#!/usr/bin/python3

import sys
import re
import time
import signal
import threading
import os

stats = {}

pattern_latency = "time=\(guint64\)([0-9]*)"
pattern_ts = "ts=\(guint64\)([0-9]*)"
pattern_element = "element=\(string\)(.*?),"

if len(sys.argv) > 1 and os.path.isfile(sys.argv[1]):
	fp = open(sys.argv[1], 'r')
else:
	print("[ERROR] Trace file dose not exist")
	print("Usage: ./parse_gst_tracers.py ./path/to/gst_trace/trace.log")
	exit()

stop = False
def signal_handler(sig, frame):
	print("Ctrl-C")
	global stop
	stop = True
signal.signal(signal.SIGINT, signal_handler)

header =  "|element                       latency      out-latancy      out-fps     frames     |"
divider = "+-----------------------------------------------------------------------------------+"
def report():
	while(not stop):
		os.system('clear')
		print(divider)
		print(header)
		print(divider)
		for e in stats:
			print('|' + e.ljust(30), ("%0.2f"%(stats[e][0]/1000000)).ljust(13), ("%0.2f"%(stats[e][2]/1000000)).ljust(17), str(stats[e][3]).ljust(12), str(stats[e][4]).ljust(11), '|', sep="")
		print(divider)
		time.sleep(1)
reporting_thread = threading.Thread(target=report)
reporting_thread.start()

while (not stop):
	l = fp.readline()
	if not l:
		time.sleep(0.5)
		continue

	t = re.findall(pattern_latency, l)
	if (not t):
		continue
	if (not t[0]):
		continue

	latency = int(t[0])

	t = re.findall(pattern_ts, l)
	if (not t):
		continue
	if (not t[0]):
		continue

	time_stamp = int(t[0])

	t = re.findall(pattern_element, l)
	if (not t):
		continue
	element = t[0]

	if element not in stats:
                #                [latency[0], curr-timestamp[1], out-latency[2], out-fps[3], num-frames[4]]
		stats[element] = [0,          0,                 0,              0,          0            ];

	stats[element][4] += 1
	stats[element][0] = ((stats[element][4] - 1) * stats[element][0] + latency)/stats[element][4]
	if (stats[element][1]):
		stats[element][2] = ((stats[element][4] - 1) * stats[element][2] + time_stamp - stats[element][1])/stats[element][4]
		stats[element][3] = int(1000000000/stats[element][2])
	stats[element][1] = time_stamp
