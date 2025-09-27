#!/bin/bash

set -e  # auto stop kalau ada error

echo -e "\n[INFO]: BUILD STARTED..!\n"

# init submodules (kalau ada)
git submodule init && git submodule update || true

# Paths
export KERNEL_ROOT="$(pwd)"
export OUT_DIR="${KERNEL_ROOT}/out"
export BUILD_DIR="${KERNEL_ROOT}/build"

# Basic info
export ARCH=arm64
export SUBARCH=arm64
export KBUILD_BUILD_USER="github-actions"
export KBUILD_BUILD_HOST="github"

# Toolchain Slim LLVM 21.1.2 (sudah di-download di workflow)
export LLVM_DIR="${HOME}/toolchains/llvm-21"
export PATH="${LLVM_DIR}/bin:${PATH}"

# Cross-compile
export CROSS_COMPILE=aarch64-linux-gnu-
export CROSS_COMPILE_ARM32=arm-linux-gnueabi-
export CC=clang
export LD=ld.lld
export AR=llvm-ar
export NM=llvm-nm
export OBJCOPY=llvm-objcopy
export OBJDUMP=llvm-objdump
export READELF=llvm-readelf
export STRIP=llvm-strip

# Prepare dirs
mkdir -p "${OUT_DIR}" "${BUILD_DIR}"

build_kernel() {
    echo -e "\n[INFO]: Using defconfig..\n"
    make -C ${KERNEL_ROOT} O=${OUT_DIR} \
        ARCH=${ARCH} \
        LLVM=1 LLVM_IAS=1 \
        CROSS_COMPILE=${CROSS_COMPILE} \
        CROSS_COMPILE_ARM32=${CROSS_COMPILE_ARM32} \
        ${DEFCONFIG:-gki_defconfig}

    echo -e "\n[INFO]: Forcing FULL LTO config..\n"
    scripts/config --file ${OUT_DIR}/.config \
        -e LTO_CLANG \
        -e LTO_CLANG_FULL \
        -d LTO_CLANG_THIN \
        -d THINLTO || true

    # re-check config
    make -C ${KERNEL_ROOT} O=${OUT_DIR} olddefconfig

    echo -e "\n[INFO]: Building kernel Image..\n"
    make -C ${KERNEL_ROOT} O=${OUT_DIR} \
        ARCH=${ARCH} LLVM=1 LLVM_IAS=1 \
        CROSS_COMPILE=${CROSS_COMPILE} \
        CROSS_COMPILE_ARM32=${CROSS_COMPILE_ARM32} \
        -j$(nproc) Image

    cp "${OUT_DIR}/arch/arm64/boot/Image" "${BUILD_DIR}/"

    echo -e "\n[INFO]: BUILD FINISHED! Image saved to ${BUILD_DIR}\n"
}

build_kernel
