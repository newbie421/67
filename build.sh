#!/usr/bin/env bash
set -euo pipefail

trap 'echo -e "\n[ERROR] Build failed at line ${LINENO}. Last 200 lines of log:\n"; tail -n 200 "${OUT_DIR}/build.log" || true' ERR

echo -e "\n[INFO]: BUILD STARTED..!\n"

# init submodules (ignore kalau tidak ada)
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

# Toolchain Slim LLVM 21.1.2
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

mkdir -p "${OUT_DIR}" "${BUILD_DIR}"

build_kernel() {
    echo -e "\n[INFO]: Using defconfig (${DEFCONFIG:-gki_defconfig})...\n"
    make -C "${KERNEL_ROOT}" O="${OUT_DIR}" \
        ARCH=${ARCH} LLVM=1 LLVM_IAS=1 \
        CROSS_COMPILE=${CROSS_COMPILE} CROSS_COMPILE_ARM32=${CROSS_COMPILE_ARM32} \
        CC=${CC} LD=${LD} AR=${AR} NM=${NM} OBJCOPY=${OBJCOPY} OBJDUMP=${OBJDUMP} READELF=${READELF} STRIP=${STRIP} \
        ${DEFCONFIG:-gki_defconfig} 2>&1 | tee "${OUT_DIR}/build.log"

    echo -e "\n[INFO]: Forcing FULL LTO...\n"
    "${KERNEL_ROOT}/scripts/config" --file "${OUT_DIR}/.config" \
        -e LTO_CLANG -e LTO_CLANG_FULL -d LTO_CLANG_THIN -d THINLTO || true

    make -C "${KERNEL_ROOT}" O="${OUT_DIR}" ARCH=${ARCH} olddefconfig \
        2>&1 | tee -a "${OUT_DIR}/build.log"

    echo -e "\n[INFO]: Building kernel Image...\n"
    make -C "${KERNEL_ROOT}" O="${OUT_DIR}" \
        ARCH=${ARCH} LLVM=1 LLVM_IAS=1 \
        CROSS_COMPILE=${CROSS_COMPILE} CROSS_COMPILE_ARM32=${CROSS_COMPILE_ARM32} \
        CC=${CC} LD=${LD} AR=${AR} NM=${NM} OBJCOPY=${OBJCOPY} OBJDUMP=${OBJDUMP} READELF=${READELF} STRIP=${STRIP} \
        -j"$(nproc)" Image 2>&1 | tee -a "${OUT_DIR}/build.log"

    if [ -f "${OUT_DIR}/arch/arm64/boot/Image" ]; then
        cp -v "${OUT_DIR}/arch/arm64/boot/Image" "${BUILD_DIR}/"
        gzip -9 -c "${BUILD_DIR}/Image" > "${BUILD_DIR}/Image.gz"
        echo -e "\n[INFO]: Build finished! Files saved in ${BUILD_DIR}\n"
    else
        echo "[ERROR] Kernel Image not found!"
        exit 1
    fi
}

build_kernel
