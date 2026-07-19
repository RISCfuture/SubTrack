#!/bin/bash
#
# Collects the complete corresponding source for the FFmpeg the download edition bundles, so it can
# be attached to a GitHub release.
#
#   Scripts/collect-ffmpeg-sources.sh <version> <output-directory>
#
# Produces "<output-directory>/ffmpeg-sources-<version>.tar.xz" and prints its path.
#
# The download build links libx264 and libx265, both GPL, which makes the bundled binary a GPL work
# and obliges us to distribute its source alongside the binary. Every version is read straight out
# of build-ffmpeg.sh, so this can never describe a different build than the one that shipped: that
# script is the single place the pins live, and it is included in the archive too, since it is what
# turns these sources into the exact binaries in the app.

set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: $(basename "$0") <version> <output-directory>" >&2
  exit 2
fi

VERSION="$1"
OUT_DIR="$2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_SCRIPT="${SCRIPT_DIR}/build-ffmpeg.sh"

# Read a pinned version out of the build script rather than repeating it here.
pin() {
  local name="$1" value
  value="$(sed -n "s/^${name}=\"\([^\"]*\)\".*/\1/p" "${BUILD_SCRIPT}" | head -1)"
  if [ -z "${value}" ]; then
    echo "error: no ${name} pin found in ${BUILD_SCRIPT}" >&2
    exit 1
  fi
  echo "${value}"
}

FFMPEG_VERSION="$(pin FFMPEG_VERSION)"
X264_COMMIT="$(pin X264_COMMIT)"
X265_TAG="$(pin X265_TAG)"
AOM_TAG="$(pin AOM_TAG)"

mkdir -p "${OUT_DIR}"
OUT_DIR="$(cd "${OUT_DIR}" && pwd)"
ARCHIVE="${OUT_DIR}/ffmpeg-sources-${VERSION}.tar.xz"
rm -f "${ARCHIVE}"

STAGE="$(mktemp -d)"
trap 'rm -rf "${STAGE}"' EXIT
ROOT="${STAGE}/ffmpeg-sources-${VERSION}"
mkdir -p "${ROOT}"

echo "==> FFmpeg ${FFMPEG_VERSION}" >&2
curl -fsSL --retry 3 -o "${ROOT}/ffmpeg-${FFMPEG_VERSION}.tar.xz" \
  "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz"

# The GPL libraries are distributed as git repositories rather than release tarballs, so each is
# cloned at its pin and packed. --depth 1 on an explicit revision keeps this to one commit.
pack_git() {
  local name="$1" url="$2" ref="$3"
  local dir="${STAGE}/${name}"
  echo "==> ${name} ${ref}" >&2
  git init -q "${dir}"
  git -C "${dir}" remote add origin "${url}"
  git -C "${dir}" fetch -q --depth 1 origin "${ref}"
  git -C "${dir}" checkout -q FETCH_HEAD
  rm -rf "${dir}/.git"
  tar -C "${STAGE}" -czf "${ROOT}/${name}-${ref}.tar.gz" "${name}"
  rm -rf "${dir}"
}

pack_git x264 "https://code.videolan.org/videolan/x264.git" "${X264_COMMIT}"
pack_git x265 "https://bitbucket.org/multicoreware/x265_git.git" "${X265_TAG}"
pack_git aom "https://aomedia.googlesource.com/aom" "${AOM_TAG}"

cp "${BUILD_SCRIPT}" "${ROOT}/build-ffmpeg.sh"

cat > "${ROOT}/README.txt" <<EOF
Complete corresponding source for the FFmpeg bundled with SubTrack ${VERSION}
(direct download edition).

  ffmpeg-${FFMPEG_VERSION}.tar.xz   FFmpeg, as released upstream
  x264-${X264_COMMIT}.tar.gz        x264 at the pinned commit
  x265-${X265_TAG}.tar.gz           x265 at the pinned tag
  aom-${AOM_TAG}.tar.gz             libaom at the pinned tag
  build-ffmpeg.sh                   the script that configures and builds them

Unpack the archives beside build-ffmpeg.sh and run "build-ffmpeg.sh full" to
reproduce the ffmpeg and ffprobe binaries inside SubTrack.app/Contents/Helpers.

FFmpeg, x264, and x265 are licensed under the GNU General Public License,
version 2 or later; libaom under the BSD 2-Clause license with the Alliance for
Open Media Patent License 1.0. SubTrack's own source is at
https://github.com/RISCfuture/SubTrack.
EOF

tar -C "${STAGE}" -cJf "${ARCHIVE}" "ffmpeg-sources-${VERSION}"

echo "${ARCHIVE}"
