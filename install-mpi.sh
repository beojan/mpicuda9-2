#!/usr/bin/env bash
set -e
source /etc/startup.sh
# source /cvmfs/sft.cern.ch/lcg/releases/gcc/13.1.0-b3d18/x86_64-el9 || exit 1
export mpich=4.2.2
export mpich_prefix=mpich-$mpich
wget https://www.mpich.org/static/downloads/$mpich/$mpich_prefix.tar.gz && \
tar axf $mpich_prefix.tar.gz                                            && \
cd $mpich_prefix                                                        && \
./configure --prefix=/usr                                               && \
make -j 8                                                               && \
make install
cd ..
rm -rf $mpich_prefix
rm -rf $mpich_prefix.tar.gz
/sbin/ldconfig
cd /usr
tar --strip-components=1 -axf /timem* && \
rm -rf /timem*
/sbin/ldconfig
