#!/bin/bash
#
# Prints one version's section of CHANGELOG.md, for whatever wants the release notes.
#
#   Scripts/release-notes.sh [--plain] <version> [locale]
#
# The Release workflow pipes this into `gh release create --notes-file`, and `--plain` is what goes
# into App Store Connect's "What's New". One source for both, so the two channels cannot drift into
# describing the same build differently.
#
# `--plain` renders the section as App Store Connect wants it: no Markdown, since that field shows
# the text verbatim, and no hard wrapping, since it reflows to whatever width the reader's App Store
# is. Headings become plain lines, bullets become "•", and inline code loses its backticks.
#
# LOCALES. A translated listing gives a locale its own heading at the same level as the version —
# `## 1.2 de-DE` beside `## 1.2` — and asking for that locale selects it. They sit at the version
# level rather than nested under it so `###` stays free for the category headings this changelog
# already uses, and so selecting a section stays one exact string match rather than a rule about
# which headings are locales. A locale with no section of its own falls back to the version's
# default text, so a newly added territory reads that rather than nothing.
#
# The heading line itself is dropped: `gh` puts the version in the release title already, and App
# Store Connect has no use for it either. Everything up to the next "## " heading is the section.

set -euo pipefail

plain=false
if [ "${1:-}" = "--plain" ]; then
  plain=true
  shift
fi

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "usage: $(basename "$0") [--plain] <version> [locale]" >&2
  exit 2
fi

version="$1"
locale="${2:-}"
changelog="$(dirname "$0")/../CHANGELOG.md"

if [ ! -f "$changelog" ]; then
  echo "No changelog at $changelog." >&2
  exit 1
fi

# `-v version=` rather than interpolating: a version string is data, and awk would otherwise parse
# whatever it contains. Matching is on the whole line so "1.1" cannot select the "1.10" section.
section() {
  awk -v heading="## $1" '
    $0 == heading { collecting = 1; next }
    collecting && /^## / { exit }
    collecting { print }
  ' "$changelog"
}

notes=""
[ -n "$locale" ] && notes=$(section "$version $locale")
[ -z "$notes" ] && notes=$(section "$version")

# Trim the blank lines the section is bracketed by, then refuse an empty one. A release whose notes
# silently came out empty is worse than one that fails here: the tag is already pushed by then, and
# the notes are what the user reads to decide whether to update.
notes=$(printf '%s\n' "$notes" | sed -e '/./,$!d' | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')

if [ -z "$notes" ]; then
  echo "CHANGELOG.md has no \"## $version\" section. Add one before tagging $version." >&2
  exit 1
fi

if [ "$plain" = false ]; then
  printf '%s\n' "$notes"
  exit 0
fi

# Unwrapping is why this is awk and not a sed pipeline: a bullet spans however many lines the
# 80-column source needed, and joining them is a decision about the *previous* line, which a
# line-at-a-time filter cannot make without holding one back.
printf '%s\n' "$notes" | awk '
  function flush() { if (buffer != "") { print buffer; buffer = "" } }
  { gsub(/`/, "") }
  /^#+ / { flush(); sub(/^#+ /, ""); print ""; print; next }
  /^[-*] / { flush(); sub(/^[-*] /, "• "); buffer = $0; next }
  /^[[:space:]]*$/ { flush(); next }
  { sub(/^[[:space:]]+/, ""); buffer = (buffer == "" ? $0 : buffer " " $0) }
  END { flush() }
' | sed -e '/./,$!d'
