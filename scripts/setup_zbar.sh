#!/bin/bash

if [[ `arch` != "aarch64" ]]; then
  echo "This should only be run on the EVM! If need be, clone the repo and transfer locally and run following setup commands"
  return
fi

echo "Clone zbar"
if [[ ! -d ./zbar ]]; then
   git clone https://github.com/mchehab/zbar.git
fi

cd zbar

echo "Build zbar"
#https://github.com/mchehab/zbar/blob/master/INSTALL.md
autoreconf -vfi
./configure
make

echo "install zbar"
make install

cd python
python3 setup.py install

echo "Copy installed zbar to /usr/lib"
# copy to /usr/lib from /usr/local/lib. Otherwise, paths need to be added for the linker/LD to find.
cp /usr/local/lib/libzbar.so.0.3.0 /usr/lib
cp /usr/local/lib/libzbar.la /usr/lib
cp /usr/local/lib/libzbar.a /usr/lib
cp /usr/local/lib/pkgconfig/zbar.pc /usr/lib/pkgconfig/zbar.pc
cp /usr/local/lib/python3.8/site-packages/zbar.* /usr/lib/python3.8/site-packages/

ln -s /usr/lib/libzbar.so.0.3.0 /usr/lib/libzbar.so.0

ldconfig