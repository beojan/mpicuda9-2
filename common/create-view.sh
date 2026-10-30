#!/usr/bin/env sh
#
sed -i 's/gcc;11.3.1/gcc;11.3.0/' /opt/lcg/LCG_102b_ATLAS_12/LCG_externals_x86_64-centos9-gcc11-opt.txt
cd /tmp
mkdir /opt/lcgviews
git clone https://gitlab.cern.ch/sft/lcgcmake.git
cd lcgcmake
git apply /lcg-view-blacklist.patch
cd ..
./lcgcmake/cmake/scripts/create_lcg_view.py -r 102b_ATLAS_12 -p x86_64-centos9-gcc11-opt -v -l /opt/lcg -d -B /opt/views/LCG_102b_ATLAS_12/x86_64-centos9-gcc11-opt
rm -rf lcgcmake
rm -rf /lcg-view-blacklist.patch
