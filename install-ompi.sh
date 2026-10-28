#!/usr/bin/env bash
set -e
source /etc/startup.sh
# source /cvmfs/sft.cern.ch/lcg/releases/gcc/13.1.0-b3d18/x86_64-el9 || exit 1
export ompi=5.0.11
export ompi_prefix=openmpi-$ompi
wget https://download.open-mpi.org/release/open-mpi/v5.0/$ompi_prefix.tar.bz2 && \
tar axf $ompi_prefix.tar.bz2                                                  && \
cd $ompi_prefix                                                               && \
./configure --prefix=/usr --with-cuda=/usr/local/cuda --with-ft=mpi           && \
make -j 8                                                                     && \
make install
cd ..
rm -rf $ompi_prefix
rm -rf $ompi_prefix.tar.bz2
/sbin/ldconfig
