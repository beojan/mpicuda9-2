FROM nvidia/cuda:13.4.2-cudnn-devel-rockylinux9
LABEL org.opencontainers.image.authors="Beojan Stanislaus <bstanislaus@lbl.gov>"

USER root
RUN yum -y install yum-utils procps-ng && yum-config-manager --enable crb  && yum -y install https://linuxsoft.cern.ch/wlcg/el9/x86_64/wlcg-repo-1.0.0-1.el9.noarch.rpm https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm && yum -y update && yum -y install HEP_OSlibs && yum clean all
RUN yum -y erase zsh vim vim-minimal && \
    yum -y update && \
    yum -y install \
      yum-utils expat expat-devel man-db wget \
      gcc-toolset-13-libstdc++-devel python3-pip \
      ripgrep fd-find ShellCheck yamllint && \
    yum clean all
COPY --chown=root:root --chmod=755 startup.sh /etc/startup.sh
RUN echo source /etc/startup.sh >> /etc/profile.d/container-date.sh
COPY --chown=root:root --chmod=700 starship.sh /usr/bin/install-starship.sh
COPY --chown=root:root --chmod=700 install-mpi.sh /usr/bin/install-mpi.sh
RUN cd /usr && wget https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz && tar --strip-components 1 -axf nvim-linux-x86_64.tar.gz && ln -s /usr/bin/nvim /usr/bin/vim && rm -rf nvim-linux-x86_64.tar.gz
RUN cd /usr/bin && wget https://github.com/zellij-org/zellij/releases/latest/download/zellij-x86_64-unknown-linux-musl.tar.gz && tar -axf zellij-x86_64-unknown-linux-musl.tar.gz && rm -rf zellij-x86_64-unknown-linux-musl.tar.gz
ENV BASH_ENV=/etc/startup.sh \
    ENV=/etc/startup.sh 

# RUN --mount=type=bind,source=cvmfs,target=/cvmfs install-mpi.sh
RUN pip install --no-cache-dir jupyterlab bash_kernel pynvim
RUN install-starship.sh --yes
RUN install-mpi.sh
RUN rm -f /usr/bin/install-mpi.sh /usr/bin/install-starship.sh && \
    rm -rf /root/.cache /tmp/* /var/cache/dnf /var/cache/yum
RUN python3 -m bash_kernel.install --sys-prefix
RUN printf '#!/bin/bash\nexec /bin/bash --rcfile /etc/startup.sh -i "$@"\n' > /usr/local/bin/apptainer-shell && \
    chmod 755 /usr/local/bin/apptainer-shell

FROM scratch
COPY --from=0 / /

ENV BASH_ENV=/etc/startup.sh \
    ENV=/etc/startup.sh \
    SINGULARITY_SHELL=/usr/local/bin/apptainer-shell \
    APPTAINER_SHELL=/usr/local/bin/apptainer-shell

LABEL org.opencontainers.image.authors="Beojan Stanislaus <bstanislaus@lbl.gov>"
USER root
WORKDIR /root

# ENTRYPOINT ["/bin/bash"]
