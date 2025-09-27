#!/usr/bin/env bash
set -euo pipefail

# show tail of log on error
trap 'rc=$?; echo -e "\n[ERROR] Build failed (rc=$rc). Last 200 lines of ${OUT_DIR}/build.log:\n"; test -f "${OUT_DIR}/build.log" && tail -n 200 "${OUT_DIR}/build.log" || true; exit $rc' ERR

echo -e "\n[INFO] BUILD STARTED\n"

export KERNEL_ROOT="$(pwd)"
export OUT_DIR="${KERNEL_ROOT}/out"
export BUILD_DIR="${KERNEL_ROOT}/build"

export ARCH=arm64
export KBUILD_BUILD_USER="${KBUILD_BUILD_USER:-github-actions}"
export KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST:-github}"

# Prefer toolchain provided by workflow; fallback to PATH
export LLVM_DIR="${HOME}/toolchains/llvm-21"
export PATH="${LLVM_DIR}/bin:${PATH}"

export CROSS_COMPILE=${CROSS_COMPILE:-aarch64-linux-gnu-}
export CROSS_COMPILE_ARM32=${CROSS_COMPILE_ARM32:-arm-linux-gnueabi-}

# compiler tools (may be overridden by env)
export CC=${CC:-clang}
export LD=${LD:-ld.lld}
export AR=${AR:-llvm-ar}
export NM=${NM:-llvm-nm}
export OBJCOPY=${OBJCOPY:-llvm-objcopy}
export OBJDUMP=${OBJDUMP:-llvm-objdump}
export READELF=${READELF:-llvm-readelf}
export STRIP=${STRIP:-llvm-strip}

mkdir -p "${OUT_DIR}" "${BUILD_DIR}"
: > "${OUT_DIR}/build.log"

echo "[INFO] Host: $(uname -a)"
echo "[INFO] Using CC=${CC}, LD=${LD}" | tee -a "${OUT_DIR}/build.log"
command -v "${CC}" >/dev/null 2>&1 && ${CC} --version | head -n1 2>&1 | tee -a "${OUT_DIR}/build.log" || true
command -v "${LD}" >/dev/null 2>&1 && file $(command -v "${LD}") 2>&1 | tee -a "${OUT_DIR}/build.log" || echo "[WARN] ${LD} not found" | tee -a "${OUT_DIR}/build.log"

# increase stack for LTO-heavy builds
ulimit -s unlimited || true

# 1) generate defconfig (gki_defconfig)
DEF=${DEFCONFIG:-gki_defconfig}
echo -e "\n[INFO] Running make ${DEF} ..." | tee -a "${OUT_DIR}/build.log"
make -C "${KERNEL_ROOT}" O="${OUT_DIR}" ARCH=${ARCH} LLVM=1 LLVM_IAS=1 \
    CROSS_COMPILE=${CROSS_COMPILE} CROSS_COMPILE_ARM32=${CROSS_COMPILE_ARM32} \
    CC=${CC} LD=${LD} AR=${AR} NM=${NM} OBJCOPY=${OBJCOPY} OBJDUMP=${OBJDUMP} READELF=${READELF} STRIP=${STRIP} \
    ${DEF} 2>&1 | tee -a "${OUT_DIR}/build.log"

# 2) disable WERROR if present to avoid warnings-as-errors
if [ -x "${KERNEL_ROOT}/scripts/config" ]; then
  echo -e "\n[INFO] Disabling CONFIG_WERROR / WERROR if present" | tee -a "${OUT_DIR}/build.log"
  "${KERNEL_ROOT}/scripts/config" --file "${OUT_DIR}/.config" -d CONFIG_WERROR -d WERROR -d CONFIG_WARN_ERROR || true
else
  echo "[WARN] scripts/config not available; continuing" | tee -a "${OUT_DIR}/build.log"
fi

# 3) force full LTO flags
echo -e "\n[INFO] Forcing LTO_CLANG_FULL and disabling thin-LTO" | tee -a "${OUT_DIR}/build.log"
"${KERNEL_ROOT}/scripts/config" --file "${OUT_DIR}/.config" \
    -e LTO_CLANG -e LTO_CLANG_FULL -d LTO_CLANG_THIN -d THINLTO || true

# sync config
echo -e "\n[INFO] Running olddefconfig to sync choices" | tee -a "${OUT_DIR}/build.log"
make -C "${KERNEL_ROOT}" O="${OUT_DIR}" ARCH=${ARCH} olddefconfig 2>&1 | tee -a "${OUT_DIR}/build.log"

# 4) build Image (add KCFLAGS fallback to ignore -Werror)
echo -e "\n[INFO] Building Image (this may take long). Using KCFLAGS=\"-Wno-error\" as safety." | tee -a "${OUT_DIR}/build.log"
KCFLAGS_EXTRA="-Wno-error"
# optionally user can override MAKEFLAGS env
MAKE_JOBS="${MAKEFLAGS:- -j$(nproc)}"
make -C "${KERNEL_ROOT}" O="${OUT_DIR}" \
    ARCH=${ARCH} LLVM=1 LLVM_IAS=1 \
    CROSS_COMPILE=${CROSS_COMPILE} CROSS_COMPILE_ARM32=${CROSS_COMPILE_ARM32} \
    CC=${CC} LD=${LD} AR=${AR} NM=${NM} OBJCOPY=${OBJCOPY} OBJDUMP=${OBJDUMP} READELF=${READELF} STRIP=${STRIP} \
    KCFLAGS="${KCFLAGS_EXTRA}" ${MAKE_JOBS} Image 2>&1 | tee -a "${OUT_DIR}/build.log"

# copy+compress result
if [ -f "${OUT_DIR}/arch/arm64/boot/Image" ]; then
    cp -v "${OUT_DIR}/arch/arm64/boot/Image" "${BUILD_DIR}/Image" | tee -a "${OUT_DIR}/build.log"
    gzip -9 -c "${BUILD_DIR}/Image" > "${BUILD_DIR}/Image.gz"
    echo -e "\n[INFO] Build finished successfully. Artifacts in ${BUILD_DIR}" | tee -a "${OUT_DIR}/build.log"
else
    echo "[ERROR] Kernel Image missing. See ${OUT_DIR}/build.log" | tee -a "${OUT_DIR}/build.log"
    exit 2
fi
