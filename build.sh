#!/bin/bash
set -e

echo -e "\n[INFO]: BUILD STARTED..!\n"

# init submodules (kalau ada, biar gak error kalau kosong)
git submodule init && git submodule update || true

# Path kernel
export KERNEL_ROOT="$(pwd)"
export OUT_DIR="${KERNEL_ROOT}/out"
export BUILD_DIR="${KERNEL_ROOT}/build"

# Basic info
export ARCH=arm64
export SUBARCH=arm64
export KBUILD_BUILD_USER="github-actions"
export KBUILD_BUILD_HOST="github"

# Toolchain LLVM (sudah di-download via workflow)
export LLVM_DIR="${HOME}/toolchains/llvm-21"
export PATH="${LLVM_DIR}/bin:${PATH}"

# Cross compile
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

# Buat direktori out & build
mkdir -p "${OUT_DIR}" "${BUILD_DIR}"

build_kernel() {
    echo -e "\n[INFO]: Using defconfig (gki_defconfig)...\n"
    make -C "${KERNEL_ROOT}" O="${OUT_DIR}" \
        ARCH=${ARCH} LLVM=1 LLVM_IAS=1 \
        CROSS_COMPILE=${CROSS_COMPILE} CROSS_COMPILE_ARM32=${CROSS_COMPILE_ARM32} \
        CC=${CC} -j"$(nproc)" gki_defconfig

    echo -e "\n[INFO]: Building kernel Image...\n"
    make -C "${KERNEL_ROOT}" O="${OUT_DIR}" \
        ARCH=${ARCH} LLVM=1 LLVM_IAS=1 \
        CROSS_COMPILE=${CROSS_COMPILE} CROSS_COMPILE_ARM32=${CROSS_COMPILE_ARM32} \
        CC=${CC} -j"$(nproc)" Image

    if [ -f "${OUT_DIR}/arch/arm64/boot/Image" ]; then
        cp "${OUT_DIR}/arch/arm64/boot/Image" "${BUILD_DIR}/"
        echo -e "\n[INFO]: BUILD FINISHED! Kernel Image saved in ${BUILD_DIR}\n"
    else
        echo "[ERROR]: Kernel Image not found!"
        exit 1
    fi
}

build_kernel
