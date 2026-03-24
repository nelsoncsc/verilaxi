FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    ca-certificates \
    git \
    make \
    g++ \
    clang \
    flex \
    bison \
    help2man \
    perl \
    gawk \
    python3 \
    python3-dev \
    autoconf \
    automake \
    libtool \
    pkg-config \
    berkeley-abc \
    libreadline-dev \
    tcl-dev \
    libffi-dev \
    zlib1g-dev \
    libfl2 \
    libfl-dev \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp

RUN git clone --depth 1 --branch v5.046 https://github.com/verilator/verilator.git \
 && cd verilator \
 && autoconf \
 && ./configure \
 && make -j"$(nproc)" \
 && make install \
 && cd /tmp \
 && rm -rf verilator

RUN git clone --depth 1 --branch yosys-0.63 https://github.com/YosysHQ/yosys.git \
 && cd yosys \
 && make config-gcc \
 && make -j"$(nproc)" \
 && make install \
 && cd /tmp \
 && rm -rf yosys

WORKDIR /workspace

CMD ["bash"]
