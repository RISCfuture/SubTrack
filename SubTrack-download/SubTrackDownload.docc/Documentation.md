# ``SubTrackDownload``

The Developer-ID shell around the `SubTrack_Common` framework.

## Overview

This target is only an entry point: it builds the `FeatureFlags` for an
unsandboxed, notarized build — a full `ffmpeg` codec set, a user-chosen `ffmpeg`
location, and GitHub-backed update checks — and hands them to `AppEnvironment`.
Every view, model, and queue lives in `SubTrack_Common`, shared with the App
Store build.

It also runs `ContainerMigration` at launch, because 1.0 was sandboxed and its
data has to be moved into the unsandboxed locations before anything reads it.

## Topics

### Entry point

- ``SubTrackApp``

### Updates

- ``GitHubUpdates``
