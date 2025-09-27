#!/usr/bin/env bash
set -euo pipefail

trap 'rc=$?; echo -e "\n[ERROR] Build failed (rc=$rc). Last 200 lines of ${OUT_DIR}/build.log:\n"; test -f "${OUT_DIR}/build.log" && tail -n 200 "${OUT_DIR}/build.log" || true; exit $rc' ERR

echo -e "\n[INFO] BUILD STARTED\n"

export KERNEL_ROOT="$(pwd)"
export OUT_DIR="${KERNEL_ROOT}/out"
export BUILD_DIR="${KERNEL_ROOT}/build"

export ARCH=arm64
export KBUILD_BUILD_USER="${KBUILD_BUILD_USER:-github-actions}"
export KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST:-github}"

# prefer toolchain provided by workflow (added to PATH via workflow)
export LLVM_DIR="${HOME}/toolchains/llvm-21"
export PATH="${LLVM_DIR}/bin:${PATH}"

export CROSS_COMPILE=${CROSS_COMPILE:-aarch64-linux-gnu-}
export CROSS_COMPILE_ARM32=${CROSS_COMPILE_ARM32:-arm-linux-gnueabi-}

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

echo "[INFO] Host: $(uname -a)" | tee -a "${OUT_DIR}/build.log"
echo "[INFO] CC=${CC} LD=${LD}" | tee -a "${OUT_DIR}/build.log"

# detect memory (MB)
MEM_MB=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo || echo 0)
echo "[INFO] MemTotal=${MEM_MB}MB" | tee -a "${OUT_DIR}/build.log"

# decide LTO mode and job count based on memory
LTO_MODE="thin"   # default thin
MAKE_JOBS="-j$(nproc)"
if [ "${MEM_MB}" -ge 24000 ]; then
  LTO_MODE="full"
  MAKE_JOBS="-j2"   # full LTO -> low parallelism
fi
echo "[INFO] Selected LTO_MODE=${LTO_MODE}, MAKE_JOBS=${MAKE_JOBS}" | tee -a "${OUT_DIR}/build.log"

# run defconfig
DEF=${DEFCONFIG:-gki_defconfig}
echo -e "\n[INFO] Running make ${DEF} ..." | tee -a "${OUT_DIR}/build.log"
make -C "${KERNEL_ROOT}" O="${OUT_DIR}" ARCH=${ARCH} LLVM=1 LLVM_IAS=1 \
  CROSS_COMPILE=${CROSS_COMPILE} CROSS_COMPILE_ARM32=${CROSS_COMPILE_ARM32} \
  CC=${CC} LD=${LD} AR=${AR} NM=${NM} OBJCOPY=${OBJCOPY} OBJDUMP=${OBJDUMP} READELF=${READELF} STRIP=${STRIP} \
  ${DEF} 2>&1 | tee -a "${OUT_DIR}/build.log"

# disable warnings-as-errors if possible
if [ -x "${KERNEL_ROOT}/scripts/config" ]; then
  echo -e "\n[INFO] Disabling CONFIG_WERROR if present" | tee -a "${OUT_DIR}/build.log"
  "${KERNEL_ROOT}/scripts/config" --file "${OUT_DIR}/.config" -d CONFIG_WERROR -d WERROR -d CONFIG_WARN_ERROR || true
fi

# set LTO options according to chosen mode
echo -e "\n[INFO] Configuring LTO mode: ${LTO_MODE}" | tee -a "${OUT_DIR}/build.log"
if [ "${LTO_MODE}" = "full" ]; then
  "${KERNEL_ROOT}/scripts/config" --file "${OUT_DIR}/.config" -e LTO_CLANG -e LTO_CLANG_FULL -d LTO_CLANG_THIN -d THINLTO || true
else
  "${KERNEL_ROOT}/scripts/config" --file "${OUT_DIR}/.config" -e LTO_CLANG -e LTO_CLANG_THIN -d LTO_CLANG_FULL -d THINLTO || true
fi

# sync config
echo -e "\n[INFO] Running olddefconfig to sync choices" | tee -a "${OUT_DIR}/build.log"
make -C "${KERNEL_ROOT}" O="${OUT_DIR}" ARCH=${ARCH} olddefconfig 2>&1 | tee -a "${OUT_DIR}/build.log"

# build with safety flags
echo -e "\n[INFO] Building Image with KCFLAGS='-Wno-error' and ${MAKE_JOBS}" | tee -a "${OUT_DIR}/build.log"
KCFLAGS_EXTRA="-Wno-error"
# run build
make -C "${KERNEL_ROOT}" O="${OUT_DIR}" \
  ARCH=${ARCH} LLVM=1 LLVM_IAS=1 \
  CROSS_COMPILE=${CROSS_COMPILE} CROSS_COMPILE_ARM32=${CROSS_COMPILE_ARM32} \
  CC=${CC} LD=${LD} AR=${AR} NM=${NM} OBJCOPY=${OBJCOPY} OBJDUMP=${OBJDUMP} READELF=${READELF} STRIP=${STRIP} \
  KCFLAGS="${KCFLAGS_EXTRA}" ${MAKE_JOBS} Image 2>&1 | tee -a "${OUT_DIR}/build.log"

# copy results
if [ -f "${OUT_DIR}/arch/arm64/boot/Image" ]; then
  cp -v "${OUT_DIR}/arch/arm64/boot/Image" "${BUILD_DIR}/Image" | tee -a "${OUT_DIR}/build.log"
  gzip -9 -c "${BUILD_DIR}/Image" > "${BUILD_DIR}/Image.gz"
  echo -e "\n[INFO] Build finished. Artifacts in ${BUILD_DIR}" | tee -a "${OUT_DIR}/build.log"
else
  echo "[ERROR] Kernel Image missing. See ${OUT_DIR}/build.log" | tee -a "${OUT_DIR}/build.log"
  exit 2
fi
