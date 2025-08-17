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
    gfortran && \
    rm -rf /var/lib/apt/lists/*

USER ubuntu
WORKDIR /home/ubuntu

RUN curl https://sh.rustup.rs -sSf | sh -s -- -y

ENV PATH="/home/ubuntu/.cargo/bin:${PATH}"
