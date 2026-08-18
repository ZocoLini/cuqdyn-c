FROM ubuntu:24.04

LABEL author="Borja Castellano" \
    version="0.1.0"

RUN apt-get update && \
    apt-get install -y \
    curl \
    git \
    libopenmpi-dev \
    openmpi-bin \
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

USER ubuntu
WORKDIR /home/ubuntu

RUN curl https://sh.rustup.rs -sSf | sh -s -- -y

ENV PATH="/home/ubuntu/.cargo/bin:${PATH}"
