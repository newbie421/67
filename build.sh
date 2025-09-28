#!/bin/bash

echo -e "\n[INFO]: BUILD STARTED..!\n"

# init submodules
git submodule init && git submodule update

export KERNEL_ROOT="$(pwd)"
export ARCH=arm64
export KBUILD_BUILD_USER="github-actions"

# toolchain clang-r563880b (sudah di-download via workflow)
export CLANG_DIR="${HOME}/toolchains/clang-r563880b"
export PATH="${CLANG_DIR}/bin:${PATH}"

# cross compile
export CROSS_COMPILE=aarch64-linux-gnu-
export CROSS_COMPILE_ARM32=arm-linux-gnueabi-
export CC=clang
export LD=ld.lld

# Create necessary directories
mkdir -p "${KERNEL_ROOT}/out" "${KERNEL_ROOT}/build"

build_kernel(){
    # defconfig
    make -C ${KERNEL_ROOT} O=${KERNEL_ROOT}/out \
        ARCH=arm64 LLVM=1 LLVM_IAS=1 \
        CROSS_COMPILE=${CROSS_COMPILE} \
        CROSS_COMPILE_ARM32=${CROSS_COMPILE_ARM32} \
        CC=${CC} -j$(nproc) gki_defconfig

    # build Image
    make -C ${KERNEL_ROOT} O=${KERNEL_ROOT}/out \
        ARCH=arm64 LLVM=1 LLVM_IAS=1 \
        CROSS_COMPILE=${CROSS_COMPILE} \
        CROSS_COMPILE_ARM32=${CROSS_COMPILE_ARM32} \
        CC=${CC} -j$(nproc) Image || exit 1

    # copy hasil
    cp "${KERNEL_ROOT}/out/arch/arm64/boot/Image" "${KERNEL_ROOT}/build"

    echo -e "\n[INFO]: BUILD FINISHED..!\n"
}

build_kernel
