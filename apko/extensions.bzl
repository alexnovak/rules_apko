"""Extensions for bzlmod.

Installs a apko toolchain.
Every module can define a toolchain version under the default name, "apko".
The latest of those versions will be selected (the rest discarded),
and will always be registered by rules_apko.

Additionally, the root module can define arbitrarily many more toolchain versions under different
names (the latest version will be picked for each name) and can register them as it sees fit,
effectively overriding the default named toolchain due to toolchain resolution precedence.
"""

load("//apko/private:apk.bzl", "apk_import", "apk_keyring", "apk_repository")
load("//apko/private:util.bzl", "util")
load(":repositories.bzl", "apko_register_toolchains")
load(":translate_lock.bzl", "translate_apko_lock")

_DEFAULT_NAME = "apko"

apko_toolchain = tag_class(attrs = {
    "name": attr.string(doc = """\
Base name for generated repositories, allowing more than one apko toolchain to be registered.
Overriding the default is only permitted in the root module.
""", default = _DEFAULT_NAME),
    "apko_version": attr.string(doc = "Explicit version of apko.", mandatory = True),
})

apko_translate_lock = tag_class(attrs = {
    "name": attr.string(mandatory = True),
    "lock": attr.label(mandatory = True),
})

def _apko_extension_impl(module_ctx):
    root_direct_deps = []
    root_direct_dev_deps = []
    registrations = {}

    # Deduplication dictionaries keyed by URL
    all_keyrings = {}  # url -> keyring dict
    all_repositories = {}  # url -> repository dict
    all_packages = {}  # url -> package dict

    # Track which URLs each lock needs (for creating mappings)
    lock_keyrings = {}  # lock_name -> [urls]
    lock_repositories = {}  # lock_name -> [urls]
    lock_packages = {}  # lock_name -> [urls]

    # Also track lock metadata for Pass 3
    lock_metadata = {}  # lock_name -> {mod, lock, is_dev}

    # Pass 1: Collect all resources from all locks, deduplicating by URL
    for mod in module_ctx.modules:
        for lock in mod.tags.translate_lock:
            lock_file = util.parse_lock(module_ctx.read(lock.lock))

            if not "contents" in lock_file:
                continue

            lock_keyrings[lock.name] = []
            lock_repositories[lock.name] = []
            lock_packages[lock.name] = []
            lock_metadata[lock.name] = {
                "mod": mod,
                "lock": lock,
                "is_dev": module_ctx.is_dev_dependency(lock),
            }

            # Collect keyrings (deduplicate by URL)
            if "keyring" in lock_file["contents"]:
                for keyring in lock_file["contents"]["keyring"]:
                    all_keyrings[keyring["url"]] = keyring
                    lock_keyrings[lock.name].append(keyring["url"])

            # Collect repositories (deduplicate by URL)
            for repository in lock_file["contents"]["repositories"]:
                all_repositories[repository["url"]] = repository
                lock_repositories[lock.name].append(repository["url"])

            # Collect packages (deduplicate by URL)
            for package in lock_file["contents"]["packages"]:
                all_packages[package["url"]] = package
                lock_packages[lock.name].append(package["url"])

    # Pass 2: Create shared repository rules (one per unique URL)
    for url, keyring in all_keyrings.items():
        apk_keyring(
            name = util.apk_keyring_repo_name(keyring),
            url = keyring["url"],
        )

    for url, repository in all_repositories.items():
        apk_repository(
            name = util.apk_index_repo_name(repository),
            url = repository["url"],
            architecture = repository["architecture"],
        )

    for url, package in all_packages.items():
        apk_import(
            name = util.apk_repo_name(package),
            package_name = package["name"],
            version = package["version"],
            architecture = package["architecture"],
            url = package["url"],
            signature_range = package["signature"]["range"],
            signature_checksum = package["signature"]["checksum"],
            control_range = package["control"]["range"],
            control_checksum = package["control"]["checksum"],
            data_range = package["data"]["range"],
            data_checksum = package["data"]["checksum"],
        )

    # Pass 3: Create lock-specific translate_apko_lock repos with URL -> repo name mappings
    for lock_name, metadata in lock_metadata.items():
        lock = metadata["lock"]
        mod = metadata["mod"]

        # Build URL -> shared repo name mappings for this lock
        package_repos = {url: util.apk_repo_name(all_packages[url]) for url in lock_packages[lock_name]}
        index_repos = {url: util.apk_index_repo_name(all_repositories[url]) for url in lock_repositories[lock_name]}
        keyring_repos = {url: util.apk_keyring_repo_name(all_keyrings[url]) for url in lock_keyrings[lock_name]}

        translate_apko_lock(
            name = lock.name,
            target_name = lock.name,
            lock = lock.lock,
            package_repos = json.encode(package_repos),
            index_repos = json.encode(index_repos),
            keyring_repos = json.encode(keyring_repos),
        )

        if mod.is_root:
            deps = root_direct_dev_deps if metadata["is_dev"] else root_direct_deps
            deps.append(lock.name)

    for mod in module_ctx.modules:
        for toolchain in mod.tags.toolchain:
            if toolchain.name != _DEFAULT_NAME and not mod.is_root:
                fail("""\
                Only the root module may override the default name for the apko toolchain.
                This prevents conflicting registrations in the global namespace of external repos.
                """)
            if toolchain.name not in registrations.keys():
                registrations[toolchain.name] = []

                if mod.is_root:
                    deps = root_direct_dev_deps if module_ctx.is_dev_dependency(toolchain) else root_direct_deps
                    deps.append(toolchain.name + "_toolchains")

            registrations[toolchain.name].append(toolchain.apko_version)

    for name, versions in registrations.items():
        if len(versions) > 1:
            # TODO: should be semver-aware, using MVS
            selected = sorted(versions, reverse = True)[0]

            # buildifier: disable=print
            print("NOTE: apko toolchain {} has multiple versions {}, selected {}".format(name, versions, selected))
        else:
            selected = versions[0]

        apko_register_toolchains(
            name = name,
            apko_version = selected,
            register = False,
        )

    # Allow use_repo calls to be automatically managed by `bazel mod tidy`
    return module_ctx.extension_metadata(
        root_module_direct_deps = root_direct_deps,
        root_module_direct_dev_deps = root_direct_dev_deps,
    )

apko = module_extension(
    implementation = _apko_extension_impl,
    tag_classes = {
        "toolchain": apko_toolchain,
        "translate_lock": apko_translate_lock,
    },
)
