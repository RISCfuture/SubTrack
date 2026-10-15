#!/bin/bash
#
# Turns the screenshot suite's result bundle into the Help book's image set.
#
#   Scripts/export-help-screenshots.sh <result-bundle.xcresult> <images-directory>
#
# extract-screenshot-attachments.sh recovers each capture as an sRGB PNG named by its slug; this
# writes one WebP per screenshot.
#
# Owns <images-directory> outright — it is emptied first, so a screenshot dropped from the suite
# leaves no stale file behind. That ownership is why a bundle carrying no named attachments is a
# hard error rather than a no-op: quietly emptying the book's images over a skipped suite would be a
# worse outcome than stopping. Which slugs must be present is the caller's business; this converts
# whatever it finds and prints each file it writes.

set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: $(basename "$0") <result-bundle> <images-directory>" >&2
  exit 2
fi

BUNDLE="$1"
IMAGES="$2"

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

"$(dirname "$0")/extract-screenshot-attachments.sh" "${BUNDLE}" "${WORK}" >/dev/null

rm -rf "${IMAGES}"
mkdir -p "${IMAGES}"

# cwebp embeds neither a timestamp nor a version string, so the encode is byte-identical run to run:
# -exact preserves the RGB under the transparent pixels a window capture's rounded corners carry,
# and -sharp_yuv earns its cost on UI text.
for png in "${WORK}"/*.png; do
  slug="$(basename "${png}" .png)"
  cwebp -quiet -q 90 -m 6 -sharp_yuv -exact "${png}" -o "${IMAGES}/${slug}.webp"
  echo "${IMAGES}/${slug}.webp"
done
