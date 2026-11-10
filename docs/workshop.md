# Publish versioned releases to Steam Workshop

The release workflow builds and checks a versioned GitHub release, attaches its ZIP and SHA256 manifest, and updates AutoMindful's existing Steam Workshop item. Publishing updates content and change notes while preserving the Workshop page's title, description, tags, and visibility.

## Publishing host

The cloud job builds and checks the release. A dedicated repository-scoped runner on the publishing machine uploads it through the already-signed-in desktop Steam client. No Steam password, two-factor seed, or Steam login file is copied into GitHub. The runner uses the `automindful-publisher` label.

Configure these non-secret repository variables under **Settings > Secrets and variables > Actions**:

| Variable | Value |
| --- | --- |
| `STEAM_WORKSHOP_ID` | AutoMindful's positive numeric existing Workshop item ID. The configured item is `3837554362`. |
| `PZ_GAME_DIR` | The publishing host's installed game directory containing `projectzomboid.jar`, `jre64/bin/java`, and `natives`. |

The native publisher needs Linux x86-64, a JDK 25 `javac`, and Steam signed in to the account owning the item. It reads the installed game's libraries in place and uses a disposable cache for its own process. It does not launch a game session, read Steam credential files, or change the running game's cache. A versioned release authorizes the upload; no game confirmation dialog is used.

The normal workflow updates one existing item and never creates another. The local initial bootstrap records the assigned ID before uploading and refuses another creation when an ID or an unresolved creation request already exists. Game libraries are never packaged into the repository or release.

The publishing host must be online. If the runner is offline, GitHub queues the publishing job until it is available. If Steam is signed out, sign in through Steam's normal UI and retry the latest release. Authentication prompts stay in Steam.

## Manage the runner

The publishing runner is installed under `~/.local/share/automindful-release-runner` and runs as the user service `automindful-workshop-runner.service`. It starts with the user session and reconnects to GitHub automatically. Its normal GitHub runner registration files stay in that local application directory; do not copy them into the repository or release artifacts.

To replace the publishing host, register a repository-scoped Linux x86-64 runner through **Settings > Actions > Runners**, give it the `automindful-publisher` label, and run the official runner's `run.sh` as that user's service. Install the game and JDK on that host, sign in through desktop Steam, and update `PZ_GAME_DIR`. Keep the same Workshop item ID. Disable the old user service when retiring its host.

```sh
systemctl --user status automindful-workshop-runner.service
systemctl --user restart automindful-workshop-runner.service
systemctl --user disable --now automindful-workshop-runner.service
```

## Publish a version

1. Change `modversion` in `mods/AutoMindful/42/mod.info` to the next stable version, such as `0.1.1`. This is the package version's authoritative source.
2. Merge the change to `main` after checks pass.
3. Create and publish a GitHub release with the matching tag, such as `v0.1.1`, pointing to that commit on `main`.
4. Wait for the **Release to Steam Workshop** workflow. It verifies the exact tagged source, stages the tested archive, attaches the package and manifest to the GitHub release, and sends that immutable artifact to the dedicated publishing runner. The runner checks out the verified source SHA, validates the artifact again, and updates the configured Workshop item.

Draft releases and prereleases do not publish to Steam. Version mismatches, missing authentication, an invalid Workshop ID, a release outside `main`, or a failed check stop publication with an error. Uploads are serialized so two releases cannot change the item concurrently. Routine updates preserve the item's existing visibility. Make a hidden initial item public through its Workshop page when it is ready.

## Validate or retry

Use **Actions > Release to Steam Workshop > Run workflow** with a version tag to validate and stage a package. Manual runs default to a dry run and do not use the native publisher. Enable publishing only to retry the latest stable published release. An older release cannot silently replace a newer release through the retry path.

The staging command can also be exercised locally without Steam credentials:

```sh
python3 tools/workshop.py stage --archive /path/to/AutoMindful-0.1.1.zip --manifest /path/to/manifest.json --tag v0.1.1 --out /path/to/new/workshop-stage
```

It accepts the archive and manifest from the passing build. It verifies their hashes, release version, allowed files, and client-only runtime before constructing the Workshop upload folder. The uploader sends only its `Contents` directory and preview image.

The native uploader can be exercised directly on the publishing host:

```sh
python3 tools/publish_desktop.py --game /path/to/ProjectZomboid/projectzomboid --stage /path/to/checked/workshop-stage --item-id 3837554362
```

For a publication failure, check the job's error and the Steam client's sign-in state, then rerun the failed publishing job or use the manual retry for the same latest release. Preserve `STEAM_WORKSHOP_ID`; do not create a replacement item to repair authentication. The staging folder is checked against the release source and its manifest before the Steam API is called.


## Initial item and runtime requirements

AutoMindful uses Project Zomboid's Workshop application ID `108600` and mod ID `AutoMindful`. Initial listing setup adds the official [Lifestyle: Hobbies](https://steamcommunity.com/sharedfiles/filedetails/?id=3403870858) item as a required item and makes the listing public after verification. That one-time setup uses `SteamWorkshopBootstrap`'s explicit `publish-listing` mode. Ordinary releases use its content-only `update` mode and preserve the existing listing settings.

All AutoMindful executable mod files remain under `media/lua/client`; the publishing tools and game libraries are not included in the mod archive. Normal Build 42 multiplayer loading still requires the server to advertise the mod.
