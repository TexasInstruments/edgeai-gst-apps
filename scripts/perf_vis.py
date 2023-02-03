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

import os
import argparse
import re
import time
import streamlit as st
from queue import Queue
import plotly.graph_objs as go

st.set_page_config(layout="wide")

graphs, lineGraphs, maxrange = [], [], []
colors = ["#e4040c","#898989",'#282527']
redGradient = ["#ffbbbb","#ef948c","#dc6e5f","#c64534","#ad0808","#8a090b","#68090a","#480707","#2b0202"]
title = ""

for i in range(30):
    fig1, fig2 = go.FigureWidget(), go.FigureWidget()
    graphs.append(fig1)
    lineGraphs.append(fig2)
    maxrange.append(100*5/6)

def stringsToValues(strings):
    try:
        values = [float(x) for x in strings]
    except:
        try:
            values = [int(x) for x in strings]
        except:
            values = strings
    
    return values


def find_oldest_file(path_to_logs):
    # Find oldest log file
    files = os.listdir(path_to_logs)
    files = [path_to_logs+file for file in files if "Log" in file]
    if len(files)==0:
        return None
    oldest_file = min(files, key=os.path.getmtime)
    return oldest_file


def on_value_change(title, history, filename, log_time):

    file1 = open(filename, 'r')


    emptyFlag, count = True, 0
    field_names, field_units, fields, heading = [], [], [], ["","",""]
    
    while True:
        # Read lines one by one each iteration
        line = file1.readline()

        # When file ends close it
        if not line:
            file1.close()
            break

        # if empty line : skip
        if(line.strip() == ""):
            continue

        if title == "":
            title = line.split("{")[0][2:]
            continue

        if line[:1] == "#" or line[:2] == "##" or line[:3] == "###":
            # Previous section ended and new section has started. 
            # If a section was already parsed, then update it's graph. Only then start parsing new section
            if not emptyFlag:
                
                # if last section was HWA, we want to see complete list of available accelerators. Edit the data that was parsed
                if count == 1:
                    HWA_list = ['VISS', 'LDC', 'BLNF', 'MSC0', 'MSC1', 'DOF ', 'SDE', 'GPU', 'INVAL']
                    value_list = []
                    for hwa_item in HWA_list:
                        if hwa_item in fields[0]:
                            value_list.append(fields[1][fields[0].index(hwa_item)])
                        else:
                            value_list.append('0')
                    fields[0] = HWA_list
                    fields[1] = value_list

                # If no data was available in previous section say no data. Else plot it:
                if(fields[0] == []):
                    # Say no data for the previous graph

                    graphs[count].add_annotation(text="No Data",
                    xref="paper", yref="paper",
                    x=0.5, y=0.5, showarrow=False)

                    graphs[count].update_layout(
                        legend=dict(orientation="h",yanchor="bottom",y=1.02,xanchor="right",x=1),
                        title=(" ").join(heading),
                        xaxis=dict(title = field_names[0]),
                        height=400,
                        width=600
                    )

                    if len(field_names) == 2 :
                        y_title = field_names[1]
                        if "LOAD" in field_names[1]:
                            y_title = field_names[1] + " (%)"
                    
                    else:
                        y_title = "MEMORY"

                    if count == 2:
                        y_title = "DDR BW (MB/s)"

                    graphs[count].update_layout(                            
                        yaxis=dict(title = y_title),
                        legend=dict(orientation="h",yanchor="bottom",y=1.02,xanchor="right",x=1),
                    )

                else:
                    # We have data to plot from previous section:
                    # First update graph data then plot
                    
                    
                    while(len(graphs[count].data) < len(fields)-1):
                        plot = go.Bar(x=[], y=[])
                        graphs[count].add_trace(plot)

                    # For each field in section, update the graph data    
                    for i in range(1,len(fields)):
                        
                        # For DDR stats, ignore peak stats
                        if count == 2 and i == len(fields)-1:
                            continue

                        values = stringsToValues(fields[i])
                            
                        graphs[count].data[i-1].x = fields[0]
                        graphs[count].data[i-1].y = values
                        maxrange[count] = max([maxrange[count],max(values)])
                        graphs[count].data[i-1].text = values
                        graphs[count].data[i-1].name = field_names[i] + " (" + field_units[i] + ")"
                        tempColors = [colors[i-1]] * len(values)
                        graphs[count].data[i-1].marker = dict(color=tempColors) 
                        if len(fields[0])==1 and len(field_names)==2:
                            graphs[count].data[i-1].width = 0.33


                        # CPU statistics : maintaining history (15 values) for line graph
                        if count == 0:
                            if history["cpu"] == []:
                                for x in range(len(values)):
                                    history["cpu"].append(Queue(maxsize=15))
                                history["cpu-names"] = fields[0]

                            for index, value in enumerate(values):
                                
                                if history["cpu"][index].full():
                                    history["cpu"][index].get()

                                history["cpu"][index].put(value)

                        # HWA statistics : maintaining history (15 values) for line graph
                        elif count == 1:
                            if history["hwa"] == []:
                                for x in range(len(values)):
                                    history["hwa"].append(Queue(maxsize=15))
                                history["hwa-names"] = fields[0]
                                
                            for index, value in enumerate(values):
                                
                                if history["hwa"][index].full():
                                    history["hwa"][index].get()

                                history["hwa"][index].put(value)

                        
                        # DDR statistics : maintaining history (15 values) for line graph
                        elif count == 2:
                            
                            if i == 1:
                                current_field_name = "ddr-avg"
                            else:
                                current_field_name = "ddr-peak"

                            if history[current_field_name] == []:
                                for x in range(len(values)):
                                    history[current_field_name].append(Queue(maxsize=15))
                                
                                temp = [name+"-"+field_names[i] for name in fields[0]]
                                history[current_field_name+"-names"] = temp


                            for index, value in enumerate(values):
                                if history[current_field_name][index].full():
                                    history[current_field_name][index].get()

                                history[current_field_name][index].put(value)
                                maxrange[19] = max([maxrange[19],value])


                        # FPS statistics : maintaining history (15 values) for line graph
                        elif count == 14:
                            
                            if history["fps"].full():
                                history["fps"].get()

                            history["fps"].put(values[0])
                            fps=values[0]

                    # Plot the updated graph:
                    graphs[count].update_traces(texttemplate='%{text:.2s}', textposition='outside')

                    graphs[count].update_layout(
                        legend=dict(orientation="h",yanchor="bottom",y=1.02,xanchor="right",x=1),
                        title=(" ").join(heading),
                        xaxis=dict(title = field_names[0]),
                        height=400,
                        width=600
                    )
                    if len(field_names) == 2 :
                        y_title = field_names[1]
                        if "LOAD" in field_names[1]:
                            y_title = field_names[1] + " (%)"
                    
                    else:
                        y_title = "MEMORY"
                    
                    if count == 2:
                        y_title = "DDR BW (MB/s)"

                    graphs[count].update_layout(     
                        legend=dict(orientation="h",yanchor="bottom",y=1.02,xanchor="right",x=1),                       
                        yaxis=dict(title = y_title),
                        height=400,
                        width=600
                    )
                    
                    graphs[count].update_yaxes(range=[0, maxrange[count]*6/5])

                # Updated graph for the previous section. Moving on to the next section   
                count += 1

                field_names, field_units, fields = [], [], []

                # No data left to be plotted. Should start parsing data from the new section
                emptyFlag = True

            # Parsing data from new section
            if line[:3] == "###":
                heading[2] = " - " + line.split("#")[-1].strip()

            elif line[:2] == "##":
                heading[1] = " - " + line.split("#")[-1].strip()
                heading[2] = ""
                
            elif line[:1] == "#":
                heading[0] = line.split("#")[-1].strip()
                heading[1] = ""
                heading[2] = ""

        # New section has started and section heading has been parsed. Start parsing data for this section

        elif line[:2] == "--":
            continue

        elif re.search(".*|.*",line) != None:
            # line contains data. Save it in fields
            emptyFlag = False

            if(field_names == []):
                field_names = [string.strip() for string in line[:-1].split("|")]
                for i in range(len(field_names)):
                    fields.append([]) 
                    field_units.append("") 
            else:
                for i, string in enumerate(list(line[:-1].split("|"))):
                    tokens = string.strip().split(" ")
                    fields[i].append(tokens[0])
                    if len(tokens) > 1:
                        field_units[i] = tokens[1]
    # File reading complete


    # Update last bar graph

    while(len(graphs[count].data) < len(fields)-1):
        plot = go.Bar(x=[], y=[])
        graphs[count].add_trace(plot)
                        
    for i in range(1,len(fields)):
        
        # For DDR stats, ignore peak stats
        if count == 2 and i == len(fields)-1:
            continue

        values = stringsToValues(fields[i])
        
        graphs[count].data[i-1].x = fields[0]
        graphs[count].data[i-1].y = values
        maxrange[count] = max([maxrange[count],max(values)])
        graphs[count].data[i-1].text = values
        graphs[count].data[i-1].name = field_names[i] + " (" + field_units[i] + ")"
        tempColors = [colors[i-1]] * len(values)
        graphs[count].data[i-1].marker = dict(color=tempColors) 
        if len(fields[0])==1 and len(field_names)==2:
            graphs[count].data[i-1].width = 0.33

    graphs[count].update_traces(texttemplate='%{text:.2s}', textposition='outside')

    graphs[count].update_layout(
        legend=dict(orientation="h",yanchor="bottom",y=1.02,xanchor="right",x=1),
        title=(" ").join(heading),
        xaxis=dict(title = field_names[0]),
        height=400,
        width=600
    )
    if len(field_names) == 2 :
        y_title = field_names[1]
        if "LOAD" in field_names[1]:
            y_title = field_names[1] + " (%)"
    
    else:
        y_title = "MEMORY"

    if count == 2:
        y_title = "DDR BW (MB/s)"

    graphs[count].update_layout(  
        legend=dict(orientation="h",yanchor="bottom",y=1.02,xanchor="right",x=1),                          
        yaxis=dict(title = y_title),
        height=400,
        width=600
    )
    
    graphs[count].update_yaxes(range=[0, maxrange[count]*6/5])
    if count == 14:
        
        if history["fps"].full():
            history["fps"].get()

        history["fps"].put(values[0])
        fps=values[0]


    #All bar graphs updated for file. Update line graphs 

    # time queue : maintaining log times (15 values) for x-axis of line graphs
    if history["time"].full():
        history["time"].get()
    history["time"].put(log_time)
    log_time_list = list(history["time"].queue)
    min_log_time = min(log_time_list)
    max_log_time = max(log_time_list)

    # CPU line graph
    count = 0
    if history["cpu"] == []:
        lineGraphs[count].add_annotation(text="No Data", xref="paper", yref="paper", x=0.5, y=0.5, showarrow=False)
    else:
        start = 1
        while(len(lineGraphs[count].data) < len(history["cpu"])):
            lineGraphs[count].add_trace(go.Scatter(x=[], y=[],mode='lines',name=history["cpu-names"][len(lineGraphs[count].data)]))
            start += 1

        for i in range(len(history["cpu"])):

            lineGraphs[count].data[i].x = log_time_list
            lineGraphs[count].data[i].y = list(history["cpu"][i].queue)
        
    lineGraphs[count].update_layout(legend=dict(orientation="h",yanchor="bottom",y=1.02,xanchor="right",x=1),title="CPU LOAD",xaxis=dict(title = "LOG TIME (s)"),yaxis=dict(title = "TOTAL LOAD(%)"),height=400,width=600)
    lineGraphs[count].update_xaxes(range=[min_log_time, max_log_time])
    lineGraphs[count].update_yaxes(range=[0, 100])

    # HWA line graph
    count += 1
    if history["hwa"] == []:
        lineGraphs[count].add_annotation(text="No Data", xref="paper", yref="paper", x=0.5, y=0.5, showarrow=False)
    
    else:
        start = 0
        while(len(lineGraphs[count].data) < len(history["hwa"])):
            lineGraphs[count].add_trace(go.Scatter(x=[], y=[],mode='lines',name=history["hwa-names"][len(lineGraphs[count].data)]))
            start += 1


        for i in range(len(history["hwa"])):

            lineGraphs[count].data[i].x = log_time_list
            lineGraphs[count].data[i].y = list(history["hwa"][i].queue)
        
    lineGraphs[count].update_layout(showlegend=True, legend=dict(orientation="h",yanchor="bottom",y=1.02,xanchor="right",x=1),title="HWA LOAD", xaxis=dict(title = "LOG TIME (s)"),yaxis=dict(title = "LOAD (%)"),height=400,width=600)
    lineGraphs[count].update_xaxes(range=[min_log_time, max_log_time])
    lineGraphs[count].update_yaxes(range=[0, 100])

    # DDR line graph
    count += 1
    start = 0

    while(len(lineGraphs[count].data) < len(history["ddr-avg"])):       # +len(history["ddr-peak"])
        lineGraphs[count].add_trace(go.Scatter(x=[], y=[],mode='lines',name=history["ddr-avg-names"][int(len(lineGraphs[count].data))]))
        start += 1
        # lineGraphs[count].add_trace(go.Scatter(x=[], y=[],mode='lines',name=history["ddr-peak-names"][int(len(lineGraphs[count].data)/2)]))
        # start += 1
    
    for i in range(len(history["ddr-avg"])):
        lineGraphs[count].data[i].x = log_time_list
        lineGraphs[count].data[i].y = list(history["ddr-avg"][i].queue)

        # lineGraphs[count].data[i*2].x = log_time_list
        # lineGraphs[count].data[i*2].y = list(history["ddr-avg"][i].queue)
        # lineGraphs[count].data[i*2+1].x = log_time_list
        # lineGraphs[count].data[i*2+1].y = list(history["ddr-peak"][i].queue)

    lineGraphs[count].update_layout(legend=dict(orientation="h",yanchor="bottom",y=1.02,xanchor="right",x=1),title="DDR Bandwidth",xaxis=dict(title = "LOG TIME (s)"),yaxis=dict(title = "DDR BW (MB/s)"),height=400,width=600)
    lineGraphs[count].update_yaxes(range=[0, maxrange[count]*6/5])
    lineGraphs[count].update_xaxes(range=[min_log_time, max_log_time])


    # FPS line graph
    count += 1

    if len(lineGraphs[count].data) == 0:
        lineGraphs[count].add_trace(go.Scatter(x=[], y=[],mode='lines',name="FPS",line=dict(color=redGradient[4])))

    lineGraphs[count].data[0].x = log_time_list
    lineGraphs[count].data[0].y = list(history["fps"].queue)
    
    lineGraphs[count].update_layout(legend=dict(orientation="h",yanchor="bottom",y=1.02,xanchor="right",x=1),title="FPS Statistics",xaxis=dict(title = "LOG TIME (s)"),yaxis=dict(title = "Frame Per Sec (FPS)"),height=400,width=600)
    lineGraphs[count].update_yaxes(range=[0, 100])
    lineGraphs[count].update_xaxes(range=[min_log_time, max_log_time])

    # All bar graphs and line graphs updated for current log file. Exit from function.
    return title, history, fps


# Main code starts here
history = {}

history["cpu"] = []
history["hwa"] = []
history["ddr-peak"] = []
history["ddr-avg"] = []
history["fps"] = Queue(maxsize=15)
history["time"] = Queue(maxsize=15)

st.title("EdgeAI Performance Visualization Tool")

msg = st.header(st.empty)

col1, col2 = st.columns((1,1))

placesLeft, placesRight = [], []

for i in range(10):
    placesLeft.append(col1.empty())

for i in range(10):
    placesRight.append(col2.empty())


st.sidebar.write('Select Graphing Method:')
methods = st.sidebar.radio("",('Line','Bar'),index=1)

st.sidebar.write('Select statistics to display:')
optionNames = ['CPU Load','HWA Load','DDR Bandwidth','Junction Temperature Statistics','mcu2_0 Task Table','mcu2_0 Heap Table','mcu2_1 Task Table','mcu2_1 Heap Table','c6x_1 Task Table','c6x_1 Heap Table','c6x_2 Task Table','c6x_2 Heap Table','c7x_1 Task Table','c7x_1 Heap Table']
graphMap = [0,1,2,15,3,4,5,6,7,8,9,10,11,12]
optionsTemp = []

# By default only show first 4 optionNames graphs
for index, op in enumerate(optionNames):
    if(index < 4):
        optionsTemp.append(st.sidebar.checkbox(op,value=True))
    else:
        optionsTemp.append(st.sidebar.checkbox(op))

parser = argparse.ArgumentParser()

parser.add_argument("-D","--directory", \
                    default=os.path.dirname(os.path.realpath(__file__)) \
                             + '/../perf_logs/', \
                    help = "Directory path that contains log files")
parser.add_argument("-N","--logs_history", \
                    default=16, \
                    help = "Number of Log files that will be maintained as history by the application, in a round-robin fashion")

args = parser.parse_args()

path_to_logs = os.path.abspath(args.directory) + '/'
logs_history = int(args.logs_history)               # Should match save_history variable value used by application

print("Looking for logs in: " + path_to_logs)

# Wait for log files to be generated in the above folder. Then find the oldest log file available.
while True:
    # Check if log folder is present.
    if os.path.isdir(path_to_logs):
        next_filename = find_oldest_file(path_to_logs)
        if next_filename is None:
            msg.write("Looking for 'Log__.md' files in : " + path_to_logs)
            time.sleep(1)                   # if no logs yet, do nothing
            continue
        else:
            print("Log files found.")
            msg.empty()
            break
    else:
        msg.write(path_to_logs + "   not found. Waiting...")
        time.sleep(1)

mtime = 0
start_time = os.path.getmtime(next_filename)
while True:
    if os.path.isfile(next_filename) and os.path.getmtime(next_filename) > mtime:
            filename = next_filename
            mtime = os.path.getmtime(next_filename)
            next_filename = path_to_logs + 'Log' + str((int(filename[:-3].split("Log")[-1])+1)%logs_history) + '.md'
    else:
        if fps == 0:
            fps_str = "NA"
        else:
            fps_str=str(fps)
        msg.subheader("Current FPS : " + fps_str)
        time.sleep(1)
        continue
    
    # Process file (Update all graphs data for file):
    title, history, fps = on_value_change(title,history,filename,mtime-start_time)


    # Refresh all graphs as required
    side, lastleft, lastright = 0, 0, 0
    for optionNumber in range(len(optionsTemp)):
        if optionsTemp[optionNumber]:
            if side == 0:
                with col1:
                    if optionNumber in [0,1,2] and methods == "Line":
                        placesLeft[lastleft].plotly_chart(lineGraphs[optionNumber], use_column_width=True)
                    else:    
                        placesLeft[lastleft].plotly_chart(graphs[graphMap[optionNumber]], use_column_width=True)
                lastleft += 1
            else:
                with col2:
                    if optionNumber in [0,1,2] and methods == "Line":
                        placesRight[lastright].plotly_chart(lineGraphs[optionNumber], use_column_width=True)
                    else:
                        placesRight[lastright].plotly_chart(graphs[graphMap[optionNumber]], use_column_width=True)
                lastright += 1
            side = (side+1)%2
