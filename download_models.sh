#!/bin/bash

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

cd $(dirname $0)
BASE_DIR=`pwd`
WGET="wget --proxy off"

if [ "$SOC" == "j721e" ]
then
	URLs="https://software-dl.ti.com/jacinto7/esd/modelzoo/08_06_00_01/modelartifacts/TDA4VM/8bits/"
elif [ "$SOC" == "j721s2" ]
then
	URLs="https://software-dl.ti.com/jacinto7/esd/modelzoo/08_06_00_01/modelartifacts/AM68A/8bits/"
elif [ "$SOC" == "j784s4" ]
then
	URLs="https://software-dl.ti.com/jacinto7/esd/modelzoo/08_06_00_01/modelartifacts/AM69A/8bits/"
elif [ "$SOC" == "am62a" ]
then
	URLs="https://software-dl.ti.com/jacinto7/esd/modelzoo/08_06_00_01/modelartifacts/AM62A/8bits/"
else
	echo "ERROR: "$SOC" not supported"
	exit
fi

types="classification detection segmentation human_pose_estimation"
DEST_DIR=../model_zoo/
mkdir -p $DEST_DIR
declare -A keys
declare -A to_keys
cat << EOF > ./dialog.config
#
# Run-time configuration file for dialog
#

tag_color = (BLACK,WHITE,OFF)
tag_key_color = tag_color
tag_key_selected_color = tag_selected_color
use_shadow = OFF
EOF

# Models that are not supported in EdgeAI SDK
cat > $DEST_DIR/unsupported_models.txt << EOF
# height/2 is odd
TFL-CL-0100-efficientNet-edgeTPU-m
TFL-CL-0140-efficientNet-lite4
TFL-CL-0170-efficientNet-lite1
TFL-CL-0190-efficientNet-edgeTPU-l
# High latency
ONR-SS-8730-deeplabv3-mobv3-lite-large-cocoseg21-512x512
# odd resolution
TVM-CL-3430-gluoncv-mxnet-xception
TFL-CL-0040-InceptionNetV3
EOF

export DIALOGRC=./dialog.config

for t in $types
do
	keys[${t:0:1}]=$t
done

parse_models()
{
	if [ $? != '0' ]
	then
		echo "ERROR: Cannot create $DEST_DIR directory"
		exit_script
	fi
	$WGET $1"artifacts.csv" > /dev/null 2>&1
	if [ ! -f artifacts.csv ]; then
		echo "ERROR: Cannot connect to model server!"
		exit_script
	fi
	for i in $(sort <<< $(cat artifacts.csv))
	do
		curr_IFS=$IFS
		IFS=','
		arr=($i)
		if [ ${arr[5]} == "False" ]
		then
			IFS=$curr_IFS
			continue
		fi
		runtime=arr[1]
		type=arr[0]
		file=arr[2]
		name=arr[3]
		if [ "$(echo ${!name} | grep -f $DEST_DIR/unsupported_models.txt)" == "${!name}" ]
		then
			IFS=$curr_IFS
			continue
		fi
		mem=$(printf "%dM" $((${arr[4]}/1024/1024)))
		eval "link_${!type}"+="("$1${!file}.tar.gz")"
		eval "runtime_${!type}"+="("${!runtime}")"
		eval "file_${!type}"+="("${!file}")"
		eval "mem_${!type}"+="($mem)"
		eval "name_${!type}"+="(${!name})"
		if [ ${arr[6]} == "True" ]
		then
			OOB_MODELS+=(${!name})
		fi

		temp=$(ls $DEST_DIR/${!name} 2>&1)
		if [ "$?" = "0" ]
		then
			eval "sel_${!type}"+="("on")"
		else
			eval "sel_${!type}"+="("off")"
		fi
		IFS=$curr_IFS
	done
	rm -f artifacts.csv
	for t in $types
	do
		temp=name_$t[0]
		if [ "${!temp}" == "" ]
		then
			continue
		fi
		to_keys[$t]=${t:0:1}
		for ((i=0;;i++))
		do
			name=name_$t[$i]
			if [ "${!name}" == "" ]
			then
				break
			fi
			to_keys[${!name}]=${t:0:1}"."$i
		done
	done
}

list_models()
{
	for t in $types
	do
		temp=name_$t[0]
		if [ "${!temp}" == "" ]
		then
			continue
		fi
		echo -e "$t models"
		for ((i=0;;i++))
		do
			name=name_$t[$i]
			link=link_$t[$i]
			mem=mem_$t[$i]
			sel=sel_$t[$i]
			if [ "${!name}" == "" ]
			then
				break
			fi
			echo "      ${!name}    ${!mem}"
		done
	done
	echo ""
	echo "Recommended Models"
	for m in ${OOB_MODELS[@]}
	do
		echo "      "$m
	done
	echo ""
	echo "./download_models.sh --download | -d name1 name2 .... | To download models"
	echo "               Ex: ./download_models.sh -d mobilenet_v1_1.0_224.tflite efficientnet-lite0-fp32.tflite"
	echo "                    classification          - To download all classification models"
	echo "                    detection               - To download all object detection models"
	echo "                    segmentation            - To download all semantic segmentation models"
	echo "                    human_pose_estimation   - To downaload all human pose estimation models"
	echo "               Ex: ./download_models.sh -d classification - Will download all classification models"
}

get_models_dialog()
{
	for t in $types
	do
		temp=name_$t[0]
		if [ "${!temp}" == "" ]
		then
			continue
		fi
		printf "${t:0:1} \'$t all models\' off "
		for ((i=0;;i++))
		do
			name=name_$t[$i]
			link=link_$t[$i]
			mem=mem_$t[$i]
			sel=sel_$t[$i]
			if [ "${!name}" == "" ]
			then
				break
			fi
			printf "${t:0:1}.%02d \'    ${!name}    ${!mem}\' ${!sel} " $i
		done
	done
}

check_args()
{
	valid_args=(--list -l --help -h --download -d --recommended -r --list-recommended)
	if [ "$1" == "" ]
	then
		return 0
	fi
	for i in "${valid_args[@]}"
	do
		if [ "$1" == "$i" ]
		then
			return 0
		fi
	done
	usage
}

usage()
{
	echo "./download_models.sh - To launch an interactive session to download models"
	echo "./download_models.sh --list  | -l - To list all the models available"
	echo "./download_models.sh --download | -d name1 name2 .... | To download models"
	echo "               Ex: ./download_models.sh -d mobilenet_v1_1.0_224.tflite efficientnet-lite0-fp32.tflite"
	echo "                    classification          - To download all classification models"
	echo "                    detection               - To download all object detection models"
	echo "                    segmentation            - To download all semantic segmentation models"
	echo "                    human_pose_estimation   - To download all semantic human pose estimation models"
	echo "               Ex: ./download_models.sh -d classification - Will download all classification models"
	echo "./download_models.sh --recommended  | -r - To download out of the box models"
	echo "./download_models.sh --help | -h - To display this"
	exit_script
}

download_models()
{
	for m in "${models[@]}"
	do
		if [ "${#m}" == "1" ]
		then
			for ((i=0;;i++))
			do
				name=name_${keys[$m]}[$i]
				if [ "${!name}" == "" ]
				then
					break
				fi
				models_d+=($m.$i)
			done
		else
			models_d+=($m)
		fi
	done
	for i in "${models_d[@]}"
	do
		sel=sel_${keys[${i:0:1}]}[10#${i:2:2}]
		if [ "${!sel}" == "on" ]
		then
			continue
		fi
		name=name_${keys[${i:0:1}]}[10#${i:2:2}]
		file=file_${keys[${i:0:1}]}[10#${i:2:2}]
		link=link_${keys[${i:0:1}]}[10#${i:2:2}]
		runtime=runtime_${keys[${i:0:1}]}[10#${i:2:2}]
		echo
		echo "Downloading model "${!name}
		cd $DEST_DIR
		$WGET ${!link}
		mkdir ${!name}
		tar xf ${!file}".tar.gz" -C ${!name}
		rm ${!file}".tar.gz"
		if [ ${!runtime} == "tvmdlr" ]
		then
			rm -rf ${!name}"/model"
			cd ${!name}"/artifacts"
			for file in `ls *.evm 2>/dev/null`; do mv $file ${file%.*}; done
			rm -rf *.pc
		fi
		cd $BASE_DIR
		eval "sel_${keys[${i:0:1}]}[10#${i:2:2}]"="on"
	done
	echo "Models downloaded to $(cd $DEST_DIR; pwd)"
}

launch_ui()
{
	models_selected=$(bash -c "dialog --backtitle 'Select Models to Download' \
	--title 'Model Downloader' \
	--ascii-lines \
	--no-tags \
	--cancel-label Quit \
	--colors \
	--checklist 'Keys:\n  Up-Down to Navigate Menu\n  Space to Select Models \n  Enter to Continue' 30 180 30 \
	--output-fd 1 $(get_models_dialog)")
	if [ "$?" -eq "0" ]; then
		clear
	fi
	if [ "$models_selected" == "" ]
	then
		echo "No models Selected"
		exit_script
	fi
	models=($models_selected)
	download_models
}

exit_script()
{
	rm -f ./dialog.config ./artifacts.csv
	exit
}

check_args $1

for u in $URLs
do
	parse_models $u
done

case $1 in
	"--list" | "-l")
		list_models
		;;
	"--list-recommended")
	    for m in ${OOB_MODELS[@]}
	    do
		    echo $m
	    done
		;;
	"--recommended" | "-r")
		for m in ${OOB_MODELS[@]}
		do
			models+=(${to_keys[$m]})
		done
		download_models
		;;
	"--download" | "-d")
		if [ "$2" == "" ]
		then
			echo "Please enter the names of the models to be downloaded"
		fi
		for m in $@
		do
			models+=(${to_keys[$m]})
		done
		download_models
		;;
	"--help" | "-h")
		usage
		;;
	"")
		launch_ui
		;;
esac
exit_script
