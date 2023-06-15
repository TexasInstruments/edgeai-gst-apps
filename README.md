# Edge AI GStreamer Apps
> Repository to host GStreamer based Edge AI applications for TI devices

## Edge AI Vision based Defect Detection


This demo runs a custom trained YOLOX-nano neural network[^1] on the **[AM62A](https://www.ti.com/tool/SK-AM62A-LP)** and performs object detection on imagery to find 

![](./doc/defect-detection-demo-setup.gif)

See [Resources](#resources) for links to AM62A and other Edge AI training material.

### Setup

Follow the [AM62A Quick Start guide](https://dev.ti.com/tirex/explore/node?node=A__AQniYj7pI2aoPAFMxWtKDQ__am62ax-devtools__FUz-xrs__LATEST) for the [AM62A Starter Kit](https://www.ti.com/tool/SK-AM62A-LP)
* Download the [Edge AI SDK](https://www.ti.com/tool/download/PROCESSOR-SDK-LINUX-AM62A) from ti.com. 
    * Ensure that the tisdk-edgeai-image-am62axx.wic.xz is being used.
* Install the SDK onto an SD card using a tool like Balena Etcher.
* Establish a network connection onto the device and log in through an SSH session.


Run the setup script below within this repository *on the EVM*. This requires a network connection on the EVM. 
*  An ethernet connection is recommended. 
*  Proxy settings for HTTPS_PROXY may be required if the EVM is behind a firewall.

```
./setup_defect_detection_demo.sh
```
*  If the network fails, clone the zbar repository and download the barcode-modelartifacts on a PC, and transfer to the SD card manually, then rerun the setup script.

This will download several tools to the EVM. 
1. The ([setup_model.sh](./scripts/setup_model.sh)[^2]) script will download a pretrained barcode detection model and install it under /opt/model_zoo in the filesystem
2. The test video to run the demo without the need to a camera.


### Running the Defect Detection Demo

This demo runs on Python only for this current version. It is built based on the the edgeai-gst-apps. Note that running other object detection models may be less effective. Run commands as follows from the base directory of this repo on the EVM.


```
python3 ./apps_python/app_edgeai.py ./configs/barcode-reader.yaml
```

On the AM62A starter kit EVM, the barcode detection model uses yolox-nano architecture and runs at >100 fps. However, performance will slow down for more barcodes since each must be decoded individually, adding linear overhead. The fps for this application is likely to operate in the 15-20 fps range for 2+ barcodes in the field of view. This application can work on multiple types of barcodes, like QR codes and EAN-8.

There is [significant opportunity for improving](#room-for-improvement) the performance with more multiprocessing on the Arm CPU cores and by developing a more specific, optimized implementation of 1-D or 2-D barcode decoding.


### How It's Made

This section of the Readme describes how the application was developed.

A survey of research papers and other literature on barcode scanning showed that localizing the barcode takes substantially more processing than decoding. This makes the problem ripe for a 2-stage solution of 
1) deep learning for localization and 
2) conventional methods for decoding the barcode in a cropped region. We'll use an open-source library for this.

Note that since barcodes contain dense, highly structured information, developing a deep neural network that can decode this information directly is nigh-impossible given the size of the search space (2^NUM_BITS possible in the code space) without developing a very complex, custom architecture with a massive training dataset. Conventional means of *decoding* are more appropriate. 

#### Building a barcode-localization model

The first stage is building a model to localize a variety of barcode types. We selected among several public and openly licensed datasets found from Kaggle and a [github pointing to many existing labelled barcode datasets](https://github.com/BenSouchet/barcode-datasets).

After selecting several datasets, we realized these had inconsistent formats for labeling. TI's training tools use the COCO-JSON format, so we wrote a [(rough) script to "COCOify"](./training/COCOify_dataset.py) these datasets.  [A checker script](./training/cocovalidator.py) can check that the COCO json is valid and that referenced image files exist.
- Each of the selected datasets already had labels associated. We assume these labels are high enough quality to use, although they did need to be reformatted.
- Some datasets use segmentation masks instead of bounding boxes. We found an (unoptimized) algorithm online to extract bounding boxes from segmentation masks.
- One of the datasets used was very large and constructed of synthetic data. In fact, many barcode datasets in the research space use synthetically generated images with barcodes given the lack of otherwise publicly available datasets. These synthetic images typically less useful than real-world images, so we only selected a small percentage of those datasets for use within our own. 

The [data_manipulation.py](./training/data_manipulation.py) script performs operations like combining multiple COCO formatted datasets, making a test-train split, performing (heavy) augmentation. This produces outputs for training (with and without augmentation) and testing. 

A small set of images (25) were collected and manually labelled as well using [Edge AI Studio](https://dev.ti.com/edgeaistudio/). The entire dataset was around 1k images before augmentation, and we used 8k augmented images for training. 
- Note that augmentation is important! This significantly boosts accuracy and robustness. Comparing augmented and unaugmented training results, we see the accuracy improve by 16.5% on the distinct testing set (0.50 -> 0.58 mAP50-95) as well as performing noticeably better on live input.

The fully combined and augmented dataset was uploaded to Edge AI Studio, and the Yolox-nano model was trained using a batch size of 4 and 20 epochs. This trained model was then compiled and the artifacts were downloaded to the PC. 


##### Quick evaluation of barcode performance on large images

Additionally, we ran a test on the AM62A in a small standalone program to evaluate the performance boost of DL for localiztion + decoding on cropped image vs. decoding on the entire image (of which <1/20th had pixels relevant to a barcode). 

On a 1280x720 image, running zbar took around 120 ms and failed to find the QR code within the image. 

Alternatively, we ran the deep learning model to localize and crop an image to the barcode. The model ran in <10 ms and decoding on the small portion of the image with the QR code (approx. 100x100 pixels) took ~5ms. In this way, we see nearly 10x improvement in performance as well as improvement in accuracy. We did not find noticeable differences in performance between C++ and Python implementations.

We did note from this that when codes are turned, the bounding box coordinates resulting from the barcode-localization model will cut off corners, so additional space needs to be added to the original coordiantes prior to cropping. Running on a larger area increases compute time per zbar-call. 

#### Building the Application

The original repo from which this is forked, [edgeai-gst-apps](https://github.com/TexasInstruments/edgeai-gst-apps), handles the bulk of the work in creating this application. For the end-application, we wanted to simply show detection results from the deep learning model and print text to the screen corresponding to the code's data.

To accomplish this, all that's needed is to add logic to the post-processing code for either [C++](./apps_cpp/common/src/post_process_image_object_detect.cpp) or [Python](./apps_python/post_process.py). Here, we look at the bounding boxes for where barcodes should be and crop a section of the image to include that code. Then, we run the zbar library to decode the code within that image. The decoded text is drawn onto the image with OpenCV.

The rest of application (grab live input, preprocess, run the deep learning model, output final result to display/file) is handled by the rest of edgeai-gst-apps. To see another example that constructs a gstreamer pipeline for a more specific use-case (and thus, somewhat easier to interpret), please see the [retail-checkout repo](https://github.com/TexasInstruments/edgeai-gst-apps-retail-checkout).

#### Room for Improvement

The current program is not running at maximum efficiency. The detection model is running at >100 fps, but the rest of the pipeline is slower than this. Reasons for the bottleneck are as follows:
- Slow cameras: USB 2.0 cameras are generally limited at their max resolution. For instance, a C920 1080p webcam only produces 15 fps
- Too many detections: Many barcodes in the space will cause linear scaling due to more croppings and barcode-decoding API calls
- Drawing on images with CPU: OpenCV calls can add substantial latency

Accuracy for decoding is also not perfect. Reasons include:
- The barcode is oriented towards the cameras such that part of the code is cropped out based on the deep learning model detection
- We attempt to decode directly after cropping, without regard for rotations or perspective. Cropping to a larger area and running edge/corner detection before rotating and/or recropping may help improve decoding accuracy
- Calls to the decoding library are generic to the code type, such that many can be recognized. Selecting a particular one, like QR-codes, may substantially boost performance and accuracy
- Depending on the camera, the focus settings may cause the image to be blurry. This makes it difficult for the decoding library to distinguish where one bit/bar is in the code versus an adjacent one


## Resources


| Purpose | Link/Explanation | 
| ------- | ----- | 
|AM62A product page (superset) | https://www.ti.com/product/AM62A7 
| AM62A Starter Kit EVM | https://www.ti.com/tool/SK-AM62A-LP 
| EVM Supporting documentation | https://dev.ti.com/tirex/explore/node?node=A__AA3uLVtZD76DOCoDcT9JXg__am62ax-devtools__FUz-xrs__LATEST
| Master Edge AI page on Github |  https://github.com/TexasInstruments/edgeai 
| Edge AI Cloud | https://dev.ti.com/edgeaistudio/
| Model Analyzer | Allows viewing of benchmarks and real-time evaluation on a 'server farm' of Edge-AI capable EVMs
| Model Composer | Allows data capture, data labelling, model selection, model training, and model compilation
| Edge AI Academy for new developers | https://dev.ti.com/tirex/explore/node?node=A__AN7hqv4wA0hzx.vdB9lTEw__EDGEAI-ACADEMY__ZKnFr2N__LATEST
| AM62A Processor SDK | https://www.ti.com/tool/PROCESSOR-SDK-AM62A
| Edge AI Linux SDK Documentation | https://software-dl.ti.com/jacinto7/esd/processor-sdk-linux-edgeai/AM62AX/latest/exports/docs/devices/AM62AX/linux/index.html
| AM62A Academy | https://dev.ti.com/tirex/explore/node?node=A__AB.GCF6kV.FoXARl2aj.wg__AM62A-ACADEMY__WeZ9SsL__LATEST
| AM62A Design Gallery | https://dev.ti.com/tirex/explore/node?node=A__AGXaZZe9tNFAfGpjXBMYKQ__AM62A-DESIGN-GALLERY__DXrWFDQ__LATEST
| e2e Support Forums | https://e2e.ti.com



[^1]: This deep learning model for barcode localization is not production grade and is provided as is. TI provides no claims or guarantees about the accuracy of this model or its usage in commercial applications. This model is intended for evaluation only.
