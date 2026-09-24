FROM ubuntu:24.04

LABEL author="Borja Castellano" \
    version="0.1.0"

RUN apt-get update && \
    apt-get install -y \
    ca-certificates \
    curl \
    git \
    build-essential \
    cmake \
    gdb \
    libpapi-dev papi-tools \
    libgsl-dev \
    gfortran \
    python3-pip \
    shfmt \
    shellcheck \
    clang-tidy \
    libxml2-utils && \
    rm -rf /var/lib/apt/lists/*

# Open MPI from source rather than from apt. The packaged build loads its MCA
# components with dlopen and dlcloses them on the way out, which leaves
# LeakSanitizer holding "<unknown module>" stacks that tests/lsan-mpi.supp
# cannot match by library name, so every rank fails the suite on Open MPI's own
# allocations. Building the components into the libraries (--disable-dlopen)
# keeps every frame resolvable.
# 4.1.8 is also what scripts/build.sh loads on CESGA, so CI and the cluster now
# run the same MPI.
ARG OPENMPI_VERSION=4.1.8
ARG OPENMPI_SHA256=466f68e3132a1dc02710cc2011fafced8336d98359fa2dae4dddcfd5719f12a9
RUN curl -sL -o /tmp/openmpi.tar.bz2 \
    "https://download.open-mpi.org/release/open-mpi/v${OPENMPI_VERSION%.*}/openmpi-${OPENMPI_VERSION}.tar.bz2" && \
    echo "${OPENMPI_SHA256}  /tmp/openmpi.tar.bz2" | sha256sum -c - && \
    tar xf /tmp/openmpi.tar.bz2 -C /tmp && \
    cd "/tmp/openmpi-${OPENMPI_VERSION}" && \
    ./configure --prefix=/opt/openmpi \
    --disable-dlopen \
    --with-pmix=internal \
    --with-hwloc=internal \
    --with-libevent=internal \
    --disable-silent-rules && \
    make -j "$(nproc)" all && \
    make install && \
    cd / && rm -rf /tmp/openmpi.tar.bz2 "/tmp/openmpi-${OPENMPI_VERSION}" && \
    echo /opt/openmpi/lib > /etc/ld.so.conf.d/openmpi.conf && ldconfig

ENV PATH="/opt/openmpi/bin:${PATH}"

# Formatters used by .githooks/pre-commit. Keeping them in the image means the
# hook works without every contributor installing seven tools by hand: when one
# is missing locally it is run in here instead.
RUN pip install --no-cache-dir --break-system-packages \
    clang-format \
    fprettify \
    black \
    gersemi \
    mdformat

# The repository is bind-mounted from the host, so its owner is whatever UID
# checked it out. Without this git refuses to operate on it, which breaks every
# hook the moment CI runs them in here.
RUN git config --system --add safe.directory '*'

ARG UID=1000
ARG GID=1000
RUN if [ "$UID:$GID" != "1000:1000" ]; then \
    groupmod -g "$GID" ubuntu && \
    usermod -u "$UID" -g "$GID" ubuntu && \
    chown -R "$UID:$GID" /home/ubuntu; \
    fi

USER ubuntu
WORKDIR /home/ubuntu

# The default profile ships rust-docs, nearly a gigabyte nobody reads in a
# container. Minimal drops it, and the two components the hooks actually use are
# asked for by name.
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y --profile minimal -c rustfmt -c clippy

ENV PATH="/home/ubuntu/.cargo/bin:${PATH}"
