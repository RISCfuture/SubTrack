# ``SubTrackMAS``

The Mac App Store shell around the `SubTrack_Common` framework.

## Overview

This target is only an entry point: it builds the `FeatureFlags` for a sandboxed
App Store build — a reduced LGPL `ffmpeg` and VideoToolbox transcoding, no update
checker — and hands them to `AppEnvironment`. Every view, model, and queue lives
in `SubTrack_Common`, shared with the Developer-ID build.

## Topics

### Entry point

- ``SubTrackApp``
