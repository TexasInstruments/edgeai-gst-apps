# Human Pose Estimation on TI devices

This repo add support for human pose estimation on top of edgeai-gst-apps

Steps to run:

1. Clone this repo in your target

    `git clone https://github.com/TexasInstruments/edgeai-gst-apps-human-pose.git`

2. Download model for human pose estimation

    `./download_models.sh -d human_pose_estimation`

3. Download sample input video

    `wget --proxy off http://software-dl.ti.com/jacinto7/esd/edgeai-test-data/demo_videos/human_pose_estimation_sample.h264 -O /opt/edgeai-test-data/videos/human_pose_estimation_sample.h264`

4. Run the python app

    `cd apps_python`

    `./app_edgeai.py ../configs/human_pose_estimation.yaml`

5. Compile cpp apps

    `./scripts/compile_cpp_apps.sh`

5. Run CPP app

    `cd apps_cpp`

    `./bin/Release/app_edgeai ../configs/human_pose_estimation.yaml`
