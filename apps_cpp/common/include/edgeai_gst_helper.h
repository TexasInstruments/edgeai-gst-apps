/*
 *  Copyright (C) 2022 Texas Instruments Incorporated - http://www.ti.com/
 *
 *  Redistribution and use in source and binary forms, with or without
 *  modification, are permitted provided that the following conditions
 *  are met:
 *
 *    Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *
 *    Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the
 *    distribution.
 *
 *    Neither the name of Texas Instruments Incorporated nor the names of
 *    its contributors may be used to endorse or promote products derived
 *    from this software without specific prior written permission.
 *
 *  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 *  "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 *  LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 *  A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 *  OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 *  SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 *  LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 *  DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 *  THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 *  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 *  OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#ifndef _TI_EDGEAI_GST_HELPER_H_
#define _TI_EDGEAI_GST_HELPER_H_

/* Standard headers. */
#include <string>
#include <vector>
#include <map>

/* Third-party headers. */
#include <gst/gst.h>
#include <gst/app/gstappsink.h>
#include <gst/app/gstappsrc.h>

namespace ti::edgeai::common
{
    using namespace ti::edgeai::common;
    using namespace std;

    /** Function to make a gstremer element and capsfilter if required.
    *
    * @param gstElement Vector to store the GST Element Constructed and
    *                   capsfilter(if any)
    * @param name Factory name of the element to make
    * @param propMap Property Vector of to be used for element
    * @param caps Caps string to be used for element
    *
    */
    void makeElement(vector<GstElement *>            &gstElement,
                     const gchar                     *name,
                     vector<vector<const gchar*>>    &propMap,
                     const gchar                     *caps=nullptr);

    /** Function to link two gstreamer element.
    *
    * @param element1 First GST elment
    * @param element2 Second GST element
    *
    */
    void link(GstElement *element1, GstElement *element2);

    /**
    * Adds all the gstelement in vector to the pipeline and links them
    * from the front of the vector to back.
    *
    * @param pipeline GST pipeline to add the elements to
    * @param gstElement Vector of GST elements to add and link
    *
    */
    void addAndLink(GstElement                      *pipeline,
                    const vector<GstElement *>      &gstElements);

    /** Function to set the property of mosaic element.
    *
    * @param mosaic Mosaic Element
    * @param propertyName Name of the Property
    * @param value Value of the property
    *
    */
    void setMosaicProperty(GstElement               *mosaic,
                           string                    propertyName,
                           int                       value);

    /** Function to get the property of mosaic element.
    *
    * @param mosaic Mosaic Element to retrive property from
    *
    * @return string property of mosaic
    */
    string getMosaicProperty(GstElement *mosaic);

    /** Get the output color format from last element of gstreamer pipeline.
    *
    * @param pipeline GST Pipeline
    * @param lastElement Lst Element of the pipeline
    *
    * @return format of the last element
    */
    const gchar *get_format(GstElement *pipeline, GstElement *lastElement);

    /** Get the list of format supported by a pad of the elment.
    *
    * @param elementName GST Element
    * @param pad GST Pad
    *
    * @return vector of formats(in string) supported
    */
    vector<string> get_format_list(const gchar *elementName,unsigned int pad);

    /** Get the structure name of gstreamer element.
    *
    * @param elementName GST Element
    * @param padName Name of GST Pad ("src" or "sink")
    *
    * @return Structure name (Ex: video/x-raw or application/x-tensor...)
    */
    const gchar *get_structure_name(GstElement *element, const gchar *padName);

    /** Returns the PadTemplate of an element.
    *
    * @param factory Factory of GST Element
    * @param pad GST Pad
    *
    * @return PadTemplate of element
    */
    GstStaticPadTemplate *get_pad_template(GstElementFactory    *factory,
                                           unsigned int          pad);

    /** Print the pipeline string from given src gstreamer pipeline.
    *
    * @param pipeline GST Pipeline
    * @param title title to be printed before GST String
    *
    */
    void print_src_pipeline(GstElement *pipeline, string title);

    /** Print the pipeline string from given sink gstreamer pipeline.
    *
    * @param pipeline GST Pipeline
    *
    */
    void print_sink_pipeline(GstElement *pipeline);



    /** Returns the Caps of an element pad.
    *
    * @param element GST Element
    * @param padName Name of GST Pad ("src" or "sink")
    *
    * @return NULL if Caps couldnt be retrived, else Caps of the Pad
    */
    GstCaps *_get_pad_capabilities (GstElement  *element,
                                    const gchar *padName);

    /** Returns the structure of a caps.
    *
    * @param caps GST Caps
    *
    * @return NULL if caps is empty,any or null, else Structure 0 of the caps.
    */
    GstStructure *_get_cap_structure(const GstCaps *caps);

    /** Returns color format of element pad as char*.
    *
    * @param element GST element
    * @param padName Name of GST Pad ("src" or "sink")
    *
    * @return "ANY" if pad has "ANY" format, else format.
    */
    const gchar *_get_format_string(GstElement  *element,
                                    const gchar *padName);

    /** Iterate though SISO or SIMO pipeline and constructs GST string
    *
    * @param pipeline GST Pipeline
    * @param startElement Starting Element of pipeline
    * @param main_string string to append GST Pipeline string to
    *
    */
    void _print_single_input(GstElement *pipeline,
                             GstElement *startElement,
                             string     &main_string);

    /** All Non-defaut, Readable and Writabel property of element
    *
    * @param element GST Element
    *
    * @return string containing factory name of element with its properties
    *
    */
    string _get_name_with_prop(GstElement *element);

    /** checks if the given string is integer or decimal number.
    *
    * @param s Number as string
    *
    * @return true if given string is numerical else false.
    *
    */
    template<typename Numeric> bool _is_number(const std::string& s);

} // namespace ti::edgeai::common

#endif /* _TI_EDGEAI_GST_HELPER_H_ */

