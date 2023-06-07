import json, os
import argparse

parser = argparse.ArgumentParser()

parser.add_argument('-p', '--path', default='./workspace/bar-and-qr/result.json', help='path to the result.json file. Assumed that all images are relative to that file in a subdirectory called "images"')

args = parser.parse_args()

coco_file = args.path

with open(coco_file) as json_file:
  coco_data = json.load(json_file)
  
def assertions(key, values, required_keys, unique_key=None):
  unique_key_id_mapper = {}
  for value in values:
    if unique_key is not None:
      unique_key_id_mapper[value['id']] = value[unique_key]
    for required_key in required_keys:
      assert required_key in value, "'{}' does not contain the required key '{}'".format(key, required_key)
  return unique_key_id_mapper

def annotation_assertions(key, annotations, image_map, category_map):
  required_keys = ['area', 'iscrowd', 'bbox', 'category_id',  'segmentation', 'image_id', 'id']
  assertions('annotations', coco_data['annotations'], required_keys, None)
  epsilon = 0.01 #if bbox and area is floating point, we need to do 'isclose' type of comparison rather than equality
  for annotation in annotations:
    assert len(annotation['bbox']) == 4, "'{}' key in 'annotations' does not match the expected format".format('bbox')
    assert annotation['category_id'] in category_map, "'{}' is not present in the 'categories' mapping".format('category_id')
    assert annotation['image_id'] in image_map, "'{}' is not present in the 'images' mapping".format('image_id')
    assert abs(annotation['area'] - (annotation['bbox'][2] * annotation['bbox'][3])) < epsilon, "Mismatch of values in '{}' and '{}'".format('area', 'bbox')
    assert len(annotation['segmentation']) == 8 or len(annotation['segmentation']) == 0, "'{}' must either be an empty list or contain a list of 8 values".format('segmentation')
    assert annotation['iscrowd'] == 0 or annotation['iscrowd'] == 1, "'{}' must either be 0 or 1. {} is invalid".format('iscrowd', annotation['iscrowd'])

def image_assertions(images, basepath):
  '''
  Reese
  '''
  for image in images:
    file_name = image['file_name']
    path = os.path.join(basepath, file_name)
    # print(path)
    assert os.path.exists(path)

def main():
  required_keys = ['images', 'type', 'annotations', 'categories']
  for required_key in required_keys:
    assert required_key in coco_data.keys(), "Required key '{}' not found in the COCO dataset".format(required_key)
    assert len(coco_data[required_key]) > 0, "Required key '{}' does not contain values".format(required_key)

  image_map = assertions('images', coco_data['images'], ["file_name", "height", "width", "id"], "file_name")
  category_map = assertions('categories', coco_data['categories'], ["id", "name"], "name")
  annotation_assertions('annotations', coco_data['annotations'], image_map, category_map)

  #Reese
  basepath_parts = coco_file.split('/')[:-1]
  basepath_parts.append('images')
  basepath = ''
  for p in basepath_parts: 
    basepath = basepath+p+'/' 
  image_assertions(coco_data['images'], basepath)
  print('The dataset format is COCO!')

if __name__ == '__main__':
  main()