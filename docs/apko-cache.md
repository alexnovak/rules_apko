# Fetching APK Contents

The `apko_image` rule fetches APK packages and repository indexes from remote sources and provides them to `apko` for building container images. Bazel manages these downloads to ensure correctness and caching.

The `apko.lock.json` file contains all the necessary information about which packages to fetch and from where.

## How It Works

1. **Lock file** (`apko.lock.json`) defines the exact packages, versions, and repository URLs
2. **`translate_lock`** converts the lock file into Bazel repository rules that download the packages
3. **`apko_image`** sets up a local repository structure and invokes `apko build` with:
   - `--build-repository-append` pointing to the local repository (packages available for build, but paths not written to `/etc/apk/repositories`)
   - `--keyring-append` for signing keys
   - `--lockfile` for reproducible builds
   - `--offline` mode since all content is pre-fetched

## Generating the Lock File

> **Note:** Documentation for lockfile generation will be added once the `apko lock` command is available.

## Using `translate_lock`

The `translate_lock` tool takes the `apko.lock.json` file and generates Bazel repositories for all the APK packages, indexes, and keyrings.

`translate_lock` creates a repository with a target named `contents` that you pass to `apko_image`:

```starlark
apko_image(
    name = "lock",
    config = "apko.yaml",
    contents = "@examples_lock//:contents",
    tag = "lock:latest",
)
```

### Usage with bzlmod

```starlark
apk = use_extension("@rules_apko//apko:extensions.bzl", "apko")

apk.translate_lock(
    name = "examples_lock",
    lock = "//path/to/lock:apko.lock.json",
)
use_repo(apk, "examples_lock")
```

### Usage with Workspace

```starlark
load("@rules_apko//apko:translate_lock.bzl", "translate_apko_lock")

translate_apko_lock(
    name = "example_lock",
    lock = "//path/to/lock:apko.lock.json",
)

load("@example_lock//:repositories.bzl", "apko_repositories")

apko_repositories()
```
