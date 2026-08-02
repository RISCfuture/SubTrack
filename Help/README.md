# The SubTrack Help book

`SubTrack.help` is the Apple Help book both editions ship. It is one book, in one language
folder, staged into each app at build time.

```text
SubTrack.help/Contents/
  Info.plist                        book metadata; CFBundleIdentifier is stamped at build
  Resources/
    help-icon.png                   HPDBookIconPath, reached as ../help-icon.png
    en.lproj/
      index.html                    the landing page and full table of contents
      *.html                        one article per topic
      subtrack-help.css
      images/                       generated — see Screenshots below
```

## How it gets into the app

The book sits outside every synchronized group on purpose. Xcode has no file type for the
`.help` extension, so a synchronized group descends into the bundle and treats each page as
a loose resource, colliding the book's own `Info.plist` with the target's. Staging it with
a script phase is what keeps the wrapper intact.

That phase is **Build Help Book**, on each app target, and it runs
`Scripts/build-help-book.sh`: the book is copied into the app's `Contents/Resources`, the
copy's `CFBundleIdentifier` is stamped with that edition's own book identifier, and
`hiutil` builds the CoreSpotlight search index each localization ships. The identifier is
stamped rather than checked in because `helpd` keys its registry on it, and both editions
ship the same content — one identifier for both would let whichever app registered last
answer for the other, which no user would ever see and every developer building both would.

## Writing a page

A new page needs `<meta name="robots" content="index, anchor">` in its `<head>`, plus an
`<a name="…">` on anything `HelpLink(anchor:)` should be able to open. The anchors the
interface asks for are named once in `Engine/Support/HelpAnchor.swift`, and the build
**fails** when that enum names one the book doesn't define — a misspelled anchor doesn't
error at runtime, it quietly opens the book's first page instead of the topic, so the build
is the only place to catch it.

`hiutil` records one target per page, so an anchor resolves exactly only when it is the
page's own anchor. A second anchor part-way down a page is reachable by an in-page
`href="#…"`, but a `HelpLink` pointing at it lands at the top of the page instead. If the
interface needs to land on a topic, give that topic its own page.

For styling and copy alone, skip the build: the pages are ordinary HTML and
`open Help/SubTrack.help/Contents/Resources/en.lproj/index.html` renders them in a browser.
Only anchors, search, and the icon need a real book.

## Reading it the way a user does

The viewer is **Tips.app**. `com.apple.helpviewer` resolves to
`/System/Applications/Tips.app` on current macOS — there is no longer a Help Viewer.app to
look for. The book can be opened without going through the app at all:

```sh
open "help:openbook=codes.tim.SubTrack-download.help"
open "help:anchor=slim-rules%20bookID=codes.tim.SubTrack-download.help"
```

## When an edit doesn't show up

**`helpd` does not read the book out of the app.** It copies it into its own group
container the first time it sees it, and serves the copy ever after:

```text
~/Library/Group Containers/group.com.apple.helpviewer.content/Library/Caches/
  codes.tim.SubTrack-download.codes.tim.SubTrack-download.help*1.0.help
```

That `*1.0` is the **app's** `CFBundleShortVersionString`, and it is the whole cache key.
The book's own version isn't in it, and neither is anything derived from the content — so
while the marketing version stays put, every rebuild is ignored and the copy taken the
first time is what the reader gets. An edit that never shows up, a page stuck without its
images, a Help menu landing on the generic macOS Tips page: all the same cause.

`hiutil -P` does **not** clear it. Clearing it is a `rm`:

```sh
rm -rf ~/Library/Group\ Containers/group.com.apple.helpviewer.content/Library/Caches/*.help
hiutil -P
```

**Then open the book once from the app's own Help menu before touching anything else.**
A purge leaves `helpd` with no materialized copy of the book, and until one exists it can
open the book but cannot resolve an *anchor* into it — every `HelpLink` reports "The
selected content is currently unavailable", and a `help:` URL falls through to the generic
page. Opening the book at its root is what materializes it; from then on anchors resolve
normally, including from a cold viewer. Clicking a help button as the first thing after a
purge looks exactly like a broken button, and isn't one.

One more trap when two copies of the app exist, which is routine here: a build in `/tmp`
and Xcode's own in DerivedData share a bundle identifier, and LaunchServices decides which
one `helpd` resolves the book from. If the pages you are looking at are older than the ones
you just built, that is why — check which copy won before assuming the build is at fault.

## Screenshots

The book's images are taken from the running app, not captured by hand:
`bundle exec fastlane mac help_screenshots` drives `HelpScreenshotUITests` over seeded
queues, then `Scripts/export-help-screenshots.sh` recovers each capture from the result
bundle and writes one WebP per shot, light and dark. Commit the images with the article
changes.

The lane **owns** `Help/SubTrack.help/Contents/Resources/en.lproj/images` and empties it
before writing, so nothing else may be kept there — which is why the book's icon sits at
`Contents/Resources/help-icon.png` and `HPDBookIconPath` reaches it as `../help-icon.png`.

It refuses to run on CI, and the suite itself skips unless the Mac draws the app the way
the shipped images are drawn: a 2× display, the multicolour accent, and Reduce
Transparency, Increase Contrast, Differentiate Without Colour, and Reduce Motion all off.

Two constraints on what a capture may contain. Nothing may be mid-animation — a stability
check waits for two byte-identical frames, so a fixture row left `probing` draws an
indeterminate spinner and the capture times out rather than settles. And a `Form`'s
sections cannot be framed: SwiftUI stamps a section's identifier onto each row it emits
instead of emitting one element spanning them, so shoot the whole pane or give the one
editor an `addressableSection(_:)` of its own.
