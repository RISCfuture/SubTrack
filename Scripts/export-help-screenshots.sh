#!/bin/bash
#
# Turns the screenshot suite's result bundle into the Help book's image set.
#
#   Scripts/export-help-screenshots.sh <result-bundle.xcresult> <images-directory>
#
# XCUITest cannot hand a file back to its caller: xcodebuild forwards no shell environment into the
# runner process, so the tests cannot be told where to write and instead attach every capture to the
# result bundle. This unpacks that bundle, recovers each attachment's name, converts the capture out
# of the capturing display's colour space, and writes one WebP per screenshot.
#
# xcresulttool names exported files by UUID and records the name the test asked for only in
# manifest.json, mangled to "<slug>_<index>_<UUID>.png". The slug is recovered from that suffix,
# which is why the tests are required to name attachments as bare [a-z0-9-]+ slugs: a dot in the
# name is re-read as an extension and the recovery would silently mis-file the image.
#
# Owns <images-directory> outright — it is emptied first, so a screenshot dropped from the manifest
# leaves no stale file behind. That ownership is why a bundle carrying no named attachments is a
# hard error rather than a no-op: an empty export means the suite was skipped or its attachments
# were not kept, and quietly emptying the book's images over that would be a worse outcome than
# stopping. Which slugs must be present is the caller's business; this maps whatever it finds and
# prints each file it writes.

set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: $(basename "$0") <result-bundle> <images-directory>" >&2
  exit 2
fi

BUNDLE="$1"
IMAGES="$2"
SRGB_PROFILE="/System/Library/ColorSync/Profiles/sRGB Profile.icc"

[ -d "${BUNDLE}" ] || { echo "error: no result bundle at ${BUNDLE}" >&2; exit 1; }
[ -f "${SRGB_PROFILE}" ] || { echo "error: no sRGB profile at ${SRGB_PROFILE}" >&2; exit 1; }

# xcresulttool refuses to overwrite: exporting into a populated directory writes "UUID (1).png"
# siblings rather than replacing anything, so the export target has to be freshly made.
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
ATTACHMENTS="${WORK}/attachments"
INDEX="${WORK}/index.tsv"

# The per-test "no matching attachments" chatter is stdout noise; a real failure still reaches
# stderr and still trips the exit-on-error.
xcrun xcresulttool export attachments \
  --path "${BUNDLE}" \
  --output-path "${ATTACHMENTS}" >/dev/null

# Python rather than a text filter: the manifest is JSON, and the field order it happens to print in
# is not part of any contract. Anything whose name does not match the slug grammar is another test's
# attachment and is left alone.
/usr/bin/python3 - "${ATTACHMENTS}/manifest.json" >"${INDEX}" <<'PYTHON'
import json, re, sys

MANGLED = re.compile(
    r"^(?P<slug>[a-z0-9-]+)_\d+_"
    r"[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}\.png$"
)

with open(sys.argv[1]) as manifest:
    for test in json.load(manifest):
        for attachment in test.get("attachments", []):
            match = MANGLED.match(attachment.get("suggestedHumanReadableName", ""))
            if match:
                print(f"{attachment['exportedFileName']}\t{match['slug']}")
PYTHON

if [ ! -s "${INDEX}" ]; then
  echo "error: no named screenshot attachments in ${BUNDLE}" >&2
  echo "       the capture suite was skipped, or its attachments were not kept" >&2
  exit 1
fi

rm -rf "${IMAGES}"
mkdir -p "${IMAGES}"

# sips converts the pixels out of the capturing display's profile but leaves the input's stale XMP
# in place; ImageMagick then strips the metadata, which is the only part of its output that is not a
# function of the pixels — it stamps a tIME chunk and three date: text chunks that would otherwise
# make every regeneration a diff. cwebp embeds neither a timestamp nor a version string, so the
# encode is byte-identical run to run: -exact preserves the RGB under the transparent pixels a
# window capture's rounded corners carry, and -sharp_yuv earns its cost on UI text.
write_screenshot() {
  local exported="$1" slug="$2"
  sips --matchTo "${SRGB_PROFILE}" "${ATTACHMENTS}/${exported}" --out "${WORK}/srgb.png" >/dev/null
  magick "${WORK}/srgb.png" -strip "${WORK}/flat.png"
  cwebp -quiet -q 90 -m 6 -sharp_yuv -exact "${WORK}/flat.png" -o "${IMAGES}/${slug}.webp"
  echo "${IMAGES}/${slug}.webp"
}

while IFS=$'\t' read -r EXPORTED SLUG; do
  write_screenshot "${EXPORTED}" "${SLUG}"
done <"${INDEX}"
