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

import copy

class ObjectTracker:
    """
    Track objects in real time as they are detected by an AI model object detection model.
    """
    # Constants
    # Portion fo the upper and lower edges of the frame to be ignored to make sure that complete objects are within the frame. This should be changed depending on objects size's relative to the frame. 
    IGNOR_RANGE_Y = 0.1
    # Portions of left and right edges of the frame to be ignored. This is a temporary measure. This constant should be deleted after cropping is implemented.
    IGNOR_RANGE_X = 0.2
    # Number of times the object is detected before it is counted.
    DETECTED_THRESHOLD = 6
    # Number of times the object is miss-read before it is deleted from the tracked list of objects.
    NOT_DETECTED_THRESHOLD = 5
    # Number of times the object changes it is class before it is actually changes in the tracked list.
    CHANGE_CLASS_THRESHOLD = 4
    

    def __init__(self, model):
        self.model = model
        # list of tracked objects. This list will be dynamically updated as objects are added, deleted or updates.
        self.tracked_list = []
        # List to count the number of detected objects for each class. Class id's are used as indices to access elements in this lis.
        self.object_count = [0] * len(model.classnames)

    def track_objects(self, bbox):
        """
        Performs the main tracking algorithm. Update, add, delete objects in the tracked_list. Add detected objects to object_count
        Parameters:
            bbox (List): list of bounding boxes each as a numpy array defining bounding box coordinates and class name.
        Returns:
        int: Index of the nearest object in object_list to the input o, if no object is found to be close to o, return -1
        """

        # define objects in the current frame
        current_frame_objects = []
        
        # clean up the objects in the current frame.
        for b in bbox:
            temp_object = DetectedObject(b, self.model)
            # ignore upper and lower edge of the frame to make sure only complete objects are included.
            if temp_object.y_center > ObjectTracker.IGNOR_RANGE_Y and temp_object.y_center < (1- ObjectTracker.IGNOR_RANGE_Y):
                # ignore left and right  parts this is just a workaround of the crop
                if temp_object.x_center > ObjectTracker.IGNOR_RANGE_X and temp_object.x_center < (1- ObjectTracker.IGNOR_RANGE_X):
                    current_frame_objects.append(temp_object)     
        
        # loop over all objects in tracked_list
        for i in range(len(self.tracked_list)):
            # sort objects in current frame based on y_center
            current_frame_objects.sort(key=lambda x:x.y_center)

            # find index of nearest objects in the area lower than the tracked object
            ind = self.find_nearest(self.tracked_list[i], current_frame_objects)

            # if objects founds
            if ind >-1:
                # check if the same class
                if self.tracked_list[i].class_id == current_frame_objects[ind].class_id:
                    # replace coordinates from new object and delete new object
                    self.tracked_list[i].update_coordinates(current_frame_objects[ind])
                    self.tracked_list[i].not_detected = 0
                    self.tracked_list[i].change_class = 0
                    self.tracked_list[i].detected += 1
                    # delete new object in the current frame
                    del current_frame_objects[ind]
                # check if change class
                elif self.tracked_list[i].change_class > ObjectTracker.CHANGE_CLASS_THRESHOLD:
                    # replace as a new object.
                    self.tracked_list[i] = copy.deepcopy(current_frame_objects[ind])
                    del current_frame_objects[ind]
                else:
                    del current_frame_objects[ind]
                    self.tracked_list[i].change_class += 1
                    self.tracked_list[i].not_detected += 1

            # no related objects found in the current frame
            else:
                self.tracked_list[i].not_detected += 1
                self.tracked_list[i].change_class = 0
        
        # filter out objects not detected more than threshold
        filtered_tracked_list = list(filter(lambda o:o.not_detected < ObjectTracker.NOT_DETECTED_THRESHOLD, self.tracked_list))

        # add rest of objects in the current frame and not related to an existed object in the tracked list
        for i in range(len(current_frame_objects)):
            if current_frame_objects[i].y_center < 2*ObjectTracker.IGNOR_RANGE_Y:
                filtered_tracked_list.append(copy.deepcopy(current_frame_objects[i]))
                filtered_tracked_list[-1].detected +=1

        # add newly detected object to the counter if they passed detected threshold.
        for i in range(len(filtered_tracked_list)):
            if filtered_tracked_list[i].detected == ObjectTracker.DETECTED_THRESHOLD:
                self.object_count[filtered_tracked_list[i].class_id] +=1
                filtered_tracked_list[i].detected += 1

        # sort tracked list from high to low. Next frame starts detected object from bottom up
        filtered_tracked_list.sort(key=lambda x:x.y_center, reverse=True)
        
        self.tracked_list = filtered_tracked_list                   

    def find_nearest(self, o, object_list):
        """
        Find nearest object in frame_list to the object in o and return its index 
        if no objects found return -1
        Parameters:
            o (DetectedObject): Current tracked object
            object_list (list[DetectedObject]): List of objects in the current frame.
        Returns:
        int: Index of the nearest object in object_list to the input o, if no object is found to be close to o, return -1
        """
         
        index_list = []
        for i in range(len(object_list)):
             
            if object_list[i].x_center > o.x1 and object_list[i].x_center < o.x2 and object_list[i].y_center > (o.y_center -(o.y2-o.y1)/4) and object_list[i].y_center < (o.y2 + (o.y2 - o.y1)):
                index_list.append(i)
        
        if len(index_list) > 0:
            nearest_index = index_list[0]
        else:
            nearest_index = -1
        
        return nearest_index

class DetectedObject:
    """
    Hold detect object properties such as bounding box coordinates and class id with its related useful functions.
    """
    def __init__(self, bbox, model):
        """
        Initialize detect object properties. 
        Parameters:
            bbox (numpy array): array defining bounding box coordinates and class name.
        """
        self.x1 = bbox[0]
        self.x2 = bbox[2]
        self.y1 = bbox[1]
        self.y2 = bbox[3]
        self.x_center = self.x1 + (self.x2-self.x1)/2
        self.y_center = self.y1 + (self.y2-self.y1)/2
        self.not_detected = 0
        self.change_class = 0
        self.detected = 0
        self.class_id = int(bbox[4])
        if type(model.label_offset) == dict:
            #print("this is dic", model.classnames)
            self.class_name = model.classnames[model.label_offset[int(bbox[4])]]
        else:
            #print("this is NOT dic", model.classnames)
            self.class_name = model.classnames[model.label_offset + int(bbox[4])]
            
            
    def get_area(self):
        """
        Calculate bounding box area.
        Returns:
            (float or int): depending on the type of x1, x2, y1, y2, the return area can be as portion of the frame area or absolute area in pixels.
        """
        area = (self.x2-self.x1) * (self.y2-self.y1)
        return area
    
    def update_class(self, newObj):
        """
        Replace class_id of this object with the newObject.
        Parameters:
            newObj (DetectedObject) new object to replace class id with.
        """
        self.class_id = newObj.class_id

    def update_coordinates(self, newObj):
        """
        Replace coordinate of this object with input object.
        Parameters:
            newObj (DetectedObject): new object to replace coordinates with.
        """
        self.x1 = newObj.x1
        self.x2 = newObj.x2
        self.x_center = newObj.x_center
        self.y1 = newObj.y1
        self.y2 = newObj.y2
        self.y_center = newObj.y_center

    def coor_per2abs(self, frame_shape):
        """
        Change coordinate from portions of frame to absolute value depending on frame dimensions.
        Parameters:
            frame_shape (tuple): frames size (width, height, channels)
        """
        self.x1 = int(self.x1 * frame_shape[1])
        self.x2 = int(self.x2 * frame_shape[1])
        self.x_center = int(self.x_center * frame_shape[1])
        self.y1 = int(self.y1 * frame_shape[0])
        self.y2 = int(self.y2 * frame_shape[0])
        self.y_center = int(self.y_center * frame_shape[0])

    

