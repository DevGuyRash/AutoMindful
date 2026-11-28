# Publish AutoMindful releases to Steam Workshop

AutoMindful's release workflow builds and checks versioned GitHub assets. Workshop uploads are explicit foreground commands or manual runs of the shared [Steam Workshop publisher](https://github.com/DevGuyRash/steam-workshop-publisher). The former desktop service and dedicated GitHub runner have been removed. No background local publisher is required.

Follow the publisher's [agent quickstart](https://github.com/DevGuyRash/steam-workshop-publisher/blob/main/docs/agent-quickstart.md) for local uploads, its [desktop guide](https://github.com/DevGuyRash/steam-workshop-publisher/blob/main/docs/desktop.md) for current-session requirements, and its [generic setup guide](https://github.com/DevGuyRash/steam-workshop-publisher/blob/main/docs/setup.md) for release or cloud setup. Those guides own the reusable procedure. `AGENTS.md` links this file as AutoMindful's publishing entrypoint.

Local candidates can be built and tested without creating a release tag, publishing a GitHub release, or uploading to Workshop. Complete local acceptance before those publication steps. The shared publisher now reuses the signed-in desktop Steam client for local uploads. Pass `--backend desktop` explicitly so an inherited environment setting cannot select another backend. Cloud publishing and an explicitly selected SteamCMD backend still use a separate login, which can replace another Steam session on the same account.

## Build a release

1. Set `modversion` in `mods/AutoMindful/42/mod.info` to the next stable version. This file is the authoritative package version.
2. Merge the change to `main` after checks pass.
3. Publish a GitHub release with a matching tag such as `v0.1.2`, pointing to that commit on `main`.
4. Wait for **Build release assets** to pass. It verifies tagged source and main-branch ancestry, runs the portable checks, and attaches `AutoMindful-<version>.zip`, `manifest.json`, and `release-notes.txt` to that release.

The build uses release assets and does not require Actions artifact storage. A release builds its assets without automatically changing Steam Workshop. Manual build runs default to validation. Enable their upload option only to attach checked assets to the latest stable GitHub release. Drafts, prereleases, mismatched versions, and source outside `main` cannot publish release assets through this workflow.

Repeated local builds stage the ZIP and manifest before replacing existing artifacts. Handled write failures preserve the previous pair; if restoration itself fails, the error identifies retained recovery backups. Keep those backups until recovery is complete. This is not an atomic two-file publication across host crashes or concurrent builders; do not run builds against the same output directory simultaneously.

## Request a Workshop upload

From the shared publisher checkout, validate the latest built release, then request the upload locally or on GitHub.

```sh
python3 local.py DevGuyRash/SecondNature v0.1.2
python3 desktop.py probe --app-id 108600
python3 local.py DevGuyRash/SecondNature v0.1.2 --publish --backend desktop
```

The listing text lives in [workshop/description.txt](../workshop/description.txt) (Steam BBCode). Uploads keep the current description unless `--description-file` is given, so add `--description-file /path/to/AutoMindful/workshop/description.txt` to the publish command when it changes.

Local release commands reuse the existing GitHub CLI login, and the upload uses the current desktop Steam session. No Steam password or Steam Guard prompt is needed. If the desktop probe fails, resolve the condition in Steam; do not silently switch to SteamCMD. The command runs in the foreground and installs no service. For a packaged local folder, the publisher also supports validation and upload through `folder.py` as described in its agent quickstart.

To use GitHub instead, configure the shared publisher once using `just setup-github --source DevGuyRash/SecondNature`. That separate cloud path uses SteamCMD authentication and cannot reuse this machine's desktop session. Then run these commands.

```sh
just github DevGuyRash/SecondNature v0.1.2
just github-publish DevGuyRash/SecondNature v0.1.2
```

The first command requests cloud validation. The second requests an upload. You can make the same choices under **Actions > Publish Workshop item > Run workflow** in the publisher repository. Follow the dispatched run to completion. With cloud authentication configured, this desktop can be off. Standard hosted jobs in the public publisher repository do not consume your private Actions minutes. AutoMindful is public, so its standard GitHub-hosted release build also avoids private Actions minutes. No extra GitHub token is needed to download its public releases.

## Keep the existing item

Second Nature's own [workshop-publisher.json](../workshop-publisher.json) maps mod ID `SecondNature` to existing Workshop item [`3837554362`](https://steamcommunity.com/sharedfiles/filedetails/?id=3837554362), under Project Zomboid application ID `108600`. Routine updates preserve the title, description, tags, visibility, and required items. Do not create a replacement item to repair an upload or authentication failure.

Since 0.4.0 (Second Nature) [Lifestyle: Hobbies](https://steamcommunity.com/sharedfiles/filedetails/?id=3403870858) is optional: Autopilot works without it, and Yoga and Meditation need it. Routine updates keep the listing's required items, so remove Lifestyle from the item's required items on Steam once when publishing 0.4.0 or later. The packaged executable files remain under `media/lua/client`. Once the mod is loaded on the client, it does not require a server-side component. With Lifestyle, its requirements and host rules still apply.

## Legacy game-based desktop uploader

Prefer the shared publisher above; its desktop backend needs no installed game or JDK. The original native uploader remains available as an explicit fallback. It needs the installed game, JDK 25, and Steam signed into the owning account. It does not install or start a service.

```sh
python3 tools/workshop.py stage --archive /path/to/AutoMindful-0.1.2.zip --manifest /path/to/manifest.json --tag v0.1.2 --notes-file /path/to/release-notes.txt --out /path/to/new/workshop-stage
python3 tools/publish_desktop.py --game /path/to/ProjectZomboid/projectzomboid --stage /path/to/new/workshop-stage --item-id 3837554362
```

Staging checks package bytes against the tagged checkout and manifest before the native uploader calls Steam. The shared publisher validates the source repository's published release assets without executing its code and can upload through desktop Steam or explicitly selected SteamCMD. Every path updates the same existing item.

## Replace the Workshop logo

The selected logo master is [workshop/logo.png](../workshop/logo.png), and its generated prompt record is [workshop/logo-prompt.md](../workshop/logo-prompt.md). The listing uses [workshop/preview.png](../workshop/preview.png), a 256 × 256 PNG validated by `tools/workshop.py`.

The shared publisher preserves the existing listing preview during ordinary content uploads. For an intentional logo replacement, stage the current released content with the new preview, then use the game-based desktop uploader above. Its update path sets content, preview, and change notes while preserving the existing item, title, description, visibility, tags, and required items. This uses the signed-in desktop Steam session and does not start SteamCMD or a separate login. Copy the validated preview to the local Workshop staging folder as well.

## Mod IDs

Since 0.7.0 the mod ID is `SecondNature`, and the package (`SecondNature-<version>.zip`) carries the same files a second time under the legacy ID `AutoMindful`, built by `tools/build.py` from the one source folder `mods/SecondNature`, with a `mod.info` that names it *Second Nature (legacy ID: only for saves made before 0.7.0)*. Saves and servers from before 0.7.0 keep working with the legacy ID and get a one-time notice on how to switch (`ModIdentity.lua`). Both copies share the internal Lua paths (`AutoMindful/...`), the settings key and the log folder, so enabling both loads each file once and nothing is lost. Drop the legacy copy only in a later release, after announcing it.
