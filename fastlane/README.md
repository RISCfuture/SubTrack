fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## Mac

### mac beta

```sh
[bundle exec] fastlane mac beta
```

Build and upload the App Store edition to TestFlight

### mac release

```sh
[bundle exec] fastlane mac release
```

Build and upload the App Store edition to App Store Connect

### mac download_release

```sh
[bundle exec] fastlane mac download_release
```

Build, notarize, and package the downloadable edition as a disk image

### mac ci_next_build_number

```sh
[bundle exec] fastlane mac ci_next_build_number
```

Resolve the next build number and write it where CI can read it

### mac ci_release

```sh
[bundle exec] fastlane mac ci_release
```

Archive one edition and ship it (CI)

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
