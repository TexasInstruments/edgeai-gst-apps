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
import math


class Dashboard:
    """
    Create and update a graphical dashboard for object detection models. 
    The created dashboard consists of an over view and a histogram graph. The overview contains three numbers Total production [Units], percentage of defects units [%], and rate of productions as [Units/Hour]. The histogram shows a graph bar of the types of detected defects.
    """
    def __init__(self,overview, val, title):
        """
        Initialize dashboard. 
        Parameters:
            overview (list): List of three integers for Total production, defect percentage, production rate.
            val (list): List of integers for the number of detected objects for each defected class. Its length should be equal to the number of defected classes.
            title (list): Names of each of the defected classes. Its length should be equal to val
        """
        self.overview = overview
        self.graph_val = val
        self.graph_title = title
        # read the template used as a background of the dashboard.
        self.template = cv2.imread('dashboard_template.png')
        self.template = cv2.cvtColor(self.template, cv2.COLOR_BGR2RGB)
        self.dashboard = copy.deepcopy(self.template)
        # add the received data to the dashboard.
        self.update_dashboard(self.overview, self.graph_val, self.graph_title)
    

    def update_dashboard(self, overview, val, title):
        """
        Add the input data data to the dashboard.
        Parameters:
            overview (list): List of three integers for Total production, defect percentage, production rate.
            val (list): List of integers for the number of detected objects for each defected class. Its length should be equal to the number of defected classes.
            title (list): Names of each of the defected classes. Its length should be equal to val
        """
        self.overview = overview
        self.graph_val = val
        self.graph_title = title
        self.dashboard = self.add_overview_values(self.template, self.overview)
        bar_graph = self.create_bar_graph(450,539, self.graph_val, self.graph_title)
        # overlay the bar graph on the dashboard template.
        self.dashboard[260:710, 10:549, :] = bar_graph
        

    def create_image(self, h,w,color):
        """
        Create a colored image and fill it with a single color.
        Parameters:

            h (int): image height.
            w (int): image width.
            color (tuple): three integers representing the color as RGB.
        """
        image = np.zeros((h, w, 3), np.uint8)
        image[:] = color
        return image

    def add_overview_values(self, image, overview):
        """
        Overlay overview values on the dashboard.
        Parameters:
            image (numpy array): three dimensional array representing the dashboard template.
            overview (list): List of three integers for Total production, defect percentage, production rate.
        Returns:
            im (numpy array): the templated with overview numbers overlaid on it.
        """
        # extract overview values.
        total = overview[0]
        defect = overview[1]
        rate =  overview[2]
        im = copy.deepcopy(image)
        number_color = (0,0,0)

        # overlay Total 
        (text_w, text_h),_ = cv2.getTextSize(str(total), cv2.FONT_HERSHEY_DUPLEX, 1.5, 2)
        text_start = 20 + int((166- text_w)/2)
        cv2.putText(im, str(total),(text_start,130) , cv2.FONT_HERSHEY_DUPLEX, 1.5, number_color, 2)

        # overlay Defect percentage
        (text_w, text_h),_ = cv2.getTextSize(str(defect), cv2.FONT_HERSHEY_DUPLEX, 1.5, 2)
        text_start = 195 + int((166- text_w)/2)
        cv2.putText(im, str(defect),(text_start,130) , cv2.FONT_HERSHEY_DUPLEX, 1.5, number_color, 2)

        # overlay Production rate
        (text_w, text_h),_ = cv2.getTextSize(str(rate), cv2.FONT_HERSHEY_DUPLEX, 1.5, 2)
        text_start = 370 + int((166- text_w)/2)
        cv2.putText(im, str(rate),(text_start,130) , cv2.FONT_HERSHEY_DUPLEX, 1.5, number_color, 2)
        return im

    def create_bar_graph(self, h,w,val,tiltes):
        """
        Create a histogram as a bar graph.
        Parameters:
            h (int): height of the generated graph.
            w (int): width of the generated graph.
            val (list): List of integers for the number of detected objects for each defected class. Its length should be equal to the number of defected classes.
            titles (list): Names of each of the defected classes. Its length should be equal to val 
        Returns:
            numpy array: the generated graph as a three dimensional array.
        """
        # color palette for the bars
        bar_colors = [(255, 179, 179),
                     (255, 129, 128),
                     (255, 78, 77),
                     (255, 28, 26),
                     (179, 2, 0),
                     (77, 1, 0)]
        back_ground_color = (255,255,255)
        text_color = (0,0,0)
        ticket = self.create_image(h,w,back_ground_color)

        # normalize values
        if max(val) > 0:
            norm_val = [float(i)/max(val) for i in val]
        else:
            norm_val = val


        title_h = 80
        top_number_h = 40
        max_bar_h = h-title_h - top_number_h

        total_bar_w = w -10
        bar_w = 0

        # sort values ang get index to select color
        sort_val_id1 = [i for i, x in sorted(enumerate(val), key=lambda x: x[1])]
        sort_val_id2 = [i for i, x in sorted(enumerate(sort_val_id1), key=lambda x: x[1])]

        for i in range(len(val)):
            bar_h = int(max_bar_h * norm_val[i])
            bar_w = int(total_bar_w/len(val) - 10)

            # draw bar
            x1 = int(10 + i * (bar_w +10))
            x2 = int(x1 + bar_w)
            y1 = int(h - title_h - bar_h)
            y2 = int(h - title_h)

            cv2.rectangle(ticket, (x1, y1), (x2, y2), bar_colors[sort_val_id2[i]], -1)

            # add number above bar
            (text_w, text_h),_ = cv2.getTextSize(str(val[i]), cv2.FONT_HERSHEY_DUPLEX, 1, 2)
            text_start = x1 + int((bar_w - text_w)/2)
            cv2.putText(ticket, str(val[i]),(text_start,y1-5) , cv2.FONT_HERSHEY_DUPLEX, 1, text_color, 2)

            # add class names (titles)
            y0 = h-((title_h-10)/2) -10
            for j, line in enumerate(tiltes[i].split(' ')):

                (text_w, text_h),_ = cv2.getTextSize(line, cv2.FONT_HERSHEY_DUPLEX, 1, 2)
                text_start = x1 + int((bar_w - text_w)/2)
                y = int(y0 + j*(text_h+10))
                cv2.putText(ticket, line,(text_start,y) , cv2.FONT_HERSHEY_DUPLEX, 1, text_color, 2)


        return ticket

    
    def overlay_dashboard(self,frame):
        """
        Add (concatenate) the dashboard to the left side of the frame.
        Parameters:
            frame (numpy array): a three dimensional array representing the frame (image).
        Returns:
            (numpy array): a three dimensional array of the frame with the dashboard to the left sad of it.
        """
        
        frame_h = frame.shape[0]
        frame_w = frame.shape[1]

        frame_x1 = math.floor(frame_w/2 - 360)
        frame_x2 = frame_x1 + 720
        frame_y1 = math.floor(frame_h/2 - 360)
        frame_y2 = frame_y1 + 720
        
        framex = copy.deepcopy(frame)
        framex[0:720,0:560,:] = self.dashboard
        framex[0:720,560:1280,:]= frame[frame_y1:frame_y2,frame_x1:frame_x2,:]
        return framex
   