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

import sys
import streamlit as st
import argparse
import gi
gi.require_version('Gst', '1.0')
from gi.repository import Gst, GObject, GLib

class GStreamer:
    Gst.init(sys.argv)

    def __init__(self,udp_port):
        DEFAULT_PIPELINE = """udpsrc port=%d !
                              application/x-rtp,encoding-name=JPEG !
                              rtpjpegdepay !
                              appsink name=sink drop=true
                              sync=false emit-signals=true""" % (udp_port)
        self.pipeline = Gst.parse_launch(DEFAULT_PIPELINE)
        self.bus = self.pipeline.get_bus()
        self.bus.add_signal_watch()
        self.appsink = self.pipeline.get_by_name('sink')
        self.bus.connect("message", self.on_message)

    def start_pipeline(self):
        self.pipeline.set_state(Gst.State.PLAYING)
        print("Starting GST Pipeline...")

    def on_message(self, bus, message):
        mtype = message.type
        if mtype == Gst.MessageType.EOS:
            print("End of stream")
        elif mtype == Gst.MessageType.ERROR:
            err, debug = message.parse_error()
            print(err, debug)
        elif mtype == Gst.MessageType.WARNING:
            err, debug = message.parse_warning()
            print(err, debug)
        return True

    def pull_frame(self):
        sample = self.appsink.emit("pull-sample")
        if (type(sample) != Gst.Sample):
            print("[ERROR] Error pulling frame from GST Pipeline")
            return None
        
        caps = sample.get_caps()
        struct = caps.get_structure(0)
        buffer = sample.get_buffer()
        _ , map_info = buffer.map(Gst.MapFlags.READ)
        buffer.unmap(map_info)
        return map_info.data

    def free(self):
        self.pipeline.set_state(Gst.State.NULL)
        print("Stopped GST Pipeline.")




parser = argparse.ArgumentParser()
parser.add_argument("-P","--port", type=int, default=8081,
                    help='udp port number to listen to for jpeg frames')

UDP_PORT = int(parser.parse_args().port)

print("Listening to port",UDP_PORT,"for jpeg frames")

st.set_page_config(layout="wide")
st.title("Livestream from edgeai-gst-apps on port "+str(UDP_PORT))

@st.cache(allow_output_mutation=True)
def gst_pipeline():
    return GStreamer(UDP_PORT)

gst_pipe = gst_pipeline()

def main():
    gst_pipe.start_pipeline()
    try:
        with st.empty():
            while True:
                frame = gst_pipe.pull_frame()
                if (frame):
                    st.image(frame, caption="From UDP Sink", output_format="JPEG")
    except:
        pass
    finally:
        gst_pipe.free()
if __name__ == "__main__":
    main()