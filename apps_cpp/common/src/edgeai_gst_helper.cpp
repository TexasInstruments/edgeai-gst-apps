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
/* Standard headers. */
#include <map>
#include <filesystem>
#include <algorithm>

/* Module headers. */
#include <common/include/edgeai_gst_helper.h>

#define TI_EDGEAI_GET_TIME() chrono::system_clock::now()
#define TI_EDGEAI_GET_DIFF(_START, _END) \
chrono::duration_cast<chrono::milliseconds>(_END - _START).count()

using namespace ti::edgeai::common;

namespace ti::edgeai::common
{
    using TimePoint = std::chrono::time_point<std::chrono::system_clock>;

    static void pad_added_handler (GstElement   *src,
                                   GstPad       *new_pad,
                                   GstElement   *peer_element);

    void makeElement(vector<GstElement *>         &gstElement,
                     const gchar                  *name,
                     vector<vector<const gchar*>> &propMap,
                     const gchar                  *caps)
    {   
        GstElement *element;
        element = gst_element_factory_make (name, NULL);
        if (!element) 
        {
            g_printerr("Failed to create element of type %s \n" ,(name));
            throw runtime_error("Failed to create Gstreamer Pipeline.");
        }

        unsigned int propMap_size = propMap.size();
        for (unsigned int i = 0; i < propMap_size; i++)
        {
            if (g_str_equal(propMap[i][0],"caps"))
            {
                g_object_set(element,propMap[i][0],
                             gst_caps_from_string(propMap[i][1]),
                             NULL);
            }
            else if (g_str_equal(propMap[i][0],"extra-controls"))
            {
                g_object_set(element,propMap[i][0],
                             gst_structure_from_string(propMap[i][1],NULL),
                             NULL);
            }
            else if (g_str_equal(propMap[i][1],"true") ||
                     g_str_equal(propMap[i][1],"false") )
            {
                bool val = g_str_equal(propMap[i][1],"true");
                g_object_set(element,propMap[i][0], val, NULL);
            }
            else if (_is_number<int>(propMap[i][1]))
            {
                try
                {
                    g_object_set(element,propMap[i][0], stoi(propMap[i][1]), NULL);
                }
                catch(...)
                {
                    g_print("Skip Setting %s=%s in %s. \n",
                            propMap[i][0],propMap[i][1],
                            gst_element_get_name(element));
                    continue;
                }
            }
            else if (_is_number<double>(propMap[i][1]))
            {
                try
                {
                    g_object_set(element,propMap[i][0], stod(propMap[i][1]), NULL);
                }
                catch(...)
                {
                    g_print("Skip Setting %s=%s in %s. \n",
                            propMap[i][0],
                            propMap[i][1],
                            gst_element_get_name(element));
                    continue;
                }
            }
            else
            {
                g_object_set(element,propMap[i][0], propMap[i][1], NULL);
            }
        }
        propMap.clear();
        
        gstElement.push_back(element);
        
        if (caps != NULL)
        {
            GstElement *capsfilter;
            capsfilter = gst_element_factory_make ("capsfilter", NULL);
            g_object_set(capsfilter, "caps", gst_caps_from_string(caps), NULL);
            gstElement.push_back(capsfilter);
        }
    }

    void link(GstElement *element1,GstElement *element2)
    {
        gst_element_link(element1,element2);
    }

    void addAndLink(GstElement                  *pipeline,
                    const vector<GstElement *>  &gstElements)
    {
        for(uint32_t i = 0; i < gstElements.size(); i++)
        {
            gst_bin_add (GST_BIN(pipeline), gstElements[i]);
        }

        for(uint32_t i = 0; i < gstElements.size()-1 ; i++)
        {
            link(gstElements[i],gstElements[i+1]);
            GstStaticPadTemplate *padtemplate;
            padtemplate = get_pad_template(gst_element_get_factory(gstElements[i]),
                                           GST_PAD_SRC
                                          );
            if (padtemplate->presence == GST_PAD_SOMETIMES)
            {
                g_signal_connect (gstElements[i],
                                  "pad-added",
                                  G_CALLBACK (pad_added_handler),
                                  gstElements[i+1]);
            }
        }
    }

    /* This function will be called by the pad-added signal */
    static void pad_added_handler (GstElement   *src,
                                   GstPad       *new_pad,
                                   GstElement   *peer_element)
    {
        if (src == nullptr || new_pad == nullptr || peer_element == nullptr)
        {
            return;
        }

        GstPad              *sink_pad;
        GstPadLinkReturn     link_ret;
        GstPad              *peer_pad=nullptr;

        sink_pad = gst_element_get_static_pad (peer_element, "sink");

        /* If our converter is already linked, we have nothing to do here */
        if (gst_pad_is_linked (sink_pad))
        {
            gst_object_unref (sink_pad);
            return;
        }

        if (!gst_pad_is_linked (new_pad))
        {
            if (gst_pad_is_linked (sink_pad))
            {
                peer_pad = gst_pad_get_peer(sink_pad);
                gst_pad_unlink(peer_pad,sink_pad);
            }
            link_ret = gst_pad_link(new_pad,sink_pad);
            if (link_ret == 0)
            {
                gst_pad_set_active (sink_pad,true);
            } 
            else
            {
                gst_pad_set_active (new_pad,true);
            }
        }

        if (peer_pad != nullptr)
        {
            if (GST_OBJECT_REFCOUNT_VALUE(peer_pad) > 1)
            {
                gst_object_unref(peer_pad);
            }
        }
    }

    void setMosaicProperty(GstElement *mosaic, string propertyName, int value)
    {
        string mosaic_name;
        mosaic_name = GST_OBJECT_NAME(gst_element_get_factory(mosaic));

        if (mosaic_name == "tiovxmosaic")
        {
            GValue array = G_VALUE_INIT;
            GValue val = G_VALUE_INIT;
            g_value_init (&array, GST_TYPE_ARRAY);
            g_value_init (&val, G_TYPE_INT);
            g_value_set_int (&val,value);
            gst_value_array_append_value (&array, &val);
            gst_child_proxy_set_property (GST_CHILD_PROXY (mosaic),
                                        propertyName.c_str(),
                                        &array);
            g_value_unset (&val);
            g_value_unset (&array);
        }
        else
        {
            GValue val = G_VALUE_INIT;
            g_value_init (&val, G_TYPE_INT);
            g_value_set_int (&val,value);
            gst_child_proxy_set_property (GST_CHILD_PROXY (mosaic),
                                        propertyName.c_str(),
                                        &val);
            g_value_unset (&val);
        }
    }

    string getMosaicProperty(GstElement *mosaic)
    {
        string      property_string{""};
        string      pad_name;
        string      prop_name;
        guint       value;
        string      mosaic_name;

        mosaic_name = GST_OBJECT_NAME(gst_element_get_factory(mosaic));

        GValue val = G_VALUE_INIT;
        g_value_init (&val, G_TYPE_INT);
        gst_child_proxy_get_property(GST_CHILD_PROXY (mosaic),
                                     "src::pool-size",
                                     &val);
        value = g_value_get_int(&val);
        g_value_unset(&val);
        property_string += "src::pool-size=" +
                            to_string(value) +
                            "\n";

        for (guint pad = 0; pad < mosaic->numsinkpads; pad++)
        {
            pad_name = "sink_" + to_string(pad);

            if (mosaic_name == "tiovxmosaic")
            {
                GValue array = G_VALUE_INIT;

                prop_name = pad_name + "::startx";
                g_value_init (&array, GST_TYPE_ARRAY);
                gst_child_proxy_get_property(GST_CHILD_PROXY (mosaic),
                                                prop_name.c_str(),
                                                &array);
                value = g_value_get_uint(gst_value_array_get_value (&array, 0));
                g_value_unset(&array);
                property_string += prop_name +
                                "=\"<" +
                                to_string(value) +
                                ">\" ";

                prop_name = pad_name + "::starty";
                g_value_init (&array, GST_TYPE_ARRAY);
                gst_child_proxy_get_property(GST_CHILD_PROXY (mosaic),
                                                prop_name.c_str(),
                                                &array);
                value = g_value_get_uint(gst_value_array_get_value (&array, 0));
                g_value_unset(&array);
                property_string += prop_name +
                                "=\"<" +
                                to_string(value) +
                                ">\" ";

                prop_name = pad_name + "::widths";
                g_value_init (&array, GST_TYPE_ARRAY);
                gst_child_proxy_get_property(GST_CHILD_PROXY (mosaic),
                                                prop_name.c_str(),
                                                &array);
                value = g_value_get_uint(gst_value_array_get_value (&array, 0));
                g_value_unset(&array);
                property_string += prop_name +
                                "=\"<" +
                                to_string(value) +
                                ">\" ";

                prop_name = pad_name + "::heights";
                g_value_init (&array, GST_TYPE_ARRAY);
                gst_child_proxy_get_property(GST_CHILD_PROXY (mosaic),
                                                prop_name.c_str(),
                                                &array);
                value = g_value_get_uint(gst_value_array_get_value (&array, 0));
                g_value_unset(&array);
                property_string += prop_name +
                                "=\"<" +
                                to_string(value) +
                                ">\"\n";
            }
            else
            {
                GValue val = G_VALUE_INIT;

                prop_name = pad_name + "::startx";
                g_value_init (&val, G_TYPE_INT);
                gst_child_proxy_get_property(GST_CHILD_PROXY (mosaic),
                                                prop_name.c_str(),
                                                &val);
                value = g_value_get_int(&val);
                g_value_unset(&val);
                property_string += prop_name +
                                "=" +
                                to_string(value) +
                                " ";

                prop_name = pad_name + "::starty";
                g_value_init (&val, G_TYPE_INT);
                gst_child_proxy_get_property(GST_CHILD_PROXY (mosaic),
                                                prop_name.c_str(),
                                                &val);
                value = g_value_get_int(&val);
                g_value_unset(&val);
                property_string += prop_name +
                                "=" +
                                to_string(value) +
                                " ";

                prop_name = pad_name + "::width";
                g_value_init (&val, G_TYPE_INT);
                gst_child_proxy_get_property(GST_CHILD_PROXY (mosaic),
                                                prop_name.c_str(),
                                                &val);
                value = g_value_get_int(&val);
                g_value_unset(&val);
                property_string += prop_name +
                                "=" +
                                to_string(value) +
                                " ";

                prop_name = pad_name + "::height";
                g_value_init (&val, G_TYPE_INT);
                gst_child_proxy_get_property(GST_CHILD_PROXY (mosaic),
                                                prop_name.c_str(),
                                                &val);
                value = g_value_get_int(&val);
                g_value_unset(&val);
                property_string += prop_name +
                                "=" +
                                to_string(value) +
                                "\n";
            }
        }

        return property_string;
    }

    const gchar *get_format(GstElement *pipeline, GstElement *lastElement)
    {
        GstElement          *fakesink{nullptr};
        GstElement          *last_element;
        GstBus              *bus;
        GstMessage          *msg;
        gboolean             terminate = false;
        const gchar         *format;
        GstPad              *peer_pad;
        GstElementFactory   *factory;
        const gchar         *factory_name;
        const char          *type;

        factory = gst_element_get_factory(lastElement);

        /* Check if last element is capsfilter and format is already defined. */
        factory_name = GST_OBJECT_NAME(factory);
        if (g_strcmp0("capsfilter", factory_name) == 0)
        {
            GValue value = G_VALUE_INIT;
            g_value_init (&value, GST_TYPE_CAPS);
            g_object_get_property (G_OBJECT(lastElement), "caps", &value);
            const GstCaps *caps = gst_value_get_caps (&value);
            if (caps != NULL)
            {
                GstStructure *structure = _get_cap_structure(caps);
                if (gst_structure_has_field (structure,"format"))
                {
                    format = gst_structure_get_string(structure, "format");
                    return format;
                }
            }
            g_value_reset (&value);
        }

        type = gst_element_factory_get_metadata(factory,"klass");

        if (!g_str_equal(type,"Sink"))
        {
            fakesink = gst_element_factory_make("fakesink", "fakesink");
            gst_bin_add (GST_BIN (pipeline), fakesink);
            link(lastElement,fakesink);
            last_element = lastElement;
        }
        else
        {
            peer_pad = gst_pad_get_peer(gst_element_get_static_pad(lastElement,
                                                                   "sink")
                                        );
            last_element = gst_pad_get_parent_element(peer_pad);
        }

        
        gst_element_set_state (pipeline, GST_STATE_PLAYING);

        TimePoint   start = TI_EDGEAI_GET_TIME();
        TimePoint   end = TI_EDGEAI_GET_TIME();
        bus = gst_element_get_bus (pipeline);
        do {
            msg = gst_bus_timed_pop_filtered (bus,
                                              GST_MSECOND*500,
                                              GST_MESSAGE_STATE_CHANGED);
            /* Parse message */
            if (msg != NULL) 
            {
                if (GST_MESSAGE_SRC (msg) == GST_OBJECT (pipeline))
                {
                    GstState old_state, new_state, pending_state;
                    gst_message_parse_state_changed (msg,
                                                     &old_state,
                                                     &new_state,
                                                     &pending_state);

                    if (old_state == GST_STATE_READY &&
                        new_state == GST_STATE_PAUSED)
                    {
                        format = _get_format_string(last_element,"src");
                        if (format)
                            terminate = true;
                    }
                    if (!format &&
                        old_state == GST_STATE_PAUSED &&
                        new_state == GST_STATE_PLAYING)
                    {
                        format = _get_format_string(last_element,"src");
                        terminate = true;
                    }
                }
                gst_message_unref (msg);
            }
            end = TI_EDGEAI_GET_TIME();
        } while (!terminate && TI_EDGEAI_GET_DIFF(start, end) < 3000);
        
        gst_object_unref (bus);
        gst_element_set_state (pipeline, GST_STATE_NULL);

        if (fakesink != nullptr)
        {
            gst_element_unlink(lastElement, fakesink);
            gst_bin_remove (GST_BIN (pipeline), fakesink);
        }
        else
        {
            if (GST_OBJECT_REFCOUNT_VALUE(peer_pad) > 1)
            {
                 gst_object_unref(peer_pad);
            }
            if (GST_OBJECT_REFCOUNT_VALUE(last_element) > 1)
            {
                gst_object_unref(last_element);
            }
        }
        return format;
    }

    const gchar *_get_format_string(GstElement *element, const gchar *padName)
    {
        const gchar     *format;
        GstCaps         *caps;

        format = NULL;
        caps = _get_pad_capabilities (element,padName);
        if (gst_caps_is_any (caps))
        {
            format = "ANY";
        }
        else
        {
            GstStructure *structure = _get_cap_structure(caps);
            format = gst_structure_get_string(structure, "format");
        }
        return format;
    }

    vector<string> get_format_list(const gchar *elementName, unsigned int pad)
    {
        vector<string>           formats{};
        GstElementFactory       *factory;
        GstStaticPadTemplate    *padtemplate;

        factory = gst_element_factory_find(elementName);
        padtemplate = get_pad_template(factory, pad);

        if(padtemplate->static_caps.string)
        {
            GstCaps *caps= gst_static_caps_get (&padtemplate->static_caps);
            if(caps == NULL || gst_caps_is_empty (caps))
            {
                formats.push_back("NULL");
            }

            if (gst_caps_is_any (caps))
            {
                formats.push_back("ANY");
            }

            else {
                GstStructure *structure = _get_cap_structure(caps);
                if (gst_structure_has_field (structure,"format"))
                {
                    //Parse format list from structure
                    string struct_string = gst_structure_to_string(structure);
                    int format_pos = struct_string.find("format");
                    int format_start_pos = struct_string.find("{", format_pos);
                    int format_end_pos = struct_string.find("}", format_start_pos);
                    string format_string="";
                    format_string = struct_string.substr(format_start_pos+1,
                                           (format_end_pos-format_start_pos-1)
                                           );

                    char *ptr = strtok(&format_string[0]," , ");
                    while (ptr != NULL)
                    {
                        formats.push_back(ptr);
                        ptr = strtok (NULL, " , ");
                    }
                }
            }
            gst_caps_unref (caps);
        }
        return formats;
    }

    const gchar *get_structure_name(GstElement *element, const gchar *padName)
    {
        const gchar     *name;
        GstCaps         *caps;

        caps = _get_pad_capabilities (element,padName);

        if(caps == NULL || gst_caps_is_empty (caps) || gst_caps_is_any (caps))
            name = "NULL";
        else
        {
            GstStructure *structure = _get_cap_structure(caps);
            name = gst_structure_get_name (structure);
        }
        return name;
    }

    GstStaticPadTemplate *get_pad_template(GstElementFactory *factory,
                                           unsigned int       pad)
    {
        const GList             *pads;
        GstStaticPadTemplate    *padtemplate;

        if (!gst_element_factory_get_num_pad_templates (factory))
        {
            return NULL;
        }

        pads = gst_element_factory_get_static_pad_templates (factory);
        while (pads)
        {
            padtemplate = (GstStaticPadTemplate *)pads->data;
            pads = g_list_next (pads);
            if (padtemplate->direction == pad)
                return padtemplate;
        }
        return NULL;
    }

    GstCaps *_get_pad_capabilities (GstElement *element, const gchar *padName)
    {
        GstPad  *pad  = NULL;
        GstCaps *caps = NULL;

        /* Retrieve pad */
        pad = gst_element_get_static_pad (element, padName);
        if (!pad)
        {
            g_printerr ("Could not retrieve pad '%s'\n", padName);
            return NULL;
        }

        /* Retrieve negotiated caps (or acceptable caps if negotiation is not finished yet) */
        caps = gst_pad_get_current_caps (pad);
        if (!caps)
        {
            caps = gst_pad_query_caps (pad, NULL);
        }
        gst_object_unref (pad);
        return caps;
    }

    GstStructure *_get_cap_structure(const GstCaps * caps)
    {
        if(caps == NULL)
        {
            return NULL;
        }
        if (gst_caps_is_empty (caps))
        {
            return NULL;
        }
        if (gst_caps_is_any (caps))
        {
            return NULL; //Change this
        }
        
        GstStructure *structure = gst_caps_get_structure (caps, 0);
        return structure;
    }

    string _get_name_with_prop(GstElement *element)
    {
        string        data{""};
        string        element_name;
        guint         num_properties;
        GParamSpec  **property_specs;

        element_name = GST_OBJECT_NAME(gst_element_get_factory(element));
        data += element_name;
        property_specs = g_object_class_list_properties(G_OBJECT_GET_CLASS(element),
                                                        &num_properties);

        for (guint i = 0; i < num_properties; i++)
        {
            GValue value = G_VALUE_INIT;
            GParamSpec *param = property_specs[i];
            g_value_init (&value, param->value_type);

            if((param->flags & G_PARAM_READABLE) &&
               (param->flags & G_PARAM_WRITABLE))
            {
                g_object_get_property (G_OBJECT(element), param->name, &value);

                if (g_param_value_defaults(param,&value) ||
                    g_str_equal(param->name,"name"))
                {
                    continue;
                }

                switch (G_VALUE_TYPE (&value))
                {
                    case G_TYPE_STRING:
                    {
                        const char *string_val = g_value_get_string (&value);
                        if ( string_val != NULL)
                        {
                            data += " ";
                            data += param->name;
                            data += "=";
                            data += string_val;
                        }
                        break;
                    }
                    case G_TYPE_BOOLEAN:
                    {
                        gboolean bool_val = g_value_get_boolean (&value);
                        data += " ";
                        data += param->name;
                        data += "=";
                        data += bool_val ? "true" : "false";
                        break;
                    }
                    case G_TYPE_UINT:
                    {
                        GParamSpecUInt *puint = G_PARAM_SPEC_UINT (param);
                        if (puint != NULL)
                        {
                            data += " ";
                            data += param->name;
                            data += "=";
                            data += to_string(g_value_get_uint (&value));
                        }
                        break;
                    }
                    case G_TYPE_INT:
                    {
                        GParamSpecInt *pint = G_PARAM_SPEC_INT (param);
                        if (pint != NULL)
                        {
                            data += " ";
                            data += param->name;
                            data += "=";
                            data += to_string(g_value_get_int (&value));
                        }
                        break;
                    }
                    case G_TYPE_UINT64:
                    {
                        GParamSpecUInt64 *puint64 = G_PARAM_SPEC_UINT64 (param);
                        if (puint64 != NULL)
                        {
                            data += " ";
                            data += param->name;
                            data += "=";
                            data += to_string(g_value_get_uint64(&value));
                        }
                        break;
                    }
                    case G_TYPE_INT64:
                    {
                        GParamSpecInt64 *pint64 = G_PARAM_SPEC_INT64 (param);
                        if (pint64 != NULL)
                        {
                            data += " ";
                            data += param->name;
                            data += "=";
                            data += to_string(g_value_get_int64(&value));
                        }
                        break;
                    }
                    case G_TYPE_FLOAT:
                    {
                        GParamSpecFloat *pfloat = G_PARAM_SPEC_FLOAT (param);
                        if (pfloat != NULL)
                        {
                            data += " ";
                            data += param->name;
                            data += "=";
                            data += to_string(g_value_get_float(&value));
                        }
                        break;
                    }
                    case G_TYPE_DOUBLE:
                    {
                        GParamSpecDouble *pdouble = G_PARAM_SPEC_DOUBLE (param);
                        if(pdouble != NULL)
                        {
                            data += " ";
                            data += param->name;
                            data += "=";
                            data += to_string(g_value_get_double(&value));
                        }
                        break;
                    }

                    default:
                        if (element_name == "capsfilter" && param->value_type == GST_TYPE_CAPS)
                        {
                            const GstCaps *caps = gst_value_get_caps (&value);
                            if (caps != NULL)
                            {
                                data += " ";
                                data += param->name;
                                data += "=\"";
                                data += gst_caps_to_string(caps);
                                data += ";\"";
                            }
                        }
                        else if (param->value_type == GST_TYPE_STRUCTURE)
                        {
                            const GstStructure *st = gst_value_get_structure (&value);
                            if (st != NULL)
                            {
                                data += " ";
                                data += param->name;
                                data += "=\"";
                                data += gst_structure_to_string(st);
                                data += "\"";
                            }
                        }

                        else if (G_IS_PARAM_SPEC_ENUM (param))
                        {
                            data += " ";
                            data += param->name;
                            data += "=";
                            data += to_string(g_value_get_enum (&value));

                        }

                        else if (GST_IS_PARAM_SPEC_FRACTION (param))
                        {
                            GstParamSpecFraction *pfraction = GST_PARAM_SPEC_FRACTION (param);
                            if (pfraction != NULL)
                            {
                                data += " ";
                                data += param->name;
                                data += "=";
                                data += to_string(gst_value_get_fraction_numerator (&value));
                                data += "/";
                                data += to_string(gst_value_get_fraction_denominator (&value));
                            }
                        }

                    break;
                }
            }
            g_value_reset (&value);
        }
        g_free (property_specs);
        return data;
    }

    void _print_single_input(GstElement *pipeline,
                             GstElement *startElement,
                             string     &main_string)
    {
        string                  startElementName;
        vector<vector<string>>  stack{};
        vector<string>          visited;

        startElementName.assign(gst_element_get_name(startElement));
        stack.push_back({startElementName,"",""});

        while (stack.size() > 0)
        {
            vector<string> data = stack.back();
            stack.pop_back();
            string elem_name = data[0];

            if(find(visited.begin(), visited.end(),elem_name) == visited.end())
            {
                visited.push_back(elem_name);

                GstElement        *element;
                GstElementFactory *factory;
                string             element_type;

                element = gst_bin_get_by_name(GST_BIN(pipeline),
                                              elem_name.c_str());
                factory = gst_element_get_factory(element);
                element_type.assign(gst_element_factory_get_metadata(factory,"klass"));

                /* Add timeout for safety */
                TimePoint   start = TI_EDGEAI_GET_TIME();
                TimePoint   end = TI_EDGEAI_GET_TIME();
                while ((element_type.find("Sink")) == string::npos &&
                        element->numsrcpads == 0 &&
                        TI_EDGEAI_GET_DIFF(start, end) < 5000)
                {
                    end = TI_EDGEAI_GET_TIME();
                }

                //prefix
                if (data[1] != "")
                {
                    main_string += data[1]+" ! ";
                }

                if (element->numsrcpads == 0)
                {
                    main_string += _get_name_with_prop(element) +
                                   " name=" +
                                   elem_name +
                                   "\n";
                }
                else if (element->numsrcpads == 1)
                {
                    main_string += _get_name_with_prop(element) + " ! ";
                }
                else
                {
                    main_string += _get_name_with_prop(element) +
                                   " name=" +
                                   elem_name +
                                   "\n";
                }
                if (data[2] != "")
                {
                    main_string += data[2];
                }
                vector<vector<string>>   children;
                GValue                   item = G_VALUE_INIT;
                GstIterator             *it;
                GstPad                  *pad;
                gboolean                 done = FALSE;

                it = gst_element_iterate_src_pads (GST_ELEMENT (element));

                while (!done && element->numsrcpads != 0){
                    GstPad     *peer_pad;
                    GstElement *peer_element;
                    string      peer_element_name;
                    string      pfx{""};
                    switch (gst_iterator_next (it, &item))
                    {
                        case GST_ITERATOR_OK:{
                            pad = (GstPad *) g_value_get_object (&item);
                            /* Add timeout for safety */
                            TimePoint   start = TI_EDGEAI_GET_TIME();
                            TimePoint   end = TI_EDGEAI_GET_TIME();
                            while ( !gst_pad_get_peer(pad) &&
                                    TI_EDGEAI_GET_DIFF(start, end) < 5000)
                            {
                                end = TI_EDGEAI_GET_TIME();
                            }

                            peer_pad = gst_pad_get_peer(pad);
                            if(peer_pad)
                            {
                                peer_element = gst_pad_get_parent_element(peer_pad);
                                if (peer_element)
                                {
                                    peer_element_name.assign(
                                            gst_element_get_name(peer_element)
                                        );
                                    if (element->numsrcpads > 1)
                                    {
                                        pfx = elem_name+".";
                                    }
                                    children.push_back({peer_element_name,pfx,""});
                                }
                            }

                            g_value_reset (&item);
                            break;
                        }
                        case GST_ITERATOR_RESYNC:
                            gst_iterator_resync (it);
                            break;
                        case GST_ITERATOR_ERROR:
                            done = TRUE;
                            break;
                        case GST_ITERATOR_DONE:
                            done = TRUE;
                            break;
                    }

                    if (GST_OBJECT_REFCOUNT_VALUE(peer_pad) > 1)
                    {
                        gst_object_unref(peer_pad);
                    }
                    if (GST_OBJECT_REFCOUNT_VALUE(peer_element) > 1)
                    {
                        gst_object_unref(peer_element);
                    }
                }
                gst_iterator_free (it);
                stack.insert(stack.end(),children.rbegin(),children.rend());
            }
        }
    }

    void print_src_pipeline(GstElement *pipeline, string title)
    {
        GstElement  *startElement;
        string       source_name;
        int32_t      num=0;

        while(true)
        {
            string main_str;
            source_name = "source" + to_string(num);
            startElement = gst_bin_get_by_name(GST_BIN(pipeline),
                                               source_name.c_str());
            if (startElement == nullptr)
            {
               break;
            }
            _print_single_input(pipeline, startElement, main_str);
            printf("%s\n%s\n",title.c_str(),main_str.c_str());
            num++;
        }
    }

    void print_sink_pipeline(GstElement *pipeline)
    {
        GValue                value = G_VALUE_INIT;
        GstIterator          *it;
        GstElement           *element;
        gboolean              done = FALSE;
        string                name;
        vector<GstElement *>  pipelineElements;
        vector<GstElement *>  mosaicElements;
        map<string,int32_t>   mosaicSinkCnt;
        string                main_string{""};
        string                mosaic_string{""};

        it = gst_bin_iterate_elements(GST_BIN (pipeline));

        while (!done){
            switch (gst_iterator_next (it, &value))
            {
                case GST_ITERATOR_OK:
                    element = GST_ELEMENT (g_value_get_object (&value));
                    pipelineElements.insert(pipelineElements.begin(),element);
                    g_value_reset (&value);
                    break;
                case GST_ITERATOR_RESYNC:
                    gst_iterator_resync (it);
                    break;
                case GST_ITERATOR_ERROR:
                case GST_ITERATOR_DONE:
                    done = TRUE;
                    break;
            }
        }
        gst_iterator_free (it);

        GstPad      *peer_pad;
        GstElement  *peer_element;

        for (uint32_t i = 0; i < pipelineElements.size(); i++)
        {
            string               prefix{""};
            string               suffix{""};
            string               data{""};
            string               element_factory_name;
            string               element_name;
            string               element_type;
            GstElementFactory   *factory;

            factory = gst_element_get_factory(pipelineElements[i]);
            element_factory_name = GST_OBJECT_NAME(factory);

            element_name.assign(gst_element_get_name(pipelineElements[i]));
            element_type.assign(gst_element_factory_get_metadata(factory,"klass"));

            if (element_factory_name == "tiovxmosaic"
                ||
                element_factory_name == "timosaic")
            {
                while(i < pipelineElements.size() &&
                      (element_type.find("Sink")) == string::npos)
                {
                   mosaicElements.push_back(pipelineElements[i]);
                   i++;
                   GstElementFactory *tempFactory;
                   tempFactory = gst_element_get_factory(pipelineElements[i]);
                   element_type.assign(gst_element_factory_get_metadata(
                                                          tempFactory,"klass"));
                }
                mosaicElements.push_back(pipelineElements[i]);
            }
            else
            {
                GstElementFactory *peerFactory;
                if (element_name.find("queue") != string::npos)
                {
                    peer_pad = gst_pad_get_peer(
                         gst_element_get_static_pad(pipelineElements[i], "sink")
                        );

                    if(peer_pad)
                    {
                        peer_element = gst_pad_get_parent_element(peer_pad);
                        if (peer_element)
                        {
                            peerFactory = gst_element_get_factory(peer_element);
                            if (g_str_equal("tee",GST_OBJECT_NAME(peerFactory)))
                            {
                                string p_element_name;
                                p_element_name.assign(
                                            gst_element_get_name(peer_element));
                                prefix = "\n" + p_element_name + ". ! ";
                            }
                            gst_object_unref(peer_element);
                        }
                        gst_object_unref(peer_pad);
                    }

                    peer_pad = gst_pad_get_peer(
                          gst_element_get_static_pad(pipelineElements[i], "src")
                        );

                    if(peer_pad)
                    {
                        peer_element = gst_pad_get_parent_element(peer_pad);
                        if (peer_element)
                        {
                            peerFactory = gst_element_get_factory(peer_element);
                            if (g_str_equal("tiovxmosaic",GST_OBJECT_NAME(peerFactory))
                                ||
                                g_str_equal("timosaic",GST_OBJECT_NAME(peerFactory))
                                )
                            {
                                string p_element_name;
                                p_element_name.assign(gst_element_get_name(peer_element));
                                if (mosaicSinkCnt.find(p_element_name) == mosaicSinkCnt.end())
                                {
                                    mosaicSinkCnt[p_element_name] = 0;
                                }
                                suffix = p_element_name + ".sink" + to_string(mosaicSinkCnt[p_element_name]);
                                mosaicSinkCnt[p_element_name] = mosaicSinkCnt[p_element_name] + 1;
                            }
                            gst_object_unref(peer_element);
                        }
                        gst_object_unref(peer_pad);
                    }
                }

                if (pipelineElements[i]->numsinkpads == 0)
                {
                    data = "\n\n" +
                           _get_name_with_prop(pipelineElements[i]) +
                           " name=" +
                           element_name +
                           " ! ";
                }
                else if (pipelineElements[i]->numsrcpads == 0)
                {
                    data = _get_name_with_prop(pipelineElements[i]);
                }
                else if (pipelineElements[i]->numsrcpads == 1)
                {
                   data = _get_name_with_prop(pipelineElements[i])+" ! ";
                }
                else
                {
                    data = _get_name_with_prop(pipelineElements[i]) +
                                   " name=" +
                                   element_name;
                }

                main_string += prefix + data + suffix;

            }
        }

        for (uint32_t i = 0; i < mosaicElements.size(); i++)
        {
            GstElementFactory *factory;
            string             element_name;

            factory = gst_element_get_factory(mosaicElements[i]);
            element_name.assign(gst_element_get_name(mosaicElements[i]));

            if (g_str_equal("tiovxmosaic",GST_OBJECT_NAME(factory))
                ||
                g_str_equal("timosaic",GST_OBJECT_NAME(factory)))
            {
                mosaic_string += "\n";
                mosaic_string += _get_name_with_prop(mosaicElements[i]) +
                                " name=" +
                                element_name +
                                " ";
                mosaic_string += getMosaicProperty(mosaicElements[i]) + "! ";
            }
            else if (mosaicElements[i]->numsrcpads == 0)
            {
                mosaic_string += _get_name_with_prop(mosaicElements[i]) + "\n";
            }
            else if (mosaicElements[i]->numsrcpads == 1)
            {
                mosaic_string += _get_name_with_prop(mosaicElements[i]) + " ! ";
            }
        }
        printf("%s\n%s\n",main_string.c_str(),mosaic_string.c_str());
    }

    template<typename Numeric>
    bool _is_number(const std::string &s)
    {
        Numeric n;
        return((std::istringstream(s) >> n >> std::ws).eof());
    }

}// namespace ti::edgeai::common