FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    ca-certificates \
    git \
    make \
    g++ \
    flex \
    bison \
    help2man \
    perl \
    python3 \
    python3-dev \
    autoconf \
    automake \
    libtool \
    pkg-config \
    zlib1g-dev \
    libfl2 \
    libfl-dev \
    yosys \
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

WORKDIR /workspace

CMD ["bash"]
