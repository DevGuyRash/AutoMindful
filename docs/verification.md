# Verify AutoMindful

Build the complete mod before running checks. Development commands use Python 3.10 or later and Lua 5.1. The product has no external runtime dependency beyond Project Zomboid and Lifestyle.

## Run portable checks

```sh
python3 tools/verify.py
```

The verification entry point builds the actual archive first, runs controller, supply, context/UI, consumable, world-water, fluid-transfer, and release-integrity contracts, and records results outside the repository. Portable contracts use explicit game-boundary doubles. They check scheduling, provenance, portions, refresh behavior, recovery, and terminal HUD card selection and progress; they do not prove multiplayer acceptance, actual rendering, animations, or a full real-time game journey.

For cooperative training, the contracts track Lua and native action identities separately. They exercise ordinary queued actions, map-reading windows with an empty queue, a chair-to-floor transition, interrupted scout trips, spent supplies, quiet intervals and hard stops. The endurance suite includes full and nearly full values, long workouts, skill-cap meditation without XP, preparation before meditation actually starts, missing stats, and stopped recovery.

For gameplay acceptance use a disposable survivor, not a personal save. Start both yoga and meditation separately; insert a workout, open and close a world and paper map, and verify the same mode resumes after each without a stop card. Check an occupied chair is left only after existing actions finish. Start endurance meditation below full, inspect the unchanged native stat during recovery, and confirm one completion at actual full. Verify genuine aiming, travel, danger and explicit Stop still terminate while waiting.

## Check the game's interpreter and upstream source

```sh
python3 tools/verify.py --game /path/to/ProjectZomboid/projectzomboid --lifestyle /path/to/workshop/mods/Lifestyle
```

Use the directory containing `projectzomboid.jar` and `jre64/bin/java` for `--game`. Native checks also need a JDK compiler compatible with the game's Java 25 runtime. Game and Workshop content stay outside the repository and distribution. The report identifies tests that use the installed interpreter and upstream source, including any accelerated clocks or boundary doubles.

Supplying the game also runs `tests/stock_queue.lua` against its unmodified queue and base action Lua. The Java character stack in that check is a double; this distinguishes stock Lua handoff behavior from an in-game playtest.

Each Lua suite runs in a fresh installed Kahlua environment. The core suite can load Lifestyle's actual menu, action, and hidden-skill Lua. The water and fluid-transfer suites use the game's `media` reference root and execute the installed `ISTakeWaterAction.lua` and native fluid wrappers and transfer action respectively. Character, inventory, world, fluid storage, and network receivers remain explicit boundaries in these checks. Real client journeys are still required for rendering, server round trips, and actual resource movement.

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
- With the AutoMindful window closed, stop a session and reach a level cap in a separate run. Each should show one noninteractive card in the correct player's viewport, with a stop reason or completion, elapsed time, and observed XP or levels. Check that clicks still reach the game and the card fades. Confirm that drinking, scouting, inventory pauses, and loan returns do not add another card.
- Exercise boredom above 30, useful and exhausted literature, food, clean water, endurance, embarrassment, fatigue, sleep, waking, and a missing required mat.
- Enable nearby collection and verify actual transfers from reachable storage. Keep another room and floor inaccessible. Leave manual queued actions intact when cancelling automation.
- Borrow books and opening tools from separate sources. Inspect the original container IDs, returned remainders, identifiable empty containers, full or inaccessible sources, and native recursive carried-bag lookup. Confirm that inventory transfers pause/resume and actual movement shows its cancellation reason.
- Exercise minimal food portions, safe milk in worn canteens, finite ground water, and available plumbing. Check taint, locks, walls, water shutoff, and exhausted sources without bypassing native restrictions.
- Exercise owned and borrowed bulk milk or water with a separate empty drinking vessel. Confirm measured native pouring, drinking, resumption, and each container's return origin. Cover a vessel in a carried bag, a world-owned source, no empty vessel, a prefilled vessel, incompatible filters, unsafe mixtures, contamination between pour and drink, and movement during a partial pour. Preserve partial or unsafe contents.
- With the singleplayer fixture loaded, send `scoutcase book` in an open, lit area. It places an eligible book six tiles away and starts meditation at 40 boredom. Verify the native walk, reading, returned book, and active meditation back on the original square. In a fresh case, send `scoutcase fast-empty`. It seeds an unexplored empty bag and switches to speed 4 during inspection. Verify the `SCOUTCASE` fast-forward marker and the return at normal speed, then active meditation at the origin. A precondition message means the scenario did not run; use a clear area without competing supplies.
- Exercise separate food and water fixtures, an inaccessible outbound source, a blocked return, manual movement, Stop, danger, and toggling scouting off during travel. A genuine blocked return stops without training elsewhere. Keep this in a disposable cache; portable walking doubles are not gameplay evidence.
- Verify the radius report counts observed container contents beyond adjacency, labels unknown/unconfirmed containers, and never moves or generates distant loot on Check supplies. Exercise a delayed multiplayer contents response, an empty response, a timeout and retry cooldown, an adjacent unknown container requiring no walk, option disable during inspection, and a changed radius. Known-source lookup and preview must share one cached snapshot.
- Join an owned loopback multiplayer server as an ordinary player. Install Lifestyle on the server and advertise AutoMindful through the server's normal mod list. All AutoMindful runtime Lua remains under `client`. Check training, care, and reconnect.
- Stop all owned clients, servers, and displays. Remove disposable caches and retain only the logs, reports, packages, and screenshots needed to review the result.

## Evidence limits

The tested game is Linux x86-64 Project Zomboid `42.22.2 3d39148846`, bundled Azul Java `25.0.5+8-LTS`, with official Lifestyle: Hobbies `0.4.0.3`, Workshop item `3403870858`. See the [0.1.0 release report](release-0.1.0.md) for completed checks and their limits. A model reaching level 10, an accelerated native run, and a normal-speed multiplayer run establish different facts. No finite run establishes every mod combination or server configuration.

## Vehicle and corpse radius storage

The radius suite includes direct corpse contents, duplicate-body/vehicle suppression, animal/fake-dead/reanimation exclusions, safehouse restrictions, native exterior door requirements, stationary storage, area-based radius bounds, unknown multiplayer contents, and unsupported-layout rejection. Controller contracts cover native vehicle-area walking, manual movement discrimination, late native-access denial, loan return before home, moving/repositioned vehicle cancellation, and queued transfer revalidation. These use explicit world/pathfinding doubles; they are not live multiplayer/pathfinding acceptance.

Implementation was checked against the installed Build 42 `ISInventoryPage.refreshBackpacks`, `Vehicles.lua` container access predicates and `ISPathFindAction`. Native container access remains authoritative at arrival. Script container `luaTest` metadata is not exposed to Lua, so distant structural discovery conservatively recognizes standard storage part IDs rather than inventing access to arbitrary modded parts. No door opening, unlocking, entry, network request or loot-generation call is made by radius discovery. Unknown contents are populated only through the existing native adjacent loot refresh.
