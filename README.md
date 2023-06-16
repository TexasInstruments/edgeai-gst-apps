# Defect Detection using Vision based Edge AI
> Repository to host GStreamer based Edge AI applications for TI devices

This repo adds a vision based defect detection support.

## Table of content
- [About Defect Detection Demo](#about-defect-detection-demo)
- [Supported Devices](#supported-devices)
- [EVM Setup](#evm-setup)
- [Demo Setup and Running](#demo-setup-and-running)
- [Result](#result)
- [How It's Made](#how-its-made)
  - [Data Collection and Augmentation](#data-collection-and-augmentation)
  - [Model Training and Compilation](#model-training-and-compilation)
  - [Object Tracker](#object-tracker)
  - [Dashboard and Bounding Boxes Drawing](#dashboard-and-bounding-boxes-drawing)
  - [Basic Summary of the Code Changes](#basic-summary-of-the-code-changes)
- [Resources](#resources)

## About Defect Detection Demo
This is a demo using **[AM62A](https://www.ti.com/tool/SK-AM62A-LP)** to run a vision based artificial intelligent model for defect detection for manufacturing applications. The model tests the produced units as they move on a conveyer belt, to recognized the accepted and the defected units. The demo is equipped with an object tracker to provide accurate coordinates of the units for sorting and filtering process. A live video is displayed on the screen with green and red boxes overlaid on the accepted and defected units respectively. The screen also includes a graphical dashboard showing live statistics bout total products, defect percentage, production rate, and a histogram of the types of defect. This demo is built based on the the edgeai-gst-apps. It runs on Python only for this current version.

This demo runs a custom trained YOLOX-nano neural network[^1] on the **[AM62A](https://www.ti.com/tool/SK-AM62A-LP)** and performs object detection on imagery to find dfd

![](./doc/defect-detection-demo-setup.gif)

See [Resources](#resources) for links to AM62A and other Edge AI training material.

## Supported Devices

| **DEVICE**              | **Supported**      |
| :---:                   | :---:              |
| AM62A                   | :heavy_check_mark: |

## EVM Setup

Follow the [AM62A Quick Start guide](https://dev.ti.com/tirex/explore/node?node=A__AQniYj7pI2aoPAFMxWtKDQ__am62ax-devtools__FUz-xrs__LATEST) for the [AM62A Starter Kit](https://www.ti.com/tool/SK-AM62A-LP)
* Download the [Edge AI SDK](https://www.ti.com/tool/download/PROCESSOR-SDK-LINUX-AM62A) from ti.com. 
    * Ensure that the tisdk-edgeai-image-am62axx.wic.xz is being used.
* Install the SDK onto an SD card using a tool like Balena Etcher.
* Connect to the device (EVM) and login using a UART connection or a network connection through an SSH session.

## Demo Setup and Running
1. Clone this repo in your target under /opt

    ```console
    root@am62axx-evm:/opt# git clone https://github.com/TexasInstruments/edgeai-gst-apps-defect-detection
    root@am62axx-evm:/opt# cd edgeai-gst-apps-defect-detection
    ```

2. Run the setup script below within this repository *on the EVM*. This requires an internet connection on the EVM. 
*  An ethernet connection is recommended. 
*  Proxy settings for HTTPS_PROXY may be required if the EVM is behind a firewall.

    ```console
    root@am62axx-evm:/opt/edgeai-gst-apps-defect-detection# ./setup-defect-detection.sh
    ```

    This script will download the following:
    a. A pre-trained defect detection model based on yolox-nano-lite[^1] and install it under /opt/model_zoo in the filesystem.
    b. The test video to run the demo without the need to a camera.


3. Run commands as follows from the base directory of this repo on the EVM.

    ```console
    root@am62axx-evm:/opt/edgeai-gst-apps-defect-detection# cd apps_python
    ```
    * To run the demo using the pre-recorded test video as input:
    ```console
    root@am62axx-evm:/opt/edgeai-gst-apps-defect-detection/apps_python# ./app_edgeai.py ../configs/defect_detection_test_video.yaml
    ```
   * To run the demo using a CSI camera as input:
    ```console
    root@am62axx-evm:/opt/edgeai-gst-apps-defect-detection/apps_python# ./app_edgeai.py ../configs/defect_detection_camera.yaml
    ```

## Result
The application shows two main sections on the screen: live feed of the input video and a graphical dashboard. The live video is overlaid boxes on the detected objects. The green boxes represent accepted (good) objects while the defected objects are overlaid with various shades of red to distinguish their defect types. The dashboard graphically shows an overview of the whole production performance including the total produced units since start of operation, the percentage of the defected units, and the production rate as units per hour. The dashboard also shows a histogram detailing the types of detected defects. 
![](./doc/defect-detection-demo-screen.gif)

## How It's Made
### Data collection and Augmentation
The demo is built by custom training YOLOX-nano model. Four classes are used to train the model: Good (accepted) and three classes of defects including Half Ring, No Plastic, No Ring. The figure shows examples of pictures from the four classes. The pictures in the figure are cropped for clarity purposes.

![](./doc/classes.jpg)

100 pictures were taken for each class (total 400 pictures) in one orientation while changing the lighting condition of each picture. The camera is positioned at a hight that is approximate to the height expected in the actual demo setup. The pictures are captured with a resolution of 720x720. The following figure shows samples of the pictures captured for the good class.
![](./doc/samples_good_class.jpg)

Then data augmentation is used expand the collected dataset. Two geometrical augmentation methods are applied flip right-left and rotation. First flipped copies are created for each picture which brings the total number of pictures to 400x2=800. Then five rotated copies of each picture is created which brings the total number of pictures up to 800+800x5=4800 pictures. The rotation angle is randomly selected for each picture. The following figure shows the augmentation process with an example. The pictures in the figure are cropped show the changes.

![](./doc/augmentation_process.jpg)

### Model Training and Compilation
The model is trained using TI Edge AI Studio **[Model Composer](https://dev.ti.com/modelcomposer/)**, an online application which provided a full suite of tools required for edge ai applications including data capturing, labeling, training, compilation and deployment. Follow this **[Quick Start Guide](https://software-dl.ti.com/ccs/esd/training/workshop/edgeaistudio/modelcomposer_quick_start_guide.html)** for a detailed tutorial about using the Model Composer.

The labeled dataset with the 4800 pictures is compressed as a tar file and uploaded to the model composer. The model composer divides the dataset into three parts for training, testing and validation. The yolox-nano-lite model is selected in the training tab with the following parameters:
* Epochs: 10 
* Learning Rate: 0.002 
* Batch size: 8 
* Weight decay: 0.0001 

The model achieved 100% accuracy on the training.

The model is then compiled using the default preset parameters in the model composer:
* Calibration Frames: 10 
* Calibration Iterations: 10 
* Detection Threshold: 0.6 
* Detection Top K: 200 
* Sensor Bits: 8  

This step generated the required artifacts which is downloaded to the AM62A EVM. These artifacts are used to offload the model to the deep accelerator at inference. 

### Object Tracker
The object tracker is used to provide accurate coordinates of the units detected in the frame. This information is used to count the total number of units and the number of units for each class. More important, the coordinates produced by the object tracker can be fed to the sorting and filtering mechanism in the production line. The object tracker code is contained in the object_tracker.py file. 

### Dashboard and Bounding Boxes Drawing
The dashboard graphically shows and over view of the performance of the whole manufacturing system including the total number of units, the percentage of the defected units, and the rate of production in units per hour. It also shows a histogram of the types of defects. Such information is useful to analyze the manufacturing system and select the most common types of defects. The dashboard code is contained in its own class which is saved in the dashboard.py file.
A new class is added to the post_process.py to control all post process work related to the defect detection demo including calling the object tracker, performance statistics calculation, calling dashboard generator, and draw bounding boxes.

### <ins>Basic summary of the code changes</ins>
* **apps_python**:
  * Add a new post process class for defect detection in post_process.py.
  * Add a new dashboard class in dashboard.py to generate graphical representation of the systems performance.
  * Add a new detectObject and objectTracker classes in object_tracker.py to track units detected in the frame.
  * 
* **apps_cpp**:    Not changed in this version
* **configs**:     Create two new config files:
  * /configs/defect_detection_test_video.yaml to run the demo using a pre-recorded video as input.
  * /configs/defect_detection_camera.yaml to run the demo with a CSI or a USB camera feed as input. 

## Resources


| Purpose | Link/Explanation | 
| ------- | ----- | 
|AM62A product page (superset) | https://www.ti.com/product/AM62A7 
| AM62A Starter Kit EVM | https://www.ti.com/tool/SK-AM62A-LP 
| EVM Supporting documentation | https://dev.ti.com/tirex/explore/node?node=A__AA3uLVtZD76DOCoDcT9JXg__am62ax-devtools__FUz-xrs__LATEST
| Master Edge AI page on Github |  https://github.com/TexasInstruments/edgeai 
| Edge AI Cloud | https://dev.ti.com/edgeaistudio/
| Model Analyzer | Allows viewing of benchmarks and real-time evaluation on a 'server farm' of Edge-AI capable EVMs https://dev.ti.com/edgeaisession/
| Model Composer | Allows data capture, data labelling, model selection, model training, and model compilation https://dev.ti.com/modelcomposer/
| Edge AI Academy for new developers | https://dev.ti.com/tirex/explore/node?node=A__AN7hqv4wA0hzx.vdB9lTEw__EDGEAI-ACADEMY__ZKnFr2N__LATEST
| AM62A Processor SDK | https://www.ti.com/tool/PROCESSOR-SDK-AM62A
| Edge AI Linux SDK Documentation | https://software-dl.ti.com/jacinto7/esd/processor-sdk-linux-edgeai/AM62AX/latest/exports/docs/devices/AM62AX/linux/index.html
| AM62A Academy | https://dev.ti.com/tirex/explore/node?node=A__AB.GCF6kV.FoXARl2aj.wg__AM62A-ACADEMY__WeZ9SsL__LATEST
| AM62A Design Gallery | https://dev.ti.com/tirex/explore/node?node=A__AGXaZZe9tNFAfGpjXBMYKQ__AM62A-DESIGN-GALLERY__DXrWFDQ__LATEST
| e2e Support Forums | https://e2e.ti.com



[^1]: This deep learning model for barcode localization is not production grade and is provided as is. TI provides no claims or guarantees about the accuracy of this model or its usage in commercial applications. This model is intended for evaluation only.
