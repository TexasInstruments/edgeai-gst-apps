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

import cv2
import numpy as np
import copy
import debug

from time import time
import objects_tracker
import dashboard

np.set_printoptions(threshold=np.inf, linewidth=np.inf)


def create_title_frame(title, width, height):
    frame = np.zeros((height, width, 3), np.uint8)
    if title != None:
        frame = cv2.putText(
            frame,
            "Texas Instruments - Edge Analytics",
            (40, 30),
            cv2.FONT_HERSHEY_SIMPLEX,
            1.2,
            (255, 0, 0),
            2,
        )
        frame = cv2.putText(
            frame, title, (40, 70), cv2.FONT_HERSHEY_SIMPLEX, 1, (0, 0, 255), 2
        )
    return frame


def overlay_model_name(frame, model_name, start_x, start_y, width, height):
    row_size = 40 * width // 1280
    font_size = width / 1280
    cv2.putText(
        frame,
        "Model : " + model_name,
        (start_x + 5, start_y - row_size // 4),
        cv2.FONT_HERSHEY_SIMPLEX,
        font_size,
        (255, 255, 255),
        2,
    )
    return frame


class PostProcess:
    """
    Class to create a post process context
    """

    def __init__(self, flow):
        self.flow = flow
        self.model = flow.model
        self.debug = None
        self.debug_str = ""
        if flow.debug_config and flow.debug_config.post_proc:
            self.debug = debug.Debug(flow.debug_config, "post")

    def get(flow):
        """
        Create a object of a subclass based on the task type
        """
        if flow.model.task_type == "classification":
            return PostProcessClassification(flow)
        elif flow.model.task_type == "detection":
            return PostProcessDetection(flow)
        elif flow.model.task_type == "segmentation":
            return PostProcessSegmentation(flow)
        elif flow.model.task_type == "defect_detection":
            return PostProcessDefectDetection(flow)


class PostProcessClassification(PostProcess):
    def __init__(self, flow):
        super().__init__(flow)

    def __call__(self, img, results):
        """
        Post process function for classification
        Args:
            img: Input frame
            results: output of inference
        """
        results = np.squeeze(results)
        img = self.overlay_topN_classnames(img, results)

        if self.debug:
            self.debug.log(self.debug_str)
            self.debug_str = ""

        return img

    def overlay_topN_classnames(self, frame, results):
        """
        Process the results of the image classification model and draw text
        describing top 5 detected objects on the image.

        Args:
            frame (numpy array): Input image in BGR format where the overlay should
        be drawn
            results (numpy array): Output of the model run
        """
        orig_width = frame.shape[1]
        orig_height = frame.shape[0]
        row_size = 40 * orig_width // 1280
        font_size = orig_width / 1280
        N = self.model.topN
        topN_classes = np.argsort(results)[: (-1 * N) - 1 : -1]
        cv2.putText(
            frame,
            "Recognized Classes (Top %d):" % N,
            (5, 2 * row_size),
            cv2.FONT_HERSHEY_SIMPLEX,
            font_size,
            (0, 255, 0),
            2,
        )
        row = 3
        for idx in topN_classes:
            class_name = self.model.classnames.get(idx + self.model.label_offset)
            cv2.putText(
                frame,
                class_name,
                (5, row_size * row),
                cv2.FONT_HERSHEY_SIMPLEX,
                font_size,
                (255, 255, 0),
                2,
            )
            row = row + 1
            if self.debug:
                self.debug_str += class_name + "\n"

        return frame


class PostProcessDetection(PostProcess):
    def __init__(self, flow):
        super().__init__(flow)

    def __call__(self, img, results):
        """
        Post process function for detection
        Args:
            img: Input frame
            results: output of inference
        """
        for i, r in enumerate(results):
            r = np.squeeze(r)
            if r.ndim == 1:
                r = np.expand_dims(r, 1)
            results[i] = r

        if self.model.shuffle_indices:
            results_reordered = []
            for i in self.model.shuffle_indices:
                results_reordered.append(results[i])
            results = results_reordered

        if results[-1].ndim < 2:
            results = results[:-1]

        bbox = np.concatenate(results, axis=-1)

        if self.model.formatter:
            if self.model.ignore_index == None:
                bbox_copy = copy.deepcopy(bbox)
            else:
                bbox_copy = copy.deepcopy(np.delete(bbox, self.model.ignore_index, 1))
            bbox[..., self.model.formatter["dst_indices"]] = bbox_copy[
                ..., self.model.formatter["src_indices"]
            ]

        if not self.model.normalized_detections:
            bbox[..., (0, 2)] /= self.model.resize[0]
            bbox[..., (1, 3)] /= self.model.resize[1]

        for b in bbox:
            if b[5] > self.model.viz_threshold:
                if type(self.model.label_offset) == dict:
                    class_name = self.model.classnames[self.model.label_offset[int(b[4])]]
                else:
                    class_name = self.model.classnames[self.model.label_offset + int(b[4])]
                img = self.overlay_bounding_box(img, b, class_name)

        if self.debug:
            self.debug.log(self.debug_str)
            self.debug_str = ""

        return img

    def overlay_bounding_box(self, frame, box, class_name):
        """
        draw bounding box at given co-ordinates.

        Args:
            frame (numpy array): Input image where the overlay should be drawn
            bbox : Bounding box co-ordinates in format [X1 Y1 X2 Y2]
            class_name : Name of the class to overlay
        """
        box = [
            int(box[0] * frame.shape[1]),
            int(box[1] * frame.shape[0]),
            int(box[2] * frame.shape[1]),
            int(box[3] * frame.shape[0]),
        ]
        box_color = (20, 220, 20)
        text_color = (0, 0, 0)
        cv2.rectangle(frame, (box[0], box[1]), (box[2], box[3]), box_color, 2)
        cv2.rectangle(
            frame,
            (int((box[2] + box[0]) / 2) - 5, int((box[3] + box[1]) / 2) + 5),
            (int((box[2] + box[0]) / 2) + 160, int((box[3] + box[1]) / 2) - 15),
            box_color,
            -1,
        )
        cv2.putText(
            frame,
            class_name,
            (int((box[2] + box[0]) / 2), int((box[3] + box[1]) / 2)),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.5,
            text_color,
        )

        if self.debug:
            self.debug_str += class_name
            self.debug_str += str(box) + "\n"

        return frame


class PostProcessSegmentation(PostProcess):
    def __call__(self, img, results):
        """
        Post process function for segmentation
        Args:
            img: Input frame
            results: output of inference
        """
        img = self.blend_segmentation_mask(img, results[0])

        return img

    def blend_segmentation_mask(self, frame, results):
        """
        Process the result of the semantic segmentation model and return
        an image color blended with the mask representing different color
        for each class

        Args:
            frame (numpy array): Input image in BGR format which should be blended
            results (numpy array): Results of the model run
        """

        mask = np.squeeze(results)

        if len(mask.shape) > 2:
            mask = mask[0]

        if self.debug:
            self.debug_str += str(mask.flatten()) + "\n"
            self.debug.log(self.debug_str)
            self.debug_str = ""

        # Resize the mask to the original image for blending
        org_image_rgb = frame
        org_width = frame.shape[1]
        org_height = frame.shape[0]

        mask_image_rgb = self.gen_segment_mask(mask)
        mask_image_rgb = cv2.resize(
            mask_image_rgb, (org_width, org_height), interpolation=cv2.INTER_LINEAR
        )

        blend_image = cv2.addWeighted(
            mask_image_rgb, 1 - self.model.alpha, org_image_rgb, self.model.alpha, 0
        )

        return blend_image

    def gen_segment_mask(self, inp):
        """
        Generate the segmentation mask from the result of semantic segmentation
        model. Creates an RGB image with different colors for each class.

        Args:
            inp (numpy array): Result of the model run
        """

        r_map = (inp * 10).astype(np.uint8)
        g_map = (inp * 20).astype(np.uint8)
        b_map = (inp * 30).astype(np.uint8)

        return cv2.merge((r_map, g_map, b_map))
    
class PostProcessDefectDetection(PostProcess):
    def __init__(self, flow):
        super().__init__(flow)

        # initialize dashboard
        overview = [0,0,0]
        defects_num = [0,0,0]
        # extract class names from model
        self.defects_class_names = []
        for i in range(1,len(self.model.classnames)): 
            self.defects_class_names.append(self.model.classnames[i])

        # initialize dashboard
        self.db = dashboard.Dashboard(overview, defects_num, self.defects_class_names)

        # initialize object tracker
        self.ot = objects_tracker.ObjectTracker(self.model)

        # keep track of total products
        self.total_objects_start = 0
        # keep track of production rate
        self.prod_rate = 0
        # variables for production rate calculation
        # time at the beginning of a minute period
        self.start_minute = time()
        # total number of produced unites at a beginning of a minute
        self.prod_start_minute = 0

    def __call__(self, img, results):
        """
        Post process function for detection
        Args:
            img: Input frame
            results: output of inference
        """
        for i, r in enumerate(results):
            r = np.squeeze(r)
            if r.ndim == 1:
                r = np.expand_dims(r, 1)
            results[i] = r

        if self.model.shuffle_indices:
            results_reordered = []
            for i in self.model.shuffle_indices:
                results_reordered.append(results[i])
            results = results_reordered

        if results[-1].ndim < 2:
            results = results[:-1]

        bbox = np.concatenate(results, axis=-1)

        if self.model.formatter:
            if self.model.ignore_index == None:
                bbox_copy = copy.deepcopy(bbox)
            else:
                bbox_copy = copy.deepcopy(np.delete(bbox, self.model.ignore_index, 1))
            bbox[..., self.model.formatter["dst_indices"]] = bbox_copy[
                ..., self.model.formatter["src_indices"]
            ]

        if not self.model.normalized_detections:
            bbox[..., (0, 2)] /= self.model.resize[0]
            bbox[..., (1, 3)] /= self.model.resize[1]

        accepted_bbox = []
        for b in bbox:
            if b[5] > self.model.viz_threshold:
                accepted_bbox.append(b)

        if self.debug:
            self.debug.log(self.debug_str)
            self.debug_str = ""

        # track objects
        self.ot.track_objects(accepted_bbox)

        # calculate total objects
        total_objects = sum(self.ot.object_count)

        # calculate defect percentage
        if total_objects > 0:
            defect_objects = round((total_objects - self.ot.object_count[0])/total_objects * 100)
        else:
            defect_objects = 0

        # calculate production rate
        current_time = time()
        # make sure that a minute is passed
        if (current_time - self.start_minute) > 60:
            # number of products in the past minute
            prod_minute = total_objects - self.prod_start_minute
            # production rate in unites per hours, hens * 3600
            self.prod_rate = int((prod_minute / (current_time-self.start_minute)) * 3600)
            # set start of the next minute at the current time.
            self.start_minute = current_time
            # set number of products at the start of the next minute
            self.prod_start_minute = total_objects
        elif self.prod_start_minute == 0:
            self.prod_rate = total_objects

        overview = [total_objects, defect_objects, self.prod_rate]
        defects_num = self.ot.object_count[1:4]

        if (self.total_objects_start != total_objects):
                self.db.update_dashboard(overview, defects_num, self.defects_class_names)
                self.total_objects_start = total_objects

        out_frame = self.draw_boxex(img, self.ot.tracked_list)
        out_frame = self.db.overlay_dashboard(out_frame)

        return out_frame
    
    def draw_boxex(self, frame, box_list):
        """
        Draw bounding boxes on the frame. 
        Parameters:
            frame (numpy array): three dimensional array for the frame.
            box_list (list[DetectedObject]): a list of detected objects.
        """
        for b in box_list:
            if b.not_detected > 0:
                continue
            temp_b = copy.deepcopy(b)
            # update coordinates to match frame
            temp_b.coor_per2abs(frame.shape)
            bar_colors = [(255, 179, 179),
                     (255, 129, 128),
                     (255, 78, 77),
                     (255, 28, 26),
                     (179, 2, 0),
                     (77, 1, 0)]
            
            box_color = (20, 220, 20)
            if temp_b.class_id == 1:
                box_color = bar_colors[0]
            if temp_b.class_id == 2:
                box_color = bar_colors[2]
            if temp_b.class_id == 3:
                box_color = bar_colors[4]
            if temp_b.class_name =="Bad":
                box_color = (220, 20, 20)
        
            text_color = (0, 0, 0)
            cv2.rectangle(frame, (temp_b.x1, temp_b.y1), (temp_b.x2, temp_b.y2), box_color, 2)
            cv2.rectangle(
                frame,
                (temp_b.x_center - 5, temp_b.y_center + 5),
                (temp_b.x_center + 80, temp_b.y_center - 15),
                box_color,
                -1,
            )
            cv2.putText(
                frame,
                temp_b.class_name,
                (temp_b.x_center, temp_b.y_center),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.5,
                text_color,
            )
        return frame