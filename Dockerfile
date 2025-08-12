FROM ubuntu:24.04

LABEL author="Borja Castellano" \
    version="0.1.0"

ENV PATH="/root/.cargo/bin:${PATH}"

RUN apt-get update && \
    apt-get install -y \
    curl \
    git \
    libopenmpi-dev \
    openmpi-bin \
    build-essential \
    cmake \
    libxml2 \
    gfortran && \
    curl https://sh.rustup.rs -sSf | sh -s -- -y && \
    echo 'export PATH=/root/.cargo/bin:$PATH' >> /root/.bashrc && \
    rm -rf /var/lib/apt/lists/*
