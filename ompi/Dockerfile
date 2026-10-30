FROM atlasadc/atlas-grid-almalinux9:latest
LABEL org.opencontainers.image.authors="Beojan Stanislaus <bstanislaus@lbl.gov>"

USER root
RUN yum -y install yum-utils procps-ng && yum-config-manager --enable crb  && yum -y install https://linuxsoft.cern.ch/wlcg/el9/x86_64/wlcg-repo-1.0.0-1.el9.noarch.rpm https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm && yum -y update && yum -y install HEP_OSlibs && yum clean all
RUN yum -y erase zsh vim vim-minimal && \
    yum -y update && \
    yum -y install \
      yum-utils expat expat-devel zlib-devel man-db wget \
      gcc-toolset-13-libstdc++-devel python3-pip \
      ripgrep fd-find ShellCheck yamllint && \
    yum clean all
COPY --chown=root:root --chmod=755 common/startup.sh /etc/startup.sh
RUN echo source /etc/startup.sh >> /etc/profile.d/container-date.sh
COPY --chown=root:root --chmod=700 common/starship.sh /usr/bin/install-starship.sh
COPY --chown=root:root --chmod=700 ompi/install-ompi.sh /usr/bin/install-ompi.sh
RUN cd /usr && wget https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz && tar --strip-components 1 -axf nvim-linux-x86_64.tar.gz && ln -s /usr/bin/nvim /usr/bin/vim && rm -rf nvim-linux-x86_64.tar.gz
RUN cd /usr/bin && wget https://github.com/zellij-org/zellij/releases/latest/download/zellij-x86_64-unknown-linux-musl.tar.gz && tar -axf zellij-x86_64-unknown-linux-musl.tar.gz && rm -rf zellij-x86_64-unknown-linux-musl.tar.gz
ENV BASH_ENV=/etc/startup.sh \
    ENV=/etc/startup.sh 

# RUN --mount=type=bind,source=cvmfs,target=/cvmfs install-mpi.sh
RUN pip install --no-cache-dir jupyterlab bash_kernel pynvim
RUN install-starship.sh --yes
RUN --mount=type=bind,from=cuda,target=/usr/local/cuda install-ompi.sh
RUN rm -f /usr/bin/install-ompi.sh /usr/bin/install-starship.sh && \
    rm -rf /root/.cache /tmp/* /var/cache/dnf /var/cache/yum
RUN python3 -m bash_kernel.install --sys-prefix

FROM scratch
COPY --from=0 / /

ENV BASH_ENV=/etc/startup.sh \
    ENV=/etc/startup.sh 

LABEL org.opencontainers.image.authors="Beojan Stanislaus <bstanislaus@lbl.gov>"
USER root
WORKDIR /root

# ENTRYPOINT ["/bin/bash"]
