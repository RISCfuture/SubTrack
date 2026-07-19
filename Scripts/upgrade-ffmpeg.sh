#!/usr/bin/env bash
#
# Upgrades (or refreshes) the pinned, hermetic ffmpeg builds the app bundles.
#
# With no arguments it force-rebuilds both variants from the versions currently
# pinned in build-ffmpeg.sh. Pass a flag to bump a pin first; the new value is
# written back into build-ffmpeg.sh so the change is committed alongside the code.
#
# Usage:
#   Scripts/upgrade-ffmpeg.sh [--ffmpeg VERSION] [--x264 COMMIT] [--x265 TAG] [--cmake VERSION]
#
# Examples:
#   Scripts/upgrade-ffmpeg.sh --ffmpeg 7.1.6   # security bump: re-pin, rebuild, verify
#   Scripts/upgrade-ffmpeg.sh                  # clean rebuild at the current pins
#
# It removes the build caches and Vendor outputs, rebuilds the lgpl and full
# variants, then verifies each binary runs, is self-contained (only system
# dylibs), exposes the codecs expected for its license, and can encode a sample.
#
# After it succeeds, review the pin change in build-ffmpeg.sh and rebuild the
# apps in Xcode (the Copy-ffmpeg phase re-signs the new binaries into the bundle).
#
# Requirements: same as build-ffmpeg.sh (curl, tar, git, make, clang) plus otool.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_SCRIPT="${REPO_ROOT}/Scripts/build-ffmpeg.sh"

# Rewrite a pinned CONSTANT="value" line in build-ffmpeg.sh, keeping any trailing comment.
bump() {
  local name="$1" value="$2"
  grep -q "^${name}=" "${BUILD_SCRIPT}" \
    || { echo "No pin named ${name} in build-ffmpeg.sh" >&2; exit 1; }
  sed -i '' -E "s|^(${name}=)\"[^\"]*\"|\1\"${value}\"|" "${BUILD_SCRIPT}"
  echo "==> Re-pinned ${name} = ${value}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ffmpeg) bump FFMPEG_VERSION "$2"; shift 2 ;;
    --x264)   bump X264_COMMIT "$2"; shift 2 ;;
    --x265)   bump X265_TAG "$2"; shift 2 ;;
    --cmake)  bump CMAKE_VERSION "$2"; shift 2 ;;
    -h|--help) sed -n '2,26p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1 (see --help)" >&2; exit 1 ;;
  esac
done

echo "==> Cleaning caches and vendored outputs"
rm -rf "${REPO_ROOT}/.build/ffmpeg" \
       "${REPO_ROOT}/Vendor/ffmpeg-lgpl" \
       "${REPO_ROOT}/Vendor/ffmpeg-full"

for variant in lgpl full; do
  echo "==> Rebuilding ${variant}"
  "${BUILD_SCRIPT}" "${variant}"
done

# Confirm a rebuilt variant runs, links only system libraries, has the right
# codecs for its license, and can encode.
verify() {
  local variant="$1"
  local dir="${REPO_ROOT}/Vendor/ffmpeg-${variant}"
  local ff="${dir}/ffmpeg" fp="${dir}/ffprobe"
  echo "==> Verifying ${variant}"
  [[ -x "${ff}" && -x "${fp}" ]] || { echo "   missing binaries in ${dir}" >&2; return 1; }

  local foreign
  foreign="$(otool -L "${ff}" "${fp}" \
    | grep -E '\.dylib|\.framework' \
    | grep -vE '/usr/lib/|/System/' || true)"
  if [[ -n "${foreign}" ]]; then
    echo "   NOT self-contained — links non-system libraries:" >&2
    echo "${foreign}" >&2
    return 1
  fi

  "${ff}" -hide_banner -version | head -1

  local encoders
  encoders="$("${ff}" -hide_banner -encoders 2>/dev/null)"
  grep -q 'hevc_videotoolbox' <<<"${encoders}" \
    || { echo "   missing hevc_videotoolbox" >&2; return 1; }

  # FFmpeg's native AV1 decoder is hwaccel-only, so without libaom an AV1
  # source fails with "Function not implemented" on every frame.
  local decoders
  decoders="$("${ff}" -hide_banner -decoders 2>/dev/null)"
  grep -q 'libaom-av1' <<<"${decoders}" \
    || { echo "   missing libaom-av1 (no software AV1 decode)" >&2; return 1; }
  if [[ "${variant}" == "full" ]]; then
    grep -q 'libx264' <<<"${encoders}" || { echo "   missing libx264 (full/GPL)" >&2; return 1; }
    grep -q 'libx265' <<<"${encoders}" || { echo "   missing libx265 (full/GPL)" >&2; return 1; }
  elif grep -q 'libx264' <<<"${encoders}"; then
    echo "   lgpl build unexpectedly links libx264 (GPL) — not App-Store-safe" >&2
    return 1
  fi

  local tmpd vcodec
  tmpd="$(mktemp -d)"
  [[ "${variant}" == "full" ]] && vcodec="libx264" || vcodec="hevc_videotoolbox"
  if "${ff}" -hide_banner -loglevel error -y \
      -f lavfi -i "testsrc=duration=1:size=128x128:rate=5" \
      -c:v "${vcodec}" -frames:v 5 "${tmpd}/out.mp4" \
      && [[ -s "${tmpd}/out.mp4" ]]; then
    echo "   encode smoke test (${vcodec}) ✓"
  else
    echo "   encode smoke test (${vcodec}) FAILED" >&2
    rm -rf "${tmpd}"
    return 1
  fi
  rm -rf "${tmpd}"
}

for variant in lgpl full; do
  verify "${variant}"
done

echo "==> ffmpeg upgrade complete. Review the pin change in build-ffmpeg.sh,"
echo "    then rebuild the apps in Xcode to re-bundle the new binaries."
