#!/usr/bin/env bash
#
# Builds self-contained static ffmpeg/ffprobe binaries for bundling in the app.
#
# Hermetic: every dependency is fetched from a pinned upstream source and built
# from scratch — nothing is taken from Homebrew or the system. The resulting
# binaries statically link the FFmpeg (and, for `full`, x264/x265) libraries and
# dynamically link only macOS system frameworks (incl. VideoToolbox / AudioToolbox).
#
# Variants:
#   lgpl  (default) — App-Store-safe: no GPL/nonfree; VideoToolbox transcoding.
#   full            — GPL: adds libx264 + libx265 (built from source).
#
# Usage:
#   Scripts/build-ffmpeg.sh [lgpl|full]
#
# Output:
#   Vendor/ffmpeg-<variant>/ffmpeg
#   Vendor/ffmpeg-<variant>/ffprobe
#
# The Xcode app targets copy these into Contents/Helpers via a Code-Sign-On-Copy
# build phase. Re-run only when changing a pinned version; outputs are git-ignored.
#
# Nothing here floats to "latest": FFmpeg, x264, x265 and CMake are all pinned
# below, so builds are reproducible from a clean checkout.
#
# Upgrading a pinned dependency:
#   1. Bump the relevant constant below (usually just FFMPEG_VERSION for a
#      security update; x264/x265 move rarely).
#   2. Force a rebuild by removing the caches and outputs:
#        rm -rf .build/ffmpeg Vendor/ffmpeg-lgpl Vendor/ffmpeg-full
#   3. Rebuild both variants:
#        Scripts/build-ffmpeg.sh lgpl && Scripts/build-ffmpeg.sh full
#   4. Re-run the encode smoke tests and the app's ffmpeg-version display to
#      confirm the new binaries run and self-contain (otool -L shows only
#      /usr/lib and /System).
#
# Requirements: curl, tar, git, make, clang (Xcode CLT). CMake is fetched (pinned)
# when needed, so it need not be installed.
set -euo pipefail

FFMPEG_VERSION="7.1.5"
X264_COMMIT="b35605ace3ddf7c1a5d67a2eb553f034aef41d55" # videolan/x264 stable
X265_TAG="4.1"
AOM_TAG="v3.10.0"
CMAKE_VERSION="3.30.5"
# arm64 on Apple Silicon. The app targets pin ARCHS to arm64 to match: a universal app
# bundling a single-slice helper would ship an Intel slice that cannot run ffmpeg at all.
# Going universal means adding an x86_64 slice here and lipo'ing, then dropping that pin.
ARCH="$(uname -m)"
MIN_MACOS="13.0"

VARIANT="${1:-lgpl}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE_DIR="${REPO_ROOT}/.build/ffmpeg"
DEPS="${CACHE_DIR}/deps-${VARIANT}"
OUT_DIR="${REPO_ROOT}/Vendor/ffmpeg-${VARIANT}"
JOBS="$(sysctl -n hw.ncpu)"
CFLAGS_COMMON="-arch ${ARCH} -mmacosx-version-min=${MIN_MACOS}"

echo "==> Building ffmpeg ${FFMPEG_VERSION} (${VARIANT}, ${ARCH})"

if [[ -x "${OUT_DIR}/ffmpeg" && -x "${OUT_DIR}/ffprobe" ]]; then
  echo "==> Already built at ${OUT_DIR}; nothing to do."
  exit 0
fi
mkdir -p "${CACHE_DIR}"

# Downloads the pinned macOS CMake, cached under .build. Deliberately ignores any cmake already on
# PATH: x265 still declares a pre-3.5 `cmake_minimum_required`, which CMake 4 refuses outright
# ("Compatibility with CMake < 3.5 has been removed"), so a machine with a current Homebrew cmake
# cannot configure it. Pinning here matches every other version in this script.
fetch_cmake() {
  local dir="${CACHE_DIR}/cmake-${CMAKE_VERSION}-macos-universal"
  local bin="${dir}/CMake.app/Contents/bin/cmake"
  if [[ ! -x "${bin}" ]]; then
    echo "==> Fetching CMake ${CMAKE_VERSION}" >&2
    curl -L -o "${CACHE_DIR}/cmake.tar.gz" \
      "https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-macos-universal.tar.gz"
    tar -xzf "${CACHE_DIR}/cmake.tar.gz" -C "${CACHE_DIR}"
  fi
  echo "${bin}"
}

build_x264() {
  echo "==> Building x264 (${X264_COMMIT:0:10})"
  local src="${CACHE_DIR}/x264"
  [[ -d "${src}/.git" ]] || git clone https://code.videolan.org/videolan/x264.git "${src}"
  git -C "${src}" checkout -q "${X264_COMMIT}"
  (
    cd "${src}"
    make distclean >/dev/null 2>&1 || true
    ./configure --prefix="${DEPS}" --enable-static --enable-pic \
      --disable-cli --disable-opencl \
      --extra-cflags="${CFLAGS_COMMON}" --extra-asflags="${CFLAGS_COMMON}" \
      --extra-ldflags="${CFLAGS_COMMON}"
    make -j"${JOBS}"
    make install
  )
}

build_x265() {
  echo "==> Building x265 ${X265_TAG}"
  local src="${CACHE_DIR}/x265"
  [[ -d "${src}/.git" ]] \
    || git clone --branch "${X265_TAG}" --depth 1 https://bitbucket.org/multicoreware/x265_git.git "${src}"
  local cmake_bin build="${src}/build-mac"
  cmake_bin="$(fetch_cmake)"
  rm -rf "${build}"
  mkdir -p "${build}"
  (
    cd "${build}"
    "${cmake_bin}" -G "Unix Makefiles" \
      -DCMAKE_INSTALL_PREFIX="${DEPS}" \
      -DENABLE_SHARED=OFF -DENABLE_CLI=OFF \
      -DCMAKE_OSX_DEPLOYMENT_TARGET="${MIN_MACOS}" \
      -DCMAKE_OSX_ARCHITECTURES="${ARCH}" \
      ../source
    make -j"${JOBS}"
    make install
  )
}

build_aom() {
  echo "==> Building libaom ${AOM_TAG}"
  local src="${CACHE_DIR}/aom"
  [[ -d "${src}/.git" ]] \
    || git clone --branch "${AOM_TAG}" --depth 1 https://aomedia.googlesource.com/aom "${src}"
  local cmake_bin build="${CACHE_DIR}/aom-build"
  cmake_bin="$(fetch_cmake)"
  rm -rf "${build}"
  mkdir -p "${build}"
  (
    cd "${build}"
    # This exists to give AV1 sources a software decode path: FFmpeg's native
    # AV1 decoder carries hwaccel hooks only, and Apple silicon has no AV1
    # hardware decoder, so an AV1 input otherwise fails with "Function not
    # implemented" on every frame.
    #
    # The encoder is built even though nothing here encodes AV1, because
    # FFmpeg's --enable-libaom compiles libaomenc.c alongside libaomdec.c and
    # that file needs <aom/aom_encoder.h>. Configuring aom with
    # CONFIG_AV1_ENCODER=0 omits the header and breaks the FFmpeg build.
    "${cmake_bin}" -G "Unix Makefiles" \
      -DCMAKE_INSTALL_PREFIX="${DEPS}" \
      -DBUILD_SHARED_LIBS=OFF \
      -DENABLE_EXAMPLES=OFF -DENABLE_TESTS=OFF -DENABLE_TOOLS=OFF -DENABLE_DOCS=OFF \
      -DCMAKE_OSX_DEPLOYMENT_TARGET="${MIN_MACOS}" \
      -DCMAKE_OSX_ARCHITECTURES="${ARCH}" \
      "${src}"
    make -j"${JOBS}"
    make install
  )
}

# ---- Dependencies for the FFmpeg build ------------------------------------
# Both variants get libaom: it is BSD-licensed, so it is safe in the
# App-Store-bound lgpl build as well as full.
rm -rf "${DEPS}"
mkdir -p "${DEPS}"
build_aom

license_flags=(--disable-gpl --disable-nonfree --enable-libaom --pkg-config-flags=--static)

if [[ "${VARIANT}" == "full" ]]; then
  build_x264
  build_x265
  license_flags=(
    --enable-gpl --disable-nonfree
    --enable-libaom --enable-libx264 --enable-libx265 --pkg-config-flags=--static
  )
fi

export PKG_CONFIG_PATH="${DEPS}/lib/pkgconfig"
# Static-only deps prefix ⇒ the linker links the .a files statically.
extra_cflags="${CFLAGS_COMMON} -I${DEPS}/include"
extra_ldflags="${CFLAGS_COMMON} -L${DEPS}/lib"

# ---- FFmpeg ---------------------------------------------------------------
SRC_DIR="${CACHE_DIR}/ffmpeg-${FFMPEG_VERSION}"
if [[ ! -d "${SRC_DIR}" ]]; then
  echo "==> Downloading FFmpeg ${FFMPEG_VERSION}"
  curl -L -o "${CACHE_DIR}/ffmpeg.tar.xz" "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz"
  tar -xJf "${CACHE_DIR}/ffmpeg.tar.xz" -C "${CACHE_DIR}"
fi

cd "${SRC_DIR}"
make distclean >/dev/null 2>&1 || true

./configure \
  --prefix="${SRC_DIR}/install" \
  --disable-shared --enable-static \
  --disable-programs --enable-ffmpeg --enable-ffprobe \
  --disable-doc --disable-debug --disable-network --disable-x86asm \
  --disable-autodetect --disable-sdl2 --disable-xlib --disable-libxcb \
  --enable-videotoolbox --enable-audiotoolbox \
  "${license_flags[@]}" \
  --arch="${ARCH}" \
  --extra-cflags="${extra_cflags}" \
  --extra-ldflags="${extra_ldflags}"

make -j"${JOBS}"

mkdir -p "${OUT_DIR}"
cp ffmpeg ffprobe "${OUT_DIR}/"
strip -S "${OUT_DIR}/ffmpeg" "${OUT_DIR}/ffprobe" || true

echo "==> Done:"
ls -lh "${OUT_DIR}/ffmpeg" "${OUT_DIR}/ffprobe"
"${OUT_DIR}/ffmpeg" -hide_banner -version | head -1
