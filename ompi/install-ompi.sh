#!/usr/bin/env bash
set -e
source /etc/startup.sh
# source /cvmfs/sft.cern.ch/lcg/releases/gcc/13.1.0-b3d18/x86_64-el9 || exit 1
# Build only the gdrcopy user-space library. UCX uses it when the gdrdrv kernel
# module is present on the host and skips it otherwise.
export gdrcopy=2.6
export gdrcopy_prefix=gdrcopy-$gdrcopy
wget https://github.com/NVIDIA/gdrcopy/archive/refs/tags/v$gdrcopy.tar.gz -O $gdrcopy_prefix.tar.gz && \
tar axf $gdrcopy_prefix.tar.gz                                                 && \
cd $gdrcopy_prefix                                                             && \
make prefix=/usr libdir=/usr/lib64 CUDA=/usr/local/cuda lib lib_install        && \
/sbin/ldconfig
cd ..
rm -rf $gdrcopy_prefix $gdrcopy_prefix.tar.gz
# The AlmaLinux 9 ucx packages have no CUDA support, so build UCX from source.
export ucx=1.22.0
export ucx_prefix=ucx-$ucx
wget https://github.com/openucx/ucx/releases/download/v$ucx/$ucx_prefix.tar.gz && \
tar axf $ucx_prefix.tar.gz                                                     && \
cd $ucx_prefix                                                                 && \
./configure --prefix=/usr --libdir=/usr/lib64 --with-cuda=/usr/local/cuda      \
            --with-verbs --with-rdmacm --with-gdrcopy=/usr --enable-mt         \
            --enable-logging --enable-profiling --enable-debug-data            \
            --disable-debug                                                    && \
make -j 8                                                                      && \
make install                                                                   && \
/sbin/ldconfig
# Fail the image build if UCX was configured without CUDA.
ucx_info -v | grep -q -- '--with-cuda'
ucx_info -v | grep -q -- '--with-gdrcopy'
cd ..
rm -rf $ucx_prefix $ucx_prefix.tar.gz
export ompi=5.0.11
export ompi_prefix=openmpi-$ompi
wget https://download.open-mpi.org/release/open-mpi/v5.0/$ompi_prefix.tar.bz2 && \
tar axf $ompi_prefix.tar.bz2                                                  && \
cd $ompi_prefix                                                               && \
./configure --prefix=/usr --with-cuda=/usr/local/cuda --with-ft=mpi           \
            --enable-mpi-ext=all                                              \
            --with-pmix=internal --with-zlib --with-ucx=/usr --with-ofi=/usr  && \
make -j 8                                                                    && \
make install                                                                  && \
/sbin/ldconfig
# PMIx builds zlib as a plugin, not into libpmix.so. Fail the image build if
# the plugin is missing or does not link zlib.
ldd /usr/lib64/pmix/pmix_mca_pcompress_zlib.so | grep -q libz
# Fail the image build if the UCX or OFI components were not built.
ompi_info | grep -q 'MCA pml: ucx'
ompi_info | grep -q 'MCA mtl: ofi'
cd ..
rm -rf $ompi_prefix
rm -rf $ompi_prefix.tar.bz2
# OSU Micro-Benchmarks, built against the Open MPI above. The benchmarks end up in
# /usr/local/libexec/osu-micro-benchmarks/mpi. The CUDA stubs let the link succeed
# without a driver. The real libcuda comes from the host at run time.
export osu=7.5.3
export osu_prefix=osu-micro-benchmarks-$osu
wget https://mvapich.cse.ohio-state.edu/download/mvapich/$osu_prefix.tar.gz && \
tar axf $osu_prefix.tar.gz                                                   && \
cd $osu_prefix                                                               && \
./configure --prefix=/usr/local CC=mpicc CXX=mpicxx                             \
            --enable-cuda --with-cuda=/usr/local/cuda                           \
            LDFLAGS="-L/usr/local/cuda/lib64 -L/usr/local/cuda/lib64/stubs"  && \
make -j 8                                                                    && \
make install
cd ..
rm -rf $osu_prefix $osu_prefix.tar.gz
/sbin/ldconfig
