# AutoMindful 0.1.0 verification

Checked on November 10, 2026 with Linux x86-64 Project Zomboid `42.22.2 3d39148846`, bundled Azul Java `25.0.5+8-LTS`, and official Lifestyle: Hobbies `0.4.0.3`, Workshop item `3403870858`.

## Repeatable checks

The complete archive build and all 13 portable contracts pass. The same contracts pass in the installed game's Kahlua interpreter. The aggregate checks source stability and records the installed upstream source hashes.

The separate progression check loads Lifestyle's actual menu, meditation action, yoga action, hidden-skill manager, and raw perk metadata in place. Both skills reach level 10 under an accelerated action clock, with 1,049 poses, 36 pose failures, and 840 meditation updates. Player, queue, mood application, and the raw-metadata Meditation XP receiver are explicit boundary doubles. This result is not a full native gameplay run.

## Native single-player checks

The final four runtime Lua files match the files loaded by the disposable graphical client. The final archive also matches the archive used by the passing aggregate. The real context menu opens the window, the nearby-supplies preference can be selected, and native actions run through the displayed training controls.

The final sample starts with no food, water, or literature in inventory. The preparation report finds 120 food items, 30 clean-water bottles, and 100 books in the adjacent ground inventory. AutoMindful actually collects water, food, and literature, eats and reads, then enters native meditation and yoga. It completes and repeats training sessions and sleeps when fatigued. Yoga reaches level 2 during this accelerated native sample. No runtime Lua exception occurs in that final sample.

Earlier native checks also exercise Stop, floor sleep and waking, and the current fluid-drinking action. The hydration recheck replaces the legacy bottle action because the installed game's older action refers to a missing thirst packet constant. Game and upstream model-loading warnings remain outside AutoMindful's code and are not represented as a clean whole-game log.

## Native multiplayer checks

An ordinary loopback player with `access=user` opens the real menu and window. Native Meditation XP increases from 0 to 48.75. Boredom triggers a real unread book, followed by resumed meditation. Yoga pose XP increases from 0 to 6 before deliberate cancellation. Stop, the nearby checkbox after Stop, and normal quit and reconnect work.

With native auto-drink disabled through the water item's context menu, AutoMindful's current `ISDrinkFluidAction` completes. Thirst falls from approximately 0.151669 to 0.000971, and meditation resumes. Eating lowers hunger from approximately 0.250529 to 0.101191, followed by resumed meditation.

The server advertises AutoMindful and uses `DoLuaChecksum=false` for this permitted-client test. Every AutoMindful executable file remains under `media/lua/client`. Build 42's native join resets the client's code-mod list to the server's advertised list; an unadvertised client code mod cannot rely on ordinary native loading.

The tested multiplayer Controller, UI, and Main files match the final source. The Supplies module in that run predates the later ground-container and world-fluid fixes, which the final single-player sample verifies. Actual multiplayer ground transfers and a full native multiplayer 0-to-10 run were not tested.

## Scope

A full native, normal-speed single-player or multiplayer 0-to-10 journey was not run. The real-source progression checks and native gameplay samples establish different facts. Windows, macOS, older game builds, Lifestyle forks, and combinations with other automation mods were not tested. The routine requires safe surroundings, a suitable training spot, room for transfers, and adequate provisions. Native server restrictions, missing required mats, injuries, and external disturbances can stop it with a reason.

All graphical checks use owned disposable caches and displays. Multiplayer databases, server caches, clients, servers, and displays are removed after retaining reviewable evidence. The user's running game, mod selections, and saves remain untouched. See [verification](verification.md) for the repeatable commands.
