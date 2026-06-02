FROM nvidia/cuda:13.0.2-cudnn-devel-rockylinux9
LABEL org.opencontainers.image.authors="Beojan Stanislaus <bstanislaus@lbl.gov>"

USER root
RUN yum -y install yum-utils procps-ng && yum-config-manager --enable crb  && yum -y install https://linuxsoft.cern.ch/wlcg/el9/x86_64/wlcg-repo-1.0.0-1.el9.noarch.rpm https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm && yum -y update && yum -y install HEP_OSlibs && yum clean all
RUN yum -y erase zsh && yum -y update && yum -y install yum-utils expat expat-devel man-db wget nodejs gcc-toolset-13-libstdc++-devel python3-pip && yum clean all
RUN yum-config-manager --add-repo "https://storage-ci.web.cern.ch/storage-ci/eos/diopside-depend/el-9/x86_64/" && yum-config-manager --add-repo "https://storage-ci.web.cern.ch/storage-ci/eos/diopside/tag/testing/el-9/x86_64/"
RUN yum -y --nogpgcheck install eos-client eos-fusex && yum clean all
COPY --chown=root:root --chmod=755 startup.sh /etc/startup.sh
RUN echo source /etc/startup.sh >> /etc/profile.d/container-date.sh
COPY --chown=root:root --chmod=700 timemory-3.3.0-Linux.tar.xz /timemory-3.3.0-Linux.tar.xz
COPY --chown=root:root --chmod=700 starship.sh /usr/bin/install-starship.sh
COPY --chown=root:root --chmod=700 install-mpi.sh /usr/bin/install-mpi.sh
RUN cd /usr && wget https://github.com/neovim/neovim/releases/download/v0.10.3/nvim-linux64.tar.gz && tar --strip-components 1 -axf nvim-linux64.tar.gz && ln -s /usr/bin/nvim /usr/bin/vim && rm -rf nvim-linux64.tar.gz
ENV BASH_ENV=/etc/startup.sh \
    ENV=/etc/startup.sh 

# RUN --mount=type=bind,source=cvmfs,target=/cvmfs install-mpi.sh
RUN pip install jupyterlab
RUN pip install bash_kernel
RUN install-starship.sh --yes
RUN install-mpi.sh
RUN rm /usr/bin/install-mpi.sh
RUN rm /usr/bin/install-starship.sh

FROM scratch
COPY --from=0 / /

ENV BASH_ENV=/etc/startup.sh \
    ENV=/etc/startup.sh 

LABEL org.opencontainers.image.authors="Beojan Stanislaus <bstanislaus@lbl.gov>"
USER root
WORKDIR /root

ENTRYPOINT ["/bin/bash"]

