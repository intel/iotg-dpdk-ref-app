#!/bin/bash

ROOT_DIR=$(pwd)
BUILD_DIR=$(pwd)/build
LIBBPF_VERSION="0.7.0"
LIBXDP_VERSION="1.2.8"
LIBDPDK_VERSION="22.07"

rm -rf ${BUILD_DIR}
mkdir ${BUILD_DIR}
apt update
apt install -y build-essential meson ninja-build python3-pyelftools libnuma-dev libelf-dev libarchive-dev gcc-multilib libpcap-dev clang llvm

# Download and build libbpf
cd ${BUILD_DIR}
curl -L "https://github.com/libbpf/libbpf/archive/refs/tags/v${LIBBPF_VERSION}.zip" -o libbpf-${LIBBPF_VERSION}.zip
unzip libbpf-${LIBBPF_VERSION}.zip
patch libbpf-${LIBBPF_VERSION}/include/uapi/linux/if_xdp.h  ${ROOT_DIR}/if-xdp.patch
cd    libbpf-${LIBBPF_VERSION}/src
mkdir build root
OBJDIR=build DESTDIR=root make install
rm -rf /usr/include/bpf
rm /usr/lib/x86_64-linux-gnu/libbpf.*
rm /usr/lib/x86_64-linux-gnu/pkgconfig/libbpf.pc
mv root/usr/include/bpf /usr/include/.
mv root/usr/lib64/libbpf.* /usr/lib/x86_64-linux-gnu/.
mv root/usr/lib64/pkgconfig/libbpf.pc /usr/lib/x86_64-linux-gnu/pkgconfig/.
ldconfig

# Download and build libxdp
cd ${BUILD_DIR}
curl -L "https://github.com/xdp-project/xdp-tools/archive/refs/tags/v${LIBXDP_VERSION}.zip" -o xdp-tools-${LIBXDP_VERSION}.zip
unzip xdp-tools-${LIBXDP_VERSION}.zip
patch xdp-tools-${LIBXDP_VERSION}/headers/linux/if_xdp.h  ${ROOT_DIR}/if-xdp.patch
cd    xdp-tools-${LIBXDP_VERSION}
./configure
make install
ldconfig

# Download and build libdpdk
cd ${BUILD_DIR}
curl -L "http://fast.dpdk.org/rel/dpdk-${LIBDPDK_VERSION}.tar.xz" -o dpdk-${LIBDPDK_VERSION}.tar.xz
tar xf dpdk-${LIBDPDK_VERSION}.tar.xz
cd dpdk-${LIBDPDK_VERSION}
meson setup build
cd build
ninja
ninja install
ldconfig
