#!/usr/bin/env bash
set -euo pipefail

# untuk debug: tulis log terakhir saat error
trap 'rc=$?; echo -e "\n[ERROR] Build failed at line ${LINENO} (rc=$rc). Last 200 lines of log:\n"; test -f "${OUT_DIR}/build.log" && tail -n 200 "${OUT_DIR}/build.log" || true; exit $rc' ERR

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

# Default defconfig (bisa override: DEFCONFIG=foo make)
: "${DEFCONFIG:=gki_defconfig}"

# Toolchain dir (workflow harus menaruh toolchain host x86_64 di sini)
export LLVM_DIR="${HOME}/toolchains/llvm-21"
export PATH="${LLVM_DIR}/bin:${PATH}"

# Cross-compile defaults (toolchain must be host binaries that run on runner)
export CROSS_COMPILE=aarch64-linux-gnu-
export CROSS_COMPILE_ARM32=arm-linux-gnueabi-

# Compiler/linker defaults (bisa di-override dari env)
export CC=${CC:-clang}
export LD=${LD:-ld.lld}
export AR=${AR:-llvm-ar}
export NM=${NM:-llvm-nm}
export OBJCOPY=${OBJCOPY:-llvm-objcopy}
export OBJDUMP=${OBJDUMP:-llvm-objdump}
export READELF=${READELF:-llvm-readelf}
export STRIP=${STRIP:-llvm-strip}

# Make dirs
mkdir -p "${OUT_DIR}" "${BUILD_DIR}"
# clear previous log
: > "${OUT_DIR}/build.log"

# increase stack for LTO-heavy builds
ulimit -s unlimited || true

check_toolchain() {
    echo "[INFO] Checking clang/lld availability..."
    # clang
    if command -v clang >/dev/null 2>&1; then
        echo "[INFO] clang found: $(clang --version | head -n1)"
    else
        echo "[WARN] clang not found in PATH. Make sure you downloaded a host clang into ${LLVM_DIR} or installed clang via apt."
    fi

    # check ld.lld binary is runnable and matches host arch
    if command -v ld.lld >/dev/null 2>&1; then
        LD_BIN=$(command -v ld.lld)
        fileout=$(file -b "$LD_BIN" || true)
        hostarch=$(uname -m)
        echo "[INFO] ld.lld found: ${LD_BIN} (${fileout})"
        # crude check: ensure hostarch (x86_64) matches ld binary type
        if echo "$hostarch" | grep -q "x86"; then
            if echo "$fileout" | grep -qiE "x86|Intel|Intel.*80386|AMD"; then
                echo "[INFO] ld.lld looks like x86_64 host binary - OK"
            else
                echo "[WARN] ld.lld does NOT look like a host x86_64 binary (runner: ${hostarch}). Falling back to system linker 'ld'."
                LD=ld
            fi
        fi
    else
        echo "[WARN] ld.lld not found in PATH. Falling back to 'ld' (may break LLVM LTO)."
        LD=ld
    fi
}

disable_werror() {
    # after first .config is generated we try to disable CONFIG_WERROR and re-run olddefconfig
    if [ -x "${KERNEL_ROOT}/scripts/config" ]; then
        echo "[INFO] Disabling CONFIG_WERROR (if present) via scripts/config"
        "${KERNEL_ROOT}/scripts/config" --file "${OUT_DIR}/.config" -d CONFIG_WERROR -d WERROR || true
    else
        echo "[WARN] scripts/config not found or not executable; will not toggle CONFIG_WERROR automatically."
    fi
}

build_kernel() {
    echo -e "\n[INFO]: Using defconfig (${DEFCONFIG})...\n"
    # run defconfig
    make -C "${KERNEL_ROOT}" O="${OUT_DIR}" \
        ARCH=${ARCH} LLVM=1 LLVM_IAS=1 \
        CROSS_COMPILE=${CROSS_COMPILE} CROSS_COMPILE_ARM32=${CROSS_COMPILE_ARM32} \
        CC=${CC} LD=${LD} AR=${AR} NM=${NM} OBJCOPY=${OBJCOPY} OBJDUMP=${OBJDUMP} READELF=${READELF} STRIP=${STRIP} \
        ${DEFCONFIG} 2>&1 | tee -a "${OUT_DIR}/build.log"

    # try to disable warnings-as-errors so warnings don't stop the build
    disable_werror

    # force FULL LTO options (enable clang full LTO, disable thin)
    if [ -f "${OUT_DIR}/.config" ]; then
        echo -e "\n[INFO]: Forcing FULL LTO options in .config\n"
        "${KERNEL_ROOT}/scripts/config" --file "${OUT_DIR}/.config" \
            -e LTO_CLANG -e LTO_CLANG_FULL -d LTO_CLANG_THIN -d THINLTO || true

        # re-run olddefconfig to apply new choices
        make -C "${KERNEL_ROOT}" O="${OUT_DIR}" ARCH=${ARCH} olddefconfig 2>&1 | tee -a "${OUT_DIR}/build.log"
    else
        echo "[WARN] .config not found after defconfig; aborting"
        exit 1
    fi

    echo -e "\n[INFO]: Building kernel Image (this may take long)...\n"

    # Use KCFLAGS fallback in case Werror still enforced by tree
    KCFLAGS_EXTRA="-Wno-error"

    make -C "${KERNEL_ROOT}" O="${OUT_DIR}" \
        ARCH=${ARCH} LLVM=1 LLVM_IAS=1 \
        CROSS_COMPILE=${CROSS_COMPILE} CROSS_COMPILE_ARM32=${CROSS_COMPILE_ARM32} \
        CC=${CC} LD=${LD} AR=${AR} NM=${NM} OBJCOPY=${OBJCOPY} OBJDUMP=${OBJDUMP} READELF=${READELF} STRIP=${STRIP} \
        KCFLAGS="${KCFLAGS_EXTRA}" \
        -j"$(nproc)" Image 2>&1 | tee -a "${OUT_DIR}/build.log"

    if [ -f "${OUT_DIR}/arch/arm64/boot/Image" ]; then
        cp -v "${OUT_DIR}/arch/arm64/boot/Image" "${BUILD_DIR}/" | tee -a "${OUT_DIR}/build.log" || true
        gzip -9 -c "${BUILD_DIR}/Image" > "${BUILD_DIR}/Image.gz"
        echo -e "\n[INFO]: Build finished! Files saved in ${BUILD_DIR}\n"
    else
        echo "[ERROR] Kernel Image not found in ${OUT_DIR}/arch/arm64/boot/"
        exit 1
    fi
}

# check toolchain early
check_toolchain

# run build
build_kernel
