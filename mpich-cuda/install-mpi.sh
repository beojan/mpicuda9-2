#!/usr/bin/env bash
set -e
source /etc/startup.sh
# source /cvmfs/sft.cern.ch/lcg/releases/gcc/13.1.0-b3d18/x86_64-el9 || exit 1
export mpich=4.3.2
export mpich_prefix=mpich-$mpich
wget https://www.mpich.org/static/downloads/$mpich/$mpich_prefix.tar.gz && \
tar axf $mpich_prefix.tar.gz                                            && \
cd $mpich_prefix                                                        && \
./configure --prefix=/usr --with-device=ch4:ofi \
  --with-cuda=/usr/local/cuda \
  --with-cuda-sm=75,80,86,87,89,90 \
  --enable-threads=multiple --enable-g=log,dbg                   && \
make -j 8                                                               && \
make install
cd ..
rm -rf $mpich_prefix
rm -rf $mpich_prefix.tar.gz
/sbin/ldconfig
