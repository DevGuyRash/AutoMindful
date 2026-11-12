# Verify AutoMindful

Build the complete mod before running checks. Development commands use Python 3.10 or later and Lua 5.1. The product has no external runtime dependency beyond Project Zomboid and Lifestyle.

## Run portable checks

```sh
python3 tools/verify.py
```

The verification entry point builds the actual archive first, runs controller, supply, context/UI, consumable, world-water, and release-integrity contracts, and records results outside the repository. Portable contracts use explicit game-boundary doubles. They check scheduling, provenance, portions, refresh behavior, and recovery; they do not prove multiplayer acceptance, actual rendering, animations, or a full real-time game journey.

## Check the game's interpreter and upstream source

```sh
python3 tools/verify.py --game /path/to/ProjectZomboid/projectzomboid --lifestyle /path/to/workshop/mods/Lifestyle
```

Use the directory containing `projectzomboid.jar` and `jre64/bin/java` for `--game`. Native checks also need a JDK compiler compatible with the game's Java 25 runtime. Game and Workshop content stay outside the repository and distribution. The report identifies tests that use the installed interpreter and upstream source, including any accelerated clocks or boundary doubles.

Each Lua suite runs in a fresh installed Kahlua environment. The core suite can load Lifestyle's actual menu, action, and hidden-skill Lua. The water suite uses the game's `media` reference root and executes the installed `ISTakeWaterAction.lua`. Character, inventory, world, and network receivers remain explicit boundaries in these checks. Real client journeys are still required for rendering, server round trips, and actual resource movement.

## Exercise a disposable game

On Linux, install Xvfb and run the real client on its own display and cache.

Use a direct Python interpreter for these stateful, long-running checks if your usual `python3` is intercepted by a command cache. Do not replay a game/server launch against the same cache. Always identify the live client and its display from the current `session.json` before driving controls.

```sh
python3 tools/play.py --game /path/to/ProjectZomboid/projectzomboid --lifestyle /path/to/workshop/mods/Lifestyle --evidence /path/to/new/evidence-directory
```

The command prints its display, process IDs, and cache path in `session.json`. It installs a freshly built AutoMindful archive in that cache and creates a disposable hard-link mirror of Lifestyle. Native script discovery fails on a directory symlink in the tested game build, so the mirror preserves the actual installed bytes without adding upstream files to the project. Do not edit files in the mirror. Choose a cache on the same filesystem as the Workshop installation. A normal launch without `--extra-mod` starts at the game's menu. Keep your personal game separate.

For the controlled single-player fixture, add `--extra-mod tests/live/AutoMindfulFixture`. This development mod creates a zombie-free disposable scenario with food, clean water, and books. It uses the permitted sandbox XP settings of 1000 for Meditation and 5 for Yoga. It never ships in the product archive. Start AutoMindful through the actual context menu and controls. Its optional `fast` test command accelerates the world clock; this is a test condition, not an AutoMindful feature or a normal-speed progression measurement.

Fixture commands belong in the disposable cache's `Lua/automindful-fixture-command.txt`. Give repeated commands a distinct suffix, such as `stock 2`, to request another sample. `stock` records current reports and raw provisions. The `nostock`, `cansbags`, `ownedbook`, and `wearable` cases arrange controlled preconditions for missing reserves, separate can/opener sources, carried-bag returns, and a milk-filled canteen. They do not replace native training or consumption actions. Keep successful-return sources below native capacity; use an intentionally full source only to verify the keep-in-inventory notice.

Cover these user journeys before a release:

- Open the world context menu, inspect preparations, start each training mode, cancel, hide the window, reopen it, and inspect the saved nearby-collection preference.
- Check standing and ground-sitting Wellness submenus, the preserved manual action, quick training and supply actions, the active-only reopen entry, optional general entry, and configured shortcut. Inspect tooltips and the full footer at normal and short window heights.
- Move into and out of stock range, transfer items manually, toggle collection during training, and confirm live counts and read-only check feedback. Start with no food or drink and ordinary needs; confirm that genuine critical or native action blockers still stop appropriately.
- Start at zero skill and verify normal Lifestyle yoga and meditation actions, native XP, natural session completion, and automatic resumption.
- Exercise boredom above 30, useful and exhausted literature, food, clean water, endurance, embarrassment, fatigue, sleep, waking, and a missing required mat.
- Enable nearby collection and verify actual transfers from reachable storage. Keep another room and floor inaccessible. Leave manual queued actions intact when cancelling automation.
- Borrow books and opening tools from separate sources. Inspect the original container IDs, returned remainders, identifiable empty containers, full or inaccessible sources, and native recursive carried-bag lookup. Confirm that inventory transfers pause/resume and actual movement shows its cancellation reason.
- Exercise minimal food portions, safe milk in worn canteens, finite ground water, and available plumbing. Check taint, locks, walls, water shutoff, and exhausted sources without bypassing native restrictions.
- Join an owned loopback multiplayer server as an ordinary player. Install Lifestyle on the server and advertise AutoMindful through the server's normal mod list. All AutoMindful runtime Lua remains under `client`. Check training, care, and reconnect.
- Stop all owned clients, servers, and displays. Remove disposable caches and retain only the logs, reports, packages, and screenshots needed to review the result.

## Evidence limits

The tested game is Linux x86-64 Project Zomboid `42.22.2 3d39148846`, bundled Azul Java `25.0.5+8-LTS`, with official Lifestyle: Hobbies `0.4.0.3`, Workshop item `3403870858`. See the [0.1.0 release report](release-0.1.0.md) for completed checks and their limits. A model reaching level 10, an accelerated native run, and a normal-speed multiplayer run establish different facts. No finite run establishes every mod combination or server configuration.
