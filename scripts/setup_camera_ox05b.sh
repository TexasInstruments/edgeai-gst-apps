#!/bin/bash

# Set CDNS CSI Bridge
media-ctl -R '"cdns_csi2rx.30101000.csi-bridge" [0/0 -> 1/0 [1], 0/1 -> 1/1 [1]]'
media-ctl -V '"cdns_csi2rx.30101000.csi-bridge":0/0 [fmt:SBGGI10_1X10/2592x1944 field:none colorspace:srgb]'
media-ctl -V '"cdns_csi2rx.30101000.csi-bridge":0/1 [fmt:SBGGI10_1X10/2592x1944 field:none colorspace:srgb]'

# Set j721e-csi2rx routes
media-ctl -R '"30102000.ticsi2rx" [0/0 -> 1/0 [1], 0/1 -> 2/0 [1]]'
media-ctl -V '"30102000.ticsi2rx":0/0 [fmt:SBGGI10_1X10/2592x1944 field:none colorspace:srgb]'
media-ctl -V '"30102000.ticsi2rx":0/1 [fmt:SBGGI10_1X10/2592x1944 field:none colorspace:srgb]'

# Set video node formats
v4l2-ctl -z platform:30102000.ticsi2rx -d "30102000.ticsi2rx context 0" -v width=2592,height=1944,pixelformat=BGI0
v4l2-ctl -z platform:30102000.ticsi2rx -d "30102000.ticsi2rx context 1" -v width=2592,height=1944,pixelformat=BGI0
