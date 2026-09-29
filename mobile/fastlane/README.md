fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## Android

### android verify

```sh
[bundle exec] fastlane android verify
```

Validate that the Play service account can reach the app

### android build

```sh
[bundle exec] fastlane android build
```

Build a signed Android App Bundle without uploading it

### android beta

```sh
[bundle exec] fastlane android beta
```

Build and upload a new Robine Wake release to a Google Play track (internal by default)

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
