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

This script to for data manipulation in preparation for a deep learning object detection model
Data is required to be in COCO JSON format for bounding boxes.

The data used for this food-detection model project was labelled with label studio on two separate computers, and required merging of the JSON files.
Additionally, augmenting the data will expand the dataset without requiring additional labelling
  The imgaug library is effective for this, especially because it ensures bounding boxes cover the same area, even if there are rotations, flips, or resolution changes.
  
Most files are assumed to exist in a subdirectory called "workspace"
'''
import os, sys, shutil
import time
import numpy as np
import cv2 as cv
import json
import imgaug as ia
import imgaug.augmenters as iaa
from imgaug.augmentables.bbs import BoundingBox, BoundingBoxesOnImage
import random
import copy

from pprint import pprint

random.seed(time.time_ns())

# General format of the annotationbs (i.e. bounding boxes) and images
## each annotation has its own ID independent of the image
annotation_template =  {"id": -1, "image_id": -2, "category_id": -1, "segmentation":[], "bbox":None, "ignore":0, "iscrowd": 0, "area":0} # bbox = [x,y,w,h]
img_template = {"width":-1, "height":-1, "id": 12345, "file_name":"filename.jpg"}


TRAIN_TEST_SPLIT = 0.8

def clear_dir(files=[], dir=None, base_path='./'):
    '''
    Delete the set of files or clear the provided directory. 
    A base path can be provided in case the file path is not relative to the current directory
    This is mainly used to delete augmented files or temperatory working directories

    Returns None
    '''
    print('clear files from ' + str(dir) + ' and/or #files: ' + str(len(files)))
    for f in files:
        # print('remove ' + f)
        try: os.remove(os.path.join(base_path, f))
        except Exception as e: 
            print('Could not delete file: ' + f)
            raise e
    if dir is not None:
        files = os.listdir(dir)
        clear_dir(files=files, dir=None, base_path=os.path.join(base_path, dir)) # doesn't work for subdirs... todo


def copy_files(image_files, dataset_dir, output_subdir, is_train=True):
    '''
    Copy a set of image_files, generally for making a training and test split

    param image_files: list of image filenames to copy
    param dataset_dir: The base path of the dataset to copy files into
    param output_subdir: A subdirectory to put the files into (after 'train' or 'test')
    param is_train: boolean. If true, output files go into dataset_dir/train/output_subdir/FILENAME. Else, "train" is replaced with "test"

    Returns None
    '''
    print('Make directory')
    train_test_str = 'train' if is_train else 'test'

    # make the directory with an OS system call. Only works in linux
    cmd = f'mkdir -p {os.path.join(dataset_dir, train_test_str, output_subdir)}'
    os.system(cmd)

    for img_f in image_files:
        # source ID help make sure data coming from test/train/validation folders don't end up with naming conflicts. train is '0'

        try: assert os.path.exists(img_f)
        except: print(f'path to image "{img_f}" does not exist'); return

        in_filename_no_dir = img_f.split('/')[-1]
        output_filename = os.path.join(dataset_dir, train_test_str, output_subdir) + '/' + output_subdir + '_' + in_filename_no_dir
        output_filename = output_filename.lower()

        shutil.copy(img_f, output_filename)



def count_instance_per_class(annotations, categories):
    '''
    Count the number of instances for each class given a list of COCO-format annotations.
    There may be multiple instances of a class within a single image. Does not check if the image exists/is valid or not - that is assumed.

    categories is assumed to be in COCO JSON format as well: a list of dictionaries/JSON objects with a 'name' entry for the classes's name

    Returns a dictionary with classnames as keys and # of instances as values
    '''

    instances = {cat['name']:0 for cat in categories}

    for anno in annotations:
        inst = anno['category_id']
        cat = categories[inst]
        if cat['id'] == inst:
            instances[cat['name']] += 1
        else:
            raise ValueError()

    pprint(instances)
    return instances


def draw_rectangles_on_image(original_image, bounding_boxes, show_image=False):
    '''
    Draws boxes on an image with opencv. Used for asserting that BB's are correct, especially post augmentation. No files are saved.

    param original_image: the image to draw boxes on. This image is not altered, but is copied
    param bounding_boxes: a list of boxes to draw. May be in imgaug format (BoundingBox) or a 4-tuple. 4-tuple is assumed to be (x1, y1, width, height)
    param show_image: If set to true, will display the image before and after boxes are drawn. Hit any key to move to move onto the next image.
    '''
    image = original_image.copy()
    if show_image:  
        cv.imshow('w', image)
        cv.waitKey(0)

    for b in bounding_boxes:
        print(b)
        if isinstance(b, BoundingBox):
            image = cv.rectangle(image, (b.x1,b.y1), (b.x2,b.y2), (255,255,255), 4)
        else: 
            print((int(b[0]), int(b[1])),  (int(b[0]+b[2]), int(b[1]+b[3])))
            image = cv.rectangle(image, (int(b[0]), int(b[1])),  (int(b[0]+b[2]), int(b[1]+b[3])), (255,255,255), 4)

    if show_image:
        cv.imshow('w', image)
        cv.waitKey(0)

    return image


def do_split(images_with_annotations, split_values=TRAIN_TEST_SPLIT, info=None, training_dir='./workspace/training/images', testing_dir='./workspace/testing/images', input_dir='./workspace/combine', clear_dirs=True):
    '''
    Make a training/test split of the data. This should be done before performing augmentations to avoid contaminating the testing set. This will copy the data and return two corresponding COCO JSON format python dicts and two similar dicts in images_with_annotations style format.

    param images_with_annotations: dictionary using image_id as a key, and value contains full image JSON object and a list of annotations (JSON objects); all COCO format. This is easier to work with 
    param split_values: a [0,1] float representing the proportion of data used for training. The rest is set aside for testing
    param info: The 'info' portion of the COCO JSON object that needs to be copied into both output objects
    param training_dir: Where to put training data
    param testing_dir: Where to put testing data 
    param clear_dirs: delete all files within the training_dir and testing_dir to avoid duplicates in case a different random seed is used for the split.

    Returns: 
      training_data: COCO JSON format for the training set
      testing_data: COCO JSON format for the testing set
      training_dict: images_with_annotations format for training set
      testing_dict: images_with_annotations format for testing set
      
    '''
    assert split_values <= 1.0 and split_values >= 0 
    
    keys = list(images_with_annotations.keys())
    random.shuffle(keys)

    training_end_ind = int(len(keys) * split_values)

    training_keys = keys[:training_end_ind]
    testing_keys = keys[training_end_ind:]


    #clear training directory and copy data in (with fixed annotations)
    training_dict = {k: images_with_annotations[k] for k in training_keys}
    if not os.path.exists(training_dir): os.makedirs(training_dir)
    if clear_dirs: clear_dir(dir=training_dir)

    #copy the training set and update the filename 
    for tk in training_keys:
        training_filename = training_dict[tk]['file_name'].split('/')[-1]
        training_path = os.path.join(training_dir, training_filename)
        original_path = os.path.join(input_dir, training_dict[tk]['file_name'])
        shutil.copy(original_path, training_path)
        training_dict[tk]['file_name'] = training_filename



    #clear testing directory and copy data in (with fixed annotations)
    testing_dict = {k: images_with_annotations[k] for k in testing_keys}
    if not os.path.exists(testing_dir): os.makedirs(testing_dir)
    if clear_dirs: clear_dir(dir=testing_dir)

   # copy testing set and update the filename
    for tk in testing_keys:
        testing_filename = testing_dict[tk]['file_name'].split('/')[-1]
        testing_path = os.path.join(testing_dir, testing_filename)
        original_path = os.path.join(input_dir, testing_dict[tk]['file_name'])
        shutil.copy(original_path, testing_path)
        testing_dict[tk]['file_name'] = testing_filename


    training_data = dissociate_anno_with_images(training_dict)
    testing_data = dissociate_anno_with_images(testing_dict)

    training_data['info'] = info #include because it apparently has to be there to train..
    testing_data['info'] = info

    return training_data, testing_data, training_dict, testing_dict


def do_augmentations(images_with_annotations, image_dir, output_dir='workspace/augmented/images', clear_augmented_files=True, num_augs_per_original=5):
    '''
    Perform data augmentations to expand the dataset and add noise/improve robustness without requiring additional labeling

    param images_with_annotations: dictionary of image-ids as keys, value is image JSON object and list of associated annotation JSONs
    param output_dir: directory to put augmented files (and copy of originals)
    param clear_augmented_files: If true, deletes all augmented images based on assumed filename structure
    param num_augs_per_original: number of additional copies to make of an image to apply augmentations to

    Returns dictionary in similar images_with_annotations format, but including all the new images and annotations. New images are written to file.
    '''

    # Make a full copy here to avoid muddying the original
    images_with_anno_aug = copy.deepcopy(images_with_annotations)

    num_files = len(images_with_annotations)
    num_augs = num_files * num_augs_per_original

    print('Performing %d augmentations' % num_augs)

    if not os.path.exists(output_dir):
        os.makedirs(output_dir)

    if clear_augmented_files:
        print(output_dir)
        clear_dir(dir=output_dir)


    ia.seed(int(time.time_ns()))

    # Perform the following augmentations sequentially. Most are given a random change of occuring
    augmentor = iaa.Sequential([ 
        iaa.Fliplr(0.25),
        iaa.Flipud(0.15),
        iaa.Sometimes(0.1, iaa.PerspectiveTransform(scale=(.01, 0.15))),
        iaa.Sometimes(0.1, iaa.imgcorruptlike.GaussianBlur(severity=2)),
        iaa.Sometimes(0.1, iaa.imgcorruptlike.GaussianNoise(severity=1)),
        iaa.Sometimes(0.1, iaa.imgcorruptlike.MotionBlur(severity=2)),
        iaa.Sometimes(0.1, iaa.imgcorruptlike.Contrast(severity=1)),
        iaa.Sometimes(0.1, iaa.AddToSaturation((-15, 15))),
        iaa.Sometimes(0.1, iaa.imgcorruptlike.JpegCompression(severity=1)),
        iaa.Sometimes(0.25, iaa.Rot90((1,3))),
        iaa.Sometimes(0.1, iaa.pillike.Autocontrast((10,15), per_channel=True)),
        iaa.Sometimes(0.20, iaa.GammaContrast((0.2, 1.6))),
        iaa.Sometimes(0.1, iaa.Sharpen(alpha=(0, 1.0), lightness=(0.75, 1.5))),
        iaa.Sometimes(0.1, iaa.MultiplyHueAndSaturation(mul_hue=(0.75, 1.25))),
        iaa.Sometimes(0.1, iaa.ChangeColorTemperature((4000, 7000)))
    ], )
    
    # image-id's and annotation id's within the JSON object MUST be unique, so find the largest one and work up from there. 
    ## There is no guarantee the list of id's are sequential, so using size/len does not work.
    next_image_id = find_max_id(list(images_with_annotations.values()))+1
    next_anno_id = find_max_id(dissociate_anno_with_images(images_with_annotations)['annotations'])+1

    for key in images_with_annotations.keys():
        # key is the image's id
        im = images_with_annotations[key]

        # for imgaug to maintain the bounding boxes on the new images, those need to be collected and associated before applying the augmentations
        box_list = []
        for anno in im['annotations']:
            b = anno['bbox']
            #COCO uses [x,y,w,h] format, BoundingBox uses [x1,y1,x2,y2]
            box_list.append(BoundingBox(b[0], b[1], b[0]+b[2], b[1]+b[3]))
        #associate teh list of boxes with an image's dimensions
        bb_on_image = BoundingBoxesOnImage(box_list, shape=(im['height'], im['width']))

        image_filepath = os.path.join(image_dir, im['file_name'])
        assert(os.path.exists(image_filepath)), image_filepath
        img = cv.imread(image_filepath)

        for i in range(num_augs_per_original):
            #generate the augmented image and potentially modified box coords
            img_aug, bbs_aug = augmentor(image=img, bounding_boxes=bb_on_image)

            #set of annotations for a newly augmented image        
            annos = []
            for j, b in enumerate(bbs_aug):
                #force the bounding box to be within image bounds
                x1 = min(max(b.x1, 0), img_aug.shape[1])
                y1 = min(max(b.y1, 0), img_aug.shape[0])
                x2 = max(0, min(b.x2, img_aug.shape[1])) #order of these ops shouldn't matter..
                y2 = max(0, min(b.y2, img_aug.shape[0]))

                #check if annotation is worth saving, i.e. it exists within the image
                if not (b.is_fully_within_image(img_aug.shape) or b.is_partly_within_image(img_aug.shape)) or int(x2-x1) == 0 or int(y2-y1) == 0:
                    continue 

                #sometimes coordinates can flip; assert x1<x2 and y1<y2               
                if x2 < x1: x1, x2 = x2, x1
                if y2 < y1: y1, y2 = y2, y1
                new_b = [int(x1), int(y1), int(x2-x1), int(y2-y1)]

                existing_anno = im['annotations'][j]
                # create a new annotation for this
                anno = {
                    "id": next_anno_id,
                    "image_id": next_image_id,
                    "category_id": existing_anno['category_id'],
                    "segmentation": [],
                    "bbox": new_b,
                    "ignore": 0,
                    "iscrowd": 0,
                    "area": int(new_b[2] * new_b[3])
                }
                annos.append(anno)
                next_anno_id += 1

            # concoct a new filename. Include '_aug' to denote it's augmented 
            aug_filename = im['file_name'].split('/')[-1].replace('.', '_aug' + str(i) + '_.')
            aug_filepath = os.path.join(output_dir,aug_filename)
            cv.imwrite(aug_filepath, img_aug)
            
           # create the new dict/JSON object for the image and provide the associated annotations
            new_image_entry = {
                'file_name': aug_filename,
                'id': next_image_id,
                'height': img_aug.shape[0],
                'width': img_aug.shape[1],
                'annotations': annos
            }

            images_with_anno_aug[next_image_id] = new_image_entry
            next_image_id += 1

        #path to copy the original/unaugmented image to    
        updated_path = os.path.join(output_dir,im['file_name'].split('/')[-1])
        shutil.copy2(image_filepath, updated_path)
        # im['file_name'] = updated_path

    # Sanity check for repitiations
    check_for_id_repeats(list(images_with_anno_aug.values()))
    return images_with_anno_aug


def combine_datasets_labelstudio(input_dirs, output_dir):
    '''
    Combine together multiple datasets that are output from labelstudio. 
    Expecting exact format of labelstudio output, which is COCO JSON for annotations (result.json) and a directory of images called 'images'
    This function will ensure there are not reptitions in ID's for images or annotations
    
    param input_dirs: list of directories with datasets built from labelstudio 
    param output_dir: where to copy output files to such that it appears that all 

    Returns a new COCO JSON format dictionary describing the results.json
    '''

    if not os.path.exists(os.path.join(output_dir, 'images')):
        os.makedirs(os.path.join(output_dir, 'images'))

    categories = []
    images = []
    annotations = []
    info = {}

    for input_dir in input_dirs:
        with open(input_dir+'/result.json', 'r') as label_file:
            labels_dict = json.load(label_file)
            #make sure there are no conflicts between the classes/categories
            cat_arr = labels_dict['categories']
            for cat in cat_arr:
                if cat['id'] < len(categories):
                    if cat['name'] != categories[cat['id']]['name']:
                        raise ValueError(categories, cat) # will be raised if the categories arrays in all directories are not identical
                else: 
                    categories.append(cat)
            
            info = labels_dict['info'] #dirty, only keep the last one. assuming no real information, but still needs to be part of output file

    #restart the annotations from zero to ensure no conflicts.
    next_image_id = 0
    next_anno_id = 0
    for input_dir in input_dirs:
        #create a new set of images and annotations for just this direcotry
        new_images = {} #dictionary so we can associate old image id with new for the annotations
        new_annotations = []
        
        with open(input_dir+'/result.json', 'r') as label_file:
            labels_dict = json.load(label_file)

            image_list = labels_dict['images']            
            annotations_list = labels_dict['annotations']

            print('Working with new directory %s; current IDs are %d, %d for %d images, %d annotations' % (input_dir, next_image_id, next_anno_id, len(image_list), len(annotations_list)))

            for im in image_list:
                image_name = im['file_name'].split('/')[-1]
                existing_path = os.path.join(input_dir,'images', image_name)
                if os.path.exists(existing_path):
                    new_filename = os.path.join(output_dir, 'images', image_name)
                    if not os.path.exists(new_filename):
                        shutil.copy(existing_path, new_filename)
                        print('Copying file %s to %s' % (existing_path, new_filename))
                else:
                    # raise an error if a dataset mentions a non-existant file
                    raise ValueError(existing_path)

                old_image_id = im['id']
                #update the id and filename
                im['id'] = next_image_id
                im['file_name'] = image_name

                # the 'im' is all we need for the image's JSON description, but old_image_id is necessary to find it's corresponding annotations
                new_images[old_image_id] = im

                next_image_id += 1 

            #add everything in this new dictionary of image descriptions to the overall list
            images.extend(new_images.values())

            for anno in annotations_list:
                image_id = anno['image_id']
                assert anno['category_id'] < len(categories)
                # use the old image id to find the updated image's id
                new_image_id = new_images[image_id]

                anno['image_id'] = new_image_id['id']
                anno['id'] = next_anno_id
                next_anno_id += 1

                new_annotations.append(anno)

            annotations.extend(new_annotations)

    data_dict_coco = {'categories': categories, 'images':images,  'annotations': annotations, 'info': info}
    data_dict_coco['type'] = 'groundtruth/object-detection'


    return data_dict_coco

def add_null_images(data_dict, null_image_path):
    '''
    Add null (i.e., no annotations) into the dataset to help with robustness on scenes not seen within the dataset. Ideally, this would be quite large. Does not check if images are valid

    param data_dict: Full COCO format JSON/dict object
    null_image_path: path to directory full of images that contain no items that are being trained on. Assume path is valid relative to working directory

    Return: updated data_dict with null images added
    '''

    assert os.path.exists(null_image_path)

    null_image_files = os.listdir(null_image_path)

    image_id = len(data_dict['images'])

    for image in null_image_files:
        img = cv.imread(os.path.join(null_image_path, image))
        image_entry = {
            'id': image_id,
            'file_name': os.path.join(null_image_path, image),
            'width': img.shape[1],
            'height': img.shape[0]
        }
        data_dict['images'].append(image_entry)

        # pprint(image_entry)
        image_id += 1    

    return data_dict


def associate_anno_with_images(annotations, images):
    '''
    COCO JSON format has separate structures for annotations and images. These are easier to work with when an image and its annotations are kept in one structure (a dictionary). This function combines those together

    This is not an optimized function and will run slowly on large dataset

    param annotations: An annotations array in JSON COCO format
    param images: An images array in JSON COCO format

    Returns a dictionary using the image-id as the key. Each value contains the full image-json object and a list of annotations
    '''
    images_with_annotations = {}

    print('Associating %d images with %d annotations' % (len(images), len(annotations)))

    for i, image in enumerate(images):
        #image is the JSON object in COCO format representing the image, not an image file/array itself
        images_with_annotations[image['id']] = image
        images_with_annotations[image['id']]['annotations'] = []


    for anno in annotations:
        for image in images: 
            # double loop is slow, can probably be replaced by using image_id as key into full dict
            if anno['image_id'] == image['id']:
                images_with_annotations[image['id']]['annotations'].append(anno)
                break

    print('done associating')
    return images_with_annotations

def dissociate_anno_with_images(images_with_annotations):
    '''
    Undo the operation in complementary function, associate_anno_with_images
    Turns the format for function above back into COCO JSON format
    '''

    #avoid muddying anything that might still have purolse
    images_with_annotations_copy = copy.deepcopy(images_with_annotations)

    data_dict = {
        'images': [],
        'annotations': []
    }

    for key in images_with_annotations_copy.keys():
        image_with_anno = images_with_annotations_copy[key]
        anno = image_with_anno['annotations']
        del image_with_anno['annotations']
        data_dict['images']
        data_dict['images'].append(image_with_anno)
        data_dict['annotations'].extend(anno)

    # with open('test.json', 'w') as f : json.dump(data_dict, f, indent=2)
    return data_dict

def check_for_id_repeats(items):
    '''
    Assert that there are no repeat ID in the annotations or images

    Raises ValueError if therea repeats. Prints of those items will show above.

    Returns None
    '''
    unique_ids = {}
    is_err = False

    for item in items:
        if item['id'] in unique_ids:
            print(unique_ids[item['id']])
            print(item)
            print('\n')
            is_err = True
        else:
            unique_ids[item['id']] = item

    if is_err: raise ValueError('repeats present')
    else: print("No repeated IDs!")

def find_max_id(items):
    '''
    Find the max ID (which must be unique) in a list of dictionaries
    '''
    max_id = -1

    for item in items:
        if item['id'] > max_id:
            max_id= item['id']

    return max_id

if __name__ == '__main__':
    # set paths to files. Carefully avoid overwriting or mucking up a directory with hundreds of wrongfully copied files!
    #FIXME: add paths to datasets
    input_dirs = ["path to dataset 1", "path to dataset 2"]
    all_data_dir = './workspace/combine'
    # null_image_path = './workspace/null_images/'

    # Combine the datasets from multiple labeling sources into one big one.
    data_dict_coco = combine_datasets_labelstudio(input_dirs=input_dirs, output_dir=all_data_dir)
    with open(os.path.join(all_data_dir,'full_annotations.json'), 'w') as f:
        # no augmentations, no test-train split
        json.dump(data_dict_coco, f)
    # data_dict_coco = add_null_images(data_dict_coco, null_image_path)
    check_for_id_repeats(data_dict_coco['annotations'])

    instance_count  = count_instance_per_class(data_dict_coco['annotations'], data_dict_coco['categories'])

    # Convert the JSON objects (dicts) describing annotations into a format easier to work with
    images_with_annotations = associate_anno_with_images(data_dict_coco['annotations'], data_dict_coco['images'])
    print(len(images_with_annotations))

    # Do a training and test split. These will be copied to a new location. DO this before augmentation
    print('do test-train split')
    training_data_coco, testing_data_coco, training_dict, testing_dict = do_split(images_with_annotations, info=data_dict_coco['info'], clear_dirs=True, input_dir=os.path.join(all_data_dir, 'images'))
    print(len(training_data_coco['images']))
    print(len(testing_data_coco['images']))


    training_data_coco['categories'] = data_dict_coco['categories']
    testing_data_coco['categories'] = data_dict_coco['categories']

    aug_training_images_with_anno = do_augmentations(training_dict, os.path.join(all_data_dir, 'images'), num_augs_per_original=8)


    aug_training_data_coco = dissociate_anno_with_images(aug_training_images_with_anno)
    #Assert no repeats, else there will be errors raised during training
    check_for_id_repeats(aug_training_data_coco['annotations'])
    aug_training_data_coco['categories'] = data_dict_coco['categories']
    #even if 'info' is empty, it has to exist or training frameworks will complain
    aug_training_data_coco['info'] = data_dict_coco['info']
    aug_training_data_coco['type'] = data_dict_coco['type']

    # Dump all the COCO JSON dictionaries into the actual files
    with open(os.path.join(all_data_dir,'full_annotations.json'), 'w') as f:
        # no augmentations, no test-train split
        json.dump(data_dict_coco, f)

    with open('workspace/augmented/training_annotations_aug.json', 'w') as f:
        #training with augmentations
        json.dump(aug_training_data_coco, f)

    with open('workspace/training/training_annotations_no_aug.json', 'w') as f:
        #training without augmentations
        json.dump(training_data_coco, f)

    with open('workspace/testing/testing_annotations_no_aug.json', 'w') as f:
        #testing without augmentations
        json.dump(testing_data_coco, f)