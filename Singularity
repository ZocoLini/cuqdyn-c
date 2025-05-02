Bootstrap: docker
From: ubuntu:22.04

%labels
    Author Borja Castellano
    Version 0.1.0

%files
    . /opt/cuqdyn-c

%post
    apt update
    apt install -y \
        build-essential \
        cmake \
        libhdf5-serial-dev \
        gfortran

    cd /opt/cuqdyn-c
    ./build.sh
