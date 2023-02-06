#!/usr/bin/python3

# This script requires below python packages
# pandas
# matplotlib

import os
import sys
import argparse
import pandas as pd
import matplotlib.pyplot as plt
from matplotlib.backends.backend_pdf import PdfPages

J7ES_MAX_DDR_BW = 8532
J721S2_MAX_DDR_BW = 17064
J784S4_MAX_DDR_BW = 34128
AM62A_MAX_DDR_BW = 14932

parser = argparse.ArgumentParser()
parser.add_argument('-if', '--input',help='Input CSV file',required=True)
parser.add_argument('-of', '--output',help='Output CSV file',required=False)
parser.add_argument('-s', '--save', help='Filename to save plot as', default=None)
parser.add_argument('-p', "--show", help='Show the generated plots in a window', action="store_true", default=False)
args = parser.parse_args()

filename = args.input
filename_to_save = args.output

soc = filename.split("_")[0].strip()
if soc.upper() not in ["J721E","J721S2","J784S4","AM62A"]:
    print("[ERROR] SOC:%s not supported. Please name input csv file with soc followed by _ at start. Ex: j721e_perf_stats.csv" % soc)
    sys.exit(-1)
soc = soc.upper()
print("[INFO] SOC: %s" % soc)
if soc == "J721E":
    MAX_DDR_BW = J7ES_MAX_DDR_BW
elif soc == "J721S2":
    MAX_DDR_BW = J721S2_MAX_DDR_BW
elif soc == "J784S4":
    MAX_DDR_BW = J784S4_MAX_DDR_BW
elif soc == "AM62A":
    MAX_DDR_BW = AM62A_MAX_DDR_BW

column_filter = ["mpu1_0","c6x_1","c6x_2","c7x_1","c7x_2","VISS","LDC", "MSC0","MSC1","ddr_read_avg","ddr_write_avg"]
max_value  =    [  100,     100,    100,    100,   100,    100,   100,   100,   100,    MAX_DDR_BW,  MAX_DDR_BW]
unit  =         [  "%",     "%",    "%",    "%",   "%",    "%",   "%",   "%",   "%",     "MB/s",        "MB/s"]
aggragetor =    [ "mean",  "mean", "mean", "mean","mean", "mean","mean","mean", "mean",  "mean",        "mean"]

SMALL_FONT_SIZE = 8
MEDIUM_FONT_SIZE = 10
LARGE_FONT_SIZE = 12
SHOW_FPS = True

# Some sanity checks
if not os.path.isfile(filename):
    print("[ERROR] %s doesnt exist." % filename)
    sys.exit(-1)
if len(column_filter) != len(max_value):
    print("[ERROR] Column_filter and Max Value length doesnt match.")
    sys.exit(-1)
if len(column_filter) != len(unit):
    print("[ERROR] Column_filter and Units length doesnt match.")
    sys.exit(-1)
if len(column_filter) != len(aggragetor):
    print("[ERROR] Column_filter and Aggregator length doesnt match.")
    sys.exit(-1)

# Read the file
try:
    df_original = pd.read_csv(filename)
except Exception as e:
    print(e)

# Clean up data and remove duplicate headers
df_original.columns = df_original.columns.str.strip()
df_original = df_original[df_original.iloc[:, 0] != df_original.columns[0]]
df_original.to_csv(filename_to_save,index=False)

df = pd.read_csv(filename_to_save)

# Copy FPS to be used later
if 'fps' in df.columns:
    fps = df.groupby(["name","title"],as_index=False,sort=False).agg({"fps":"mean"})
    has_fps = True
else:
    has_fps = False
    SHOW_FPS = False

# Adding HWA stats from multiple mcu cores
df = df.groupby(df.columns, axis=1, sort=False).sum()

# Filter by column_filter and handle non-existance column_filter elements
try:
    df = df[["name","title"]+column_filter]
except KeyError as e:
    print(e)
    df = df[df.columns.intersection(["name","title"]+column_filter)]
    t_column_filter = list(df.columns)
    t_column_filter.remove("name")
    t_column_filter.remove("title")
    t_aggregator = []
    t_max_value = []
    t_unit = []
    for i in t_column_filter:
        t_aggregator.append(aggragetor[column_filter.index(i)])
        t_max_value.append(max_value[column_filter.index(i)])
        t_unit.append(unit[column_filter.index(i)])
    aggragetor = t_aggregator
    max_value = t_max_value
    unit = t_unit
    column_filter = t_column_filter

# Group by column name and apply aggregation
count = 0
aggragetor_dict={}
for i,j in zip(column_filter,aggragetor):
        aggragetor_dict[i] = j
df = df.groupby(["name","title"],as_index=False,sort=False).agg(aggragetor_dict)

df = df.rename(columns = {col_name:f"{col_name} ({unit[idx]})" for idx,col_name in enumerate(column_filter)})
if has_fps:
    df_to_save = pd.concat([df , fps["fps"]], axis=1)
    df_to_save.to_csv(filename_to_save,index=False)
else:
    df.to_csv(filename_to_save,index=False)

print(f"[SUCCESS] Processed raw perf data and saved to {filename_to_save}");

if args.save != None:
    pdf = PdfPages(args.save)

# Plot by group
for i in range(len(df)):
    # Convert actual value to percentage
    actual_values = list(df.loc[i,~df.columns.isin(['name', 'title'])])
    actual_values = [ round(elem,2) for elem in actual_values]
    values = actual_values.copy()
    colors = ['green' for _ in range(len(values))]
    for j in range(len(values)):
        values[j] = (values[j]/max_value[j]) * 100
        if values[j] > 50 and values[j] <= 90:
            colors[j] = 'yellow'
        elif values[j] > 90:
            colors[j] = 'red'

    values = [ round(elem,2) for elem in values]

    fig = plt.figure(figsize = (12, 6))
    plt.ylim(0,100)
    plt.title(df.iloc[i]['title'], y=1.025,  fontdict = {'fontsize' : SMALL_FONT_SIZE, 'fontweight': 'bold'}, backgroundcolor= 'silver')
    plt.ylabel('Percentage (%)', fontdict = {'fontsize' : MEDIUM_FONT_SIZE, 'fontweight': 'bold'})
    plt.xlabel('Hardware Loading', fontdict = {'fontsize' : MEDIUM_FONT_SIZE, 'fontweight': 'bold'})
    fig.tight_layout()

    plt.bar(column_filter, values, color=colors)

    plt.rc('font', size=SMALL_FONT_SIZE)
    for index, value in enumerate(values):
        if (max_value[index] == 100):
            text = f"{actual_values[index]} {unit[index]}"
        else:
            text = f"{round(100*(actual_values[index]/max_value[index]),2)} %\nvalue: {actual_values[index]} {unit[index]}"
        plt.text(index, min(95,value+2), text, horizontalalignment='center')

    if SHOW_FPS:
        fps_text = f"FPS: {fps.iloc[i]['fps']}"
        plt.annotate(fps_text, xy=(1, 1), xytext=(-15, -15), fontsize=MEDIUM_FONT_SIZE,
                     xycoords='axes fraction', textcoords='offset points',
                     bbox=dict(facecolor='white', alpha=0.8),
                     horizontalalignment='right', verticalalignment='top')
    if args.save != None:
        fig.savefig(pdf,format="pdf")

if args.save != None:
    pdf.close()
    print(f"[SUCCESS] Saved graphs to {args.save}")

if args.show == True:
    plt.show()
