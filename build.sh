#!/usr/bin/env bash
set -euo pipefail

echo -e "\n[INFO] BUILD STARTED...\n"

# --- Paths & Info ---
KERNEL_ROOT="$(pwd)"
OUT_DIR="${KERNEL_ROOT}/out"
BUILD_DIR="${KERNEL_ROOT}/build"

export ARCH=arm64
export SUBARCH=arm64
export KBUILD_BUILD_USER="github-actions"
export KBUILD_BUILD_HOST="github"

# --- Toolchain ---
LLVM_DIR="${HOME}/toolchains/llvm-21"
export PATH="${LLVM_DIR}/bin:${PATH}"

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

# --- Prepare ---
mkdir -p "${OUT_DIR}" "${BUILD_DIR}"

# --- Build function ---
build_kernel() {
    echo -e "\n[INFO] Using defconfig (gki_defconfig)...\n"
    make -C "${KERNEL_ROOT}" O="${OUT_DIR}" \
        ARCH=${ARCH} LLVM=1 LLVM_IAS=1 \
        CROSS_COMPILE=${CROSS_COMPILE} CROSS_COMPILE_ARM32=${CROSS_COMPILE_ARM32} \
        gki_defconfig

    echo -e "\n[INFO] Forcing FULL LTO...\n"
    "${KERNEL_ROOT}/scripts/config" --file "${OUT_DIR}/.config" \
        -e LTO_CLANG \
        -e LTO_CLANG_FULL \
        -d LTO_CLANG_THIN \
        -d THINLTO || true

    make -C "${KERNEL_ROOT}" O="${OUT_DIR}" ARCH=${ARCH} olddefconfig

    echo -e "\n[INFO] Building kernel Image...\n"
    make -C "${KERNEL_ROOT}" O="${OUT_DIR}" \
        ARCH=${ARCH} LLVM=1 LLVM_IAS=1 \
        CROSS_COMPILE=${CROSS_COMPILE} CROSS_COMPILE_ARM32=${CROSS_COMPILE_ARM32} \
        CC=${CC} LD=${LD} AR=${AR} NM=${NM} OBJCOPY=${OBJCOPY} OBJDUMP=${OBJDUMP} READELF=${READELF} STRIP=${STRIP} \
        -j"$(nproc)" Image

    if [[ -f "${OUT_DIR}/arch/arm64/boot/Image" ]]; then
        cp -v "${OUT_DIR}/arch/arm64/boot/Image" "${BUILD_DIR}/"
        gzip -9 -c "${BUILD_DIR}/Image" > "${BUILD_DIR}/Image.gz"
        echo -e "\n[INFO] BUILD FINISHED! Output in ${BUILD_DIR}\n"
    else
        echo -e "\n[ERROR] Kernel Image not found!\n"
        exit 1
    fi
}

# --- Run Build ---
build_kernel
