# Verify AutoMindful

Build the complete mod before running checks. Development commands use Python 3.10 or later and Lua 5.1. The product has no external runtime dependency beyond Project Zomboid and Lifestyle.

## Run portable checks

```sh
python3 tools/verify.py
```

The verification entry point builds the actual archive first, runs the controller and supply contracts, and records its results outside the repository. Portable contracts use explicit game-boundary doubles. They check scheduling and recovery behavior; they do not prove multiplayer acceptance, actual animations, or a full real-time game journey.

## Check the game's interpreter and upstream source

```sh
python3 tools/verify.py --game /path/to/ProjectZomboid/projectzomboid --lifestyle /path/to/workshop/mods/Lifestyle
```

Use the directory containing `projectzomboid.jar` and `jre64/bin/java` for `--game`. Native checks also need a JDK compiler compatible with the game's Java 25 runtime. Game and Workshop content stay outside the repository and distribution. The report identifies tests that use the installed interpreter and upstream source, including any accelerated clocks or boundary doubles.

## Exercise a disposable game

On Linux, install Xvfb and run the real client on its own display and cache.

```sh
python3 tools/play.py --game /path/to/ProjectZomboid/projectzomboid --lifestyle /path/to/workshop/mods/Lifestyle --evidence /path/to/new/evidence-directory
```

The command prints its display, process IDs, and cache path in `session.json`. It installs a freshly built AutoMindful archive in that cache and creates a disposable hard-link mirror of Lifestyle. Native script discovery fails on a directory symlink in the tested game build, so the mirror preserves the actual installed bytes without adding upstream files to the project. Do not edit files in the mirror. Choose a cache on the same filesystem as the Workshop installation. A normal launch without `--extra-mod` starts at the game's menu. Keep your personal game separate.

For the controlled single-player fixture, add `--extra-mod tests/live/AutoMindfulFixture`. This development mod creates a zombie-free disposable scenario with food, clean water, and books. It uses the permitted sandbox XP settings of 1000 for Meditation and 5 for Yoga. It never ships in the product archive. Start AutoMindful through the actual context menu and controls. Its optional `fast` test command accelerates the world clock; this is a test condition, not an AutoMindful feature or a normal-speed progression measurement.

Cover these user journeys before a release:

- Open the world context menu, inspect preparations, start each training mode, cancel, hide the window, reopen it, and inspect the saved nearby-collection preference.
- Start at zero skill and verify normal Lifestyle yoga and meditation actions, native XP, natural session completion, and automatic resumption.
- Exercise boredom above 30, useful and exhausted literature, food, clean water, endurance, embarrassment, fatigue, sleep, waking, and a missing required mat.
- Enable nearby collection and verify actual transfers from reachable storage. Keep another room and floor inaccessible. Leave manual queued actions intact when cancelling automation.
- Join an owned loopback multiplayer server as an ordinary player. Install Lifestyle on the server and advertise AutoMindful through the server's normal mod list. All AutoMindful runtime Lua remains under `client`. Check training, care, and reconnect.
- Stop all owned clients, servers, and displays. Remove disposable caches and retain only the logs, reports, packages, and screenshots needed to review the result.

## Evidence limits

The tested game is Linux x86-64 Project Zomboid `42.22.2 3d39148846`, bundled Azul Java `25.0.5+8-LTS`, with official Lifestyle: Hobbies `0.4.0.3`, Workshop item `3403870858`. See the release report for completed checks and their evidence paths. A model reaching level 10, an accelerated native run, and a normal-speed multiplayer run establish different facts. No finite run establishes every mod combination or server configuration.
