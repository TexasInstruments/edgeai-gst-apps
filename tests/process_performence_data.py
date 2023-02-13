#!/usr/bin/python3

# This script requires below python packages
# pandas
# numpy
# matplotlib

import os
import sys
import argparse
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
from matplotlib.backends.backend_pdf import PdfPages


def cleanup_and_save_data(filename,filename_to_save):
    global column_filter,aggragetor,unit,max_value

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
    aggragetor_dict={}
    for i,j in zip(column_filter,aggragetor):
            aggragetor_dict[i] = j
    df = df.groupby(["name","title"],as_index=False,sort=False).agg(aggragetor_dict)

    df = df.rename(columns = {col_name:f"{col_name} ({unit[idx]})" for idx,col_name in enumerate(column_filter)})

    if has_fps:
        df = pd.concat([df , fps["fps"]], axis=1)
        df.to_csv(filename_to_save,index=False)
    else:
        df.to_csv(filename_to_save,index=False)

    print(f"[SUCCESS] Processed raw perf data and saved to {filename_to_save}")
    return df


def generate_plot(df):
    if args.save:
        pdf = PdfPages(pdf_to_save)
    # Plot by group
    for i in range(len(df)):
        # Convert actual value to percentage
        actual_values = list(df.loc[i,~df.columns.isin(['name', 'title', 'fps'])])
        actual_values = [ round(elem,2) for elem in actual_values]
        values = actual_values.copy()
        colors = ['green' for _ in range(len(values))]
        for j in range(len(values)):
            values[j] = (values[j]/max_value[j]) * 100
            if values[j] > 75 and values[j] <= 90:
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
            fps_text = f"FPS: {df.iloc[i]['fps']}"
            plt.annotate(fps_text, xy=(1, 1), xytext=(-15, -15), fontsize=MEDIUM_FONT_SIZE,
                        xycoords='axes fraction', textcoords='offset points',
                        bbox=dict(facecolor='white', alpha=0.8),
                        horizontalalignment='right', verticalalignment='top')
        if args.save:
            fig.savefig(pdf,format="pdf")

    if args.save:
        pdf.close()
        print(f"[SUCCESS] Saved graphs to {pdf_to_save}")

    if args.show == True:
        plt.show()


J7ES_MAX_DDR_BW = 8532
J721S2_MAX_DDR_BW = 17064
J784S4_MAX_DDR_BW = 34128
AM62A_MAX_DDR_BW = 14932

SMALL_FONT_SIZE = 8
MEDIUM_FONT_SIZE = 10
LARGE_FONT_SIZE = 12
SHOW_FPS = True

COLUMN_FILTER = ["mpu1_0","c6x_1","c6x_2","c7x_1","c7x_2","VISS","LDC", "MSC0","MSC1"]
MAX_VALUE     = [  100,     100,    100,    100,   100,    100,   100,   100,   100]
UNIT          = [  "%",     "%",    "%",    "%",   "%",    "%",   "%",   "%",   "%"]
AGGREGATOR    = [ "mean",  "mean", "mean", "mean","mean", "mean","mean","mean", "mean"]

parser = argparse.ArgumentParser()
parser.add_argument('-i', '--input',help='Input CSV files',required=True,type=str,nargs='*')
parser.add_argument('-s', '--save', help='Save plot as pdf', action="store_true", default=False)
parser.add_argument('-p', "--show", help='Show the generated plots in a window', action="store_true", default=False)
args = parser.parse_args()

filenames = args.input
all_dataframes = []
all_soc = []
for filename in args.input:
    filename = filename.strip()
    filename_to_save = ''.join(filename.split(".")[:-1])+"_out."+filename.split(".")[-1]
    pdf_to_save = ''.join(filename.split(".")[:-1])+"_plot.pdf"
    soc = filename.split("_")[0].strip()
    if soc.upper() not in ["J721E","J721S2","J784S4","AM62A"]:
        print("[ERROR] SOC:%s not supported. Please name input csv file with soc followed by _ at start. Ex: j721e_perf_stats.csv" % soc)
        break
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

    column_filter = COLUMN_FILTER + ["ddr_read_avg","ddr_write_avg"]
    max_value  =    MAX_VALUE + [MAX_DDR_BW,  MAX_DDR_BW]
    unit  =         UNIT + ["MB/s","MB/s"]
    aggragetor =    AGGREGATOR + ["mean","mean"]

    # Some sanity checks
    if not os.path.isfile(filename):
        print("[ERROR] %s doesnt exist." % filename)
        break
    if len(column_filter) != len(max_value):
        print("[ERROR] Column_filter and Max Value length doesnt match.")
        break
    if len(column_filter) != len(unit):
        print("[ERROR] Column_filter and Units length doesnt match.")
        break
    if len(column_filter) != len(aggragetor):
        print("[ERROR] Column_filter and Aggregator length doesnt match.")
        break

    df = cleanup_and_save_data(filename,filename_to_save)
    all_dataframes.append(df)
    all_soc.append(soc)
    if (args.save or args.show):
        generate_plot(df)

# Generate combined dataframe
master_df = None
first_join = True
for soc,dataframe in zip(all_soc,all_dataframes):
    renamed_columns = []
    for i in range(len(dataframe.columns)):
        if dataframe.columns[i] == "name" or dataframe.columns[i] == "title":
            continue
        renamed_columns.append(f"{dataframe.columns[i]}_{soc}")
    dataframe.columns = ["name","title"] + renamed_columns

    if master_df is not None:
        suffixes=("","")
        master_df = pd.merge(master_df,dataframe,how='outer',on=['name','title'],suffixes=suffixes).fillna("NA")
    else:
        master_df = dataframe
        prev_soc = soc

column_filter = COLUMN_FILTER + ["ddr_read_avg","ddr_write_avg","fps"]
new_columns = []
for i in column_filter:
    for j in master_df.columns:
        if j == "name" or j == "title":
            continue
        if j.startswith(i):
            new_columns.append(j)

master_df = master_df[["name","title"] + new_columns]
master_df.to_csv("combined_performance_statistics.csv",index=False)
print("[SUCCESS] Processed raw perf data and saved to combined_performance_statistics.csv")

if args.save or args.show:
    if args.save:
        pdf = PdfPages("combined_performance_statistics.pdf")

    column_filter.remove('fps')
    max_value  =    MAX_VALUE + [MAX_DDR_BW,  MAX_DDR_BW]
    unit  =         UNIT + ["MB/s","MB/s"]
    aggragetor =    AGGREGATOR + ["mean","mean"]
    GROUPED_GRAPH_WIDTH = round(1/len(all_soc),2)-0.05

    for i in range(len(master_df)):
        soc_specific_values = {soc_name:[-1 for _ in range(len(column_filter))] for soc_name in all_soc}
        for j in range(len(column_filter)):
            for k in new_columns:
                if k.startswith(column_filter[j]):
                    soc = k.split("_")[-1]
                    if master_df.loc[i,k] != "NA" and "fps" not in k:
                        soc_specific_values[soc][j] = master_df.loc[i,k]

        fig = plt.figure(figsize = (12, 6))
        plt.ylim(0,100)
        plt.title(master_df.iloc[i]['title'], y=1.025,  fontdict = {'fontsize' : SMALL_FONT_SIZE, 'fontweight': 'bold'}, backgroundcolor= 'silver')
        plt.rc('font', size=MEDIUM_FONT_SIZE)
        plt.ylabel('Percentage (%)', fontdict = {'fontsize' : MEDIUM_FONT_SIZE, 'fontweight': 'bold'})
        plt.xlabel('Hardware Loading', fontdict = {'fontsize' : MEDIUM_FONT_SIZE, 'fontweight': 'bold'})
        fig.tight_layout()

        plt.rc('font', size=SMALL_FONT_SIZE-2)
        ind = np.arange(len(column_filter))
        x_coordinate = 0
        fps_y_coord = 1
        for soc,val in soc_specific_values.items():
            if len(val) == val.count(-1):
                break
            value = []
            for j in range(len(val)):
                value.append((val[j]/max_value[j]) * 100)
            value = [ round(elem,2) for elem in value]
            plt.bar(ind+x_coordinate, value, width=GROUPED_GRAPH_WIDTH, label=soc)
            for index, value in enumerate(value):
                if value <= 0: continue
                if (max_value[index] == 100):
                    text = f"{round(val[index],2)} {unit[index]}"
                else:
                    text = f"{round(100*(val[index]/max_value[index]),2)} %\n{val[index]} {unit[index]}"
                plt.text(index+x_coordinate, min(95,value+2), text, horizontalalignment='center')

            if SHOW_FPS:
                fps_text = f"{soc} FPS: {master_df.iloc[i]['fps_%s' % soc]}"
                plt.annotate(fps_text, xy=(1, fps_y_coord), xytext=(-10, -10), fontsize=MEDIUM_FONT_SIZE,
                             xycoords='axes fraction', textcoords='offset points',
                             bbox=dict(facecolor='white', alpha=0.8),
                             horizontalalignment='right', verticalalignment='top')
                fps_y_coord -= 0.05

            x_coordinate += GROUPED_GRAPH_WIDTH

        plt.rc('font', size=MEDIUM_FONT_SIZE)
        plt.xticks(ind + GROUPED_GRAPH_WIDTH / 2, column_filter)
        plt.legend(loc = 'upper left')
        if args.save:
            fig.savefig(pdf,format="pdf")
    if args.save:
        pdf.close()
        print("[SUCCESS] Saved graphs to combined_performance_statistics.pdf")

    if args.show == True:
        plt.show()