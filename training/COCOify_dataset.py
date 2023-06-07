'''
#  Copyright (C) 2023 Texas Instruments Incorporated - http://www.ti.com/
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

This file is made to "cocoify" a dataset by turning all labels into COCO JSON format,
placing all images into an 'images' subdirectory and the JSON file into 'result.json'
in the parent of those images.
'''

import os, sys, shutil
import time
import numpy as np
import cv2 as cv
import json
import random
import copy
from pprint import pprint
import math
import re
import pandas as pd

# https://pytorch.org/vision/main/auto_examples/plot_repurposing_annotations.html
import matplotlib.pyplot as plt
from torchvision.io import read_image

annotation_template =  {"id": -1, "image_id": -2, "category_id": -1, "segmentation":[], "bbox":None, "ignore":0, "iscrowd": 0, "area":0} # bbox = [x,y,w,h]
img_template = {"width":-1, "height":-1, "id": 12345, "file_name":"filename.jpg"}
categories = [{"id":0, "name": "code"}]

plt.rcParams["savefig.bbox"] = "tight"


def show(image, box):
    x,y,w,h = box
    print(x,y,w,h)
    image = cv.rectangle(image, (x,y), (x+w,y+h), (255,255,255), 4)
    image = cv.rectangle(image, (x,y), (x+w,y+h), (0,0,255), 2)
    if (max(image.shape) > 1080):
        image = cv.resize(image, (640,480))
    cv.imshow('w', image)
    cv.waitKey(0)

def convert_mask_to_box_huawei(maskpath, realpath=None, visualize=False):
    '''

    '''
    mask = read_image(maskpath)

    mask = mask[0,:,:] # 3 planes for no good reason

    mask = mask > 1
    print(mask)
    print(mask.shape)

    mask_tensor = mask
    print(mask_tensor.shape)
    boxes = mask_to_boxes_stackoverflow(mask_tensor)
    print(boxes)


def mask_to_boxes_stackoverflow(mask):
    """ 
    Source: https://stackoverflow.com/questions/73282135/computing-bounding-boxes-from-a-mask-image-tensorflow-or-other
    slow but useful algorithm

    Convert a boolean (Height x Width) mask into a (N x 4) array of NON-OVERLAPPING bounding boxes
    surrounding "islands of truth" in the mask.  Boxes indicate the (Left, Top, Right, Bottom) bounds
    of each island, with Right and Bottom being NON-INCLUSIVE (ie they point to the indices AFTER the island).

    This algorithm (Downright Boxing) does not necessarily put separate connected components into
    separate boxes.

    You can "cut out" the island-masks with
        boxes = mask_to_boxes(mask)
        island_masks = [mask[t:b, l:r] for l, t, r, b in boxes]
    """
    max_ix = max(s+1 for s in mask.shape)   # Use this to represent background
    print('max_ix')
    print(max_ix)
    # These arrays will be used to carry the "box start" indices down and to the right.
    x_ixs = np.full(mask.shape, fill_value=max_ix)
    y_ixs = np.full(mask.shape, fill_value=max_ix)

    # Propagate the earliest x-index in each segment to the bottom-right corner of the segment
    for i in range(mask.shape[0]):
        x_fill_ix = max_ix
        for j in range(mask.shape[1]):
            above_cell_ix = x_ixs[i-1, j] if i>0 else max_ix
            still_active = mask[i, j] or ((x_fill_ix != max_ix) and (above_cell_ix != max_ix))
            x_fill_ix = min(x_fill_ix, j, above_cell_ix) if still_active else max_ix
            x_ixs[i, j] = x_fill_ix

    # Propagate the earliest y-index in each segment to the bottom-right corner of the segment
    for j in range(mask.shape[1]):
        y_fill_ix = max_ix
        for i in range(mask.shape[0]):
            left_cell_ix = y_ixs[i, j-1] if j>0 else max_ix
            still_active = mask[i, j] or ((y_fill_ix != max_ix) and (left_cell_ix != max_ix))
            y_fill_ix = min(y_fill_ix, i, left_cell_ix) if still_active else max_ix
            y_ixs[i, j] = y_fill_ix

    # Find the bottom-right corners of each segment
    new_xstops = np.diff((x_ixs != max_ix).astype(np.int32), axis=1, append=False)==-1
    new_ystops = np.diff((y_ixs != max_ix).astype(np.int32), axis=0, append=False)==-1
    corner_mask = new_xstops & new_ystops
    y_stops, x_stops = np.array(np.nonzero(corner_mask))

    # Extract the boxes, getting the top-right corners from the index arrays
    x_starts = x_ixs[y_stops, x_stops]
    y_starts = y_ixs[y_stops, x_stops]
    ltrb_boxes = np.hstack([x_starts[:, None], y_starts[:, None], x_stops[:, None]+1, y_stops[:, None]+1])
    return ltrb_boxes


def COCOify_huawei(image_dir, mask_dir, dest_dir='workspace/huawei_dataset/'):

    if not os.path.exists(dest_dir): os.makedirs(dest_dir)
    if not os.path.exists(os.path.join(dest_dir, 'images')): os.makedirs(os.path.join(dest_dir, 'images'))

    image_files = os.listdir(image_dir)
    mask_files = os.listdir(mask_dir)

    image_files.sort()
    mask_files.sort()

    coco_json = {}
    coco_json['info'] = 'something informative'
    coco_json['categories'] = categories
    coco_json['type'] = 'groundtruth/object-detection'
    # coco_json['images'] = []
    # coco_json['annotations'] = []

    coco_images = []
    coco_annotations = []

    assert(len(image_files) ==  len(mask_files))

    # annotation_template =  {"id": -1, "image_id": -2, "category_id": -1, "segmentation":[], "bbox":None, "ignore":0, "iscrowd": 0, "area":0} # bbox = [x,y,w,h]
    # img_template = {"width":-1, "height":-1, "id": 12345, "file_name":"filename.jpg"}
    img_id = 0
    anno_id = 0

    for i in range(len(image_files)):
        image_path = os.path.join(image_dir, image_files[i])
        mask_path = os.path.join(mask_dir, mask_files[i])

        mask = cv.imread(mask_path)
        mask = mask[:,:,0] # RGB images that are actually grayscale. Only use 1 channel
        mask = mask > 1 #everything nonzero is considered of interest. It should be a binary mask but this dataset is not..

        boxes = mask_to_boxes_stackoverflow(mask)
        print(boxes)
        for box in boxes:
            x = int(box[0])
            y = int(box[1])
            w = int(box[2]-box[0])
            h = int(box[3]-box[1])
            anno = {"id": anno_id, "image_id": img_id, "category_id": 0, "bbox": [x,y,w,h], "area": w*h, "iscrowd": 0, "segmentation": [], "ignore": 0}
            anno_id += 1
            coco_annotations.append(anno)

        imagename = image_files[i]
        shutil.copy(image_path, os.path.join(dest_dir, 'images', imagename))
        img = {"id": img_id, "file_name": imagename, "width": mask.shape[1], "height": mask.shape[0]}
        img_id += 1
        coco_images.append(img)

        # break # temp for first test

    coco_json['images'] = coco_images
    coco_json['annotations'] = coco_annotations

    with open(os.path.join(dest_dir, 'result.json'), 'w') as f:
        json.dump(coco_json, f)
    print(coco_json)
    print('done!')
        

def COCOify_barQR_seg_dataset(image_dir, mask_dir, dest_dir='workspace/bar_and_QR/'):

    if not os.path.exists(dest_dir): os.makedirs(dest_dir)
    if not os.path.exists(os.path.join(dest_dir, 'images')): os.makedirs(os.path.join(dest_dir, 'images'))

    image_files = os.listdir(image_dir)
    mask_files = os.listdir(mask_dir)

    image_files.sort()
    mask_files.sort()

    coco_json = {}
    coco_json['info'] = 'something informative'
    coco_json['categories'] = categories
    coco_json['type'] = 'groundtruth/object-detection'
    # coco_json['images'] = []
    # coco_json['annotations'] = []

    coco_images = []
    coco_annotations = []

    # annotation_template =  {"id": -1, "image_id": -2, "category_id": -1, "segmentation":[], "bbox":None, "ignore":0, "iscrowd": 0, "area":0} # bbox = [x,y,w,h]
    # img_template = {"width":-1, "height":-1, "id": 12345, "file_name":"filename.jpg"}
    img_id = 0
    anno_id = 0

    for i in range(len(image_files)):
        image_path = os.path.join(image_dir, image_files[i])
        
        print(image_files[i])

        if not image_files[i] in mask_files:
            continue
        mask_path = os.path.join(mask_dir, image_files[i])
        assert os.path.exists(mask_path), mask_path

        mask = cv.imread(mask_path)
        image = cv.imread(image_path)
        mask = mask[:,:,0] # RGB images that are actually grayscale. Only use 1 channel
        mask = mask > 100 #everything nonzero is considered of interest. It should be a binary mask but this dataset is not..


        boxes = mask_to_boxes_stackoverflow(mask)
        print(boxes)
        for box in boxes:
            x = int(box[0])
            y = int(box[1])
            w = int(box[2]-box[0])
            h = int(box[3]-box[1])
            if w*h < 200: continue #sometimes interpolation artifacts break the algorithm. This can fix
            anno = {"id": anno_id, "image_id": img_id, "category_id": 0, "bbox": [x,y,w,h], "area": w*h, "iscrowd": 0, "segmentation": [], "ignore": 0}
            anno_id += 1
            coco_annotations.append(anno)
            # show(image, [x,y,w,h])

        imagename = image_files[i]
        shutil.copy(image_path, os.path.join(dest_dir, 'images', imagename))
        img = {"id": img_id, "file_name": imagename, "width": mask.shape[1], "height": mask.shape[0]}
        img_id += 1
        coco_images.append(img)

        # break # temp for first test

    coco_json['images'] = coco_images
    coco_json['annotations'] = coco_annotations

    with open(os.path.join(dest_dir, 'result.json'), 'w') as f:
        json.dump(coco_json, f)
    # print(coco_json)
    print('done!')
     

def COCOify_text_boundingboxes(image_dir, dest_dir):

    if not os.path.exists(dest_dir): os.makedirs(dest_dir)
    if not os.path.exists(os.path.join(dest_dir, 'images')): os.makedirs(os.path.join(dest_dir, 'images'))

    image_files = [f for f in os.listdir(image_dir) if '.jpg' in f]
    txt_files =  [f for f in os.listdir(image_dir) if '.txt' in f]

    image_files.sort()
    txt_files.sort()

    coco_json = {}
    coco_json['info'] = 'something informative'
    coco_json['categories'] = categories
    coco_json['type'] = 'groundtruth/object-detection'
    # coco_json['images'] = []
    # coco_json['annotations'] = []

    coco_images = []
    coco_annotations = []

    # annotation_template =  {"id": -1, "image_id": -2, "category_id": -1, "segmentation":[], "bbox":None, "ignore":0, "iscrowd": 0, "area":0} # bbox = [x,y,w,h]
    # img_template = {"width":-1, "height":-1, "id": 12345, "file_name":"filename.jpg"}
    img_id = 0
    anno_id = 0

    for i in range(len(image_files)):
        assert(image_files[i].split('.')[0] == txt_files[i].split('.')[0])

        image_path = os.path.join(image_dir, image_files[i])
        image = cv.imread(image_path)
        txt_path = os.path.join(image_dir, txt_files[i])

        with open(txt_path) as f:
            lines = f.readlines()

        for line in lines:
            print(line)
            _,x,y,w,h = line.split()[:5]
            bbox=[x,y,w,h]
            print(x,y,w,h)
            x = int(float(x) * image.shape[1])
            w = int(float(w) * image.shape[1])
            y = int(float(y) * image.shape[0])
            h = int(float(h) * image.shape[0])
            x1 = x-w//2
            x2 = x+w//2
            y1 = y-h//2
            y2 = y + h//2
            bbox=[x1,y1,w,h]

            print(x,y,w,h)
            image = cv.rectangle(image, (x1,y1), (x2,y2), (255,255,255), 4)
            # cv.imshow('w', image)
            # cv.waitKey(0)
            show(image, bbox)

            anno = {"id": anno_id, "image_id": img_id, "category_id": 0, "bbox": bbox, "area": w*h, "iscrowd": 0, "segmentation": [], "ignore": 0}
            anno_id += 1
            coco_annotations.append(anno)
        # break # temp for first test

        imagename = image_files[i]
        shutil.copy(image_path, os.path.join(dest_dir, 'images', imagename))
        img = {"id": img_id, "file_name": imagename, "width": image.shape[1], "height": image.shape[0]}
        img_id += 1
        coco_images.append(img)


    coco_json['images'] = coco_images
    coco_json['annotations'] = coco_annotations

    with open(os.path.join(dest_dir, 'result.json'), 'w') as f:
        json.dump(coco_json, f)
    print(coco_json)
    print('done!')

def get_annotations_and_images_csvlabel(data_dir, dest_dir, anno_idx, image_idx):
    '''
    Read the images and CSV to generate annotations, image_annotations, copy 
    images, and update teh anno_/image_idx values before returning
    '''
    image_files = [f for f in os.listdir(data_dir) if '.jpg' in f.lower()]
    label_files =  [f for f in os.listdir(data_dir) if '.csv' in f.lower()]

    image_files.sort()
    label_files.sort()

    # annotation_template =  {"id": -1, "image_id": -2, "category_id": -1, "segmentation":[], "bbox":None, "ignore":0, "iscrowd": 0, "area":0} # bbox = [x,y,w,h]
    # img_template = {"width":-1, "height":-1, "id": 12345, "file_name":"filename.jpg"}
    annotations = []
    images = []

    for i in range(len(image_files)):
        image_f = image_files[i]
        label_f = label_files[i]
        assert image_f.split('.')[0] in label_f, "%s, %s" % (image_f, label_f)

        label_path = os.path.join(data_dir, label_f)
        print(label_path)
        label_data = pd.read_csv(label_path)
        image_path = os.path.join(data_dir, image_f)
        image = cv.imread(image_path)

        for index, row in label_data.iterrows():

            x = index
            y = row.iloc[0]
            r = row.iloc[1]
            x = max(x-r, 0)
            y = max(y-r, 0)
            w = 2*r
            h = 2*r
            bbox = [x,y,w,h]
            image_path = os.path.join(data_dir, image_f)
            # show(image, [x,y,w,h])
            anno = {"id": anno_idx, "image_id": image_idx, "category_id": 0, "bbox": bbox, "area": w*h, "iscrowd": 0, "segmentation": [], "ignore": 0}
            annotations.append(anno)
            anno_idx += 1

        imagename = image_path.split('/')[-1]
        new_path = os.path.join(dest_dir, 'images', imagename)
        print(new_path)
        assert not os.path.exists(new_path)
        shutil.copy(image_path, new_path)
        img = {"id": image_idx, "file_name": imagename, "width": image.shape[1], "height": image.shape[0]}
        image_idx += 1
        images.append(img)


    return annotations, images, anno_idx, image_idx

def COCOify_qrcode_dataset_csvlabel(image_dir, dest_dir):

    if not os.path.exists(dest_dir): os.makedirs(dest_dir)
    if not os.path.exists(os.path.join(dest_dir, 'images')): os.makedirs(os.path.join(dest_dir, 'images'))

    dirs = os.listdir(image_dir)


    coco_json={}
    coco_json['info'] = 'something informative'
    coco_json['categories'] = categories
    coco_json['type'] = 'groundtruth/object-detection'
    # coco_json['images'] = []
    # coco_json['annotations'] = []

    coco_images = []
    coco_annotations = []

    # annotation_template =  {"id": -1, "image_id": -2, "category_id": -1, "segmentation":[], "bbox":None, "ignore":0, "iscrowd": 0, "area":0} # bbox = [x,y,w,h]
    # img_template = {"width":-1, "height":-1, "id": 12345, "file_name":"filename.jpg"}
    img_id = 0
    anno_id = 0

    for i in range(len(dirs)):
        print(dirs[i])
        annotations, images, anno_id, img_id = get_annotations_and_images_csvlabel(os.path.join(image_dir, dirs[i]), dest_dir, anno_id, img_id)
        coco_annotations.extend(annotations)
        coco_images.extend(images)

    coco_json['images'] = coco_images
    coco_json['annotations'] = coco_annotations

    with open(os.path.join(dest_dir, 'result.json'), 'w') as f:
        json.dump(coco_json, f)
    print(coco_json)
    print('done!')
      

if __name__ == '__main__':

    COCOify_barQR_seg_dataset('bar&QRCode-seg-dataset/barqrcode/pic', 'bar&QRCode-seg-dataset/barqrcode/segmentation', 'workspace/bar-and-qr/')

    COCOify_qrcode_dataset_csvlabel('./qrcode-datasets-labelled/qrcode-datasets/datasets', dest_dir='workspace/qr')
    COCOify_text_boundingboxes('./oneDBarcode-1D-real-products', dest_dir='workspace/oneDBarcode')
    COCOify_text_boundingboxes('./inventbarcode-1Dbarcode-real-products', dest_dir='workspace/inventbarcode')
    COCOify_huawei('./syn10k_plus_huawei/huawei', './syn10k_plus_huawei/huawei_gt', dest_dir='workspace/huawei/')

    exit()
