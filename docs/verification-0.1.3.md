# 0.1.3 verification

Version 0.1.3 adds safe bulk-fluid supplies, measured native transfers into empty drinking vessels, and separate return records for the source and vessel. It remains a local test candidate. No release tag or Workshop upload is part of this update.

The package contains ten client Lua files and no server implementation. It uses the installed game's fluid wrappers, transfer action, drinking action, and inventory actions. The [supply policy](supplies.md) describes source selection and mixture safety.

## Automated checks

The complete package was built before new tests were written. All 16 checks passed against Project Zomboid 42.22.2 and Lifestyle 0.4.0.3 with a stable source fingerprint. The eight checks without installed references also passed, matching the public CI command. The controller suite has 45 cases. Dedicated supply, consumable, world-water, and fluid-transfer suites cover the new boundaries.

The controller cases check separate nearby origins, carried-bag vessels with nearby collection disabled, preservation of existing drinks, contamination before and after pouring, movement during a partial pour, and native automatic drinking before controller confirmation. The fluid suite rejects diluted harmful constituents even when combined properties omit sickness effects. It also checks sample release, native constructor references, measured volumes, capacity, transfer filters, changing reachability, and partially filled recipients.

Installed Kahlua checks execute real native and Lifestyle Lua with explicit character, inventory, fluid-storage, and network receiver doubles. They supplement the following client journeys and do not establish native multiplayer behavior by themselves.

## Native single-player checks

The native client used a private display, disposable cache, and the development fixture. Fixture commands arranged starting resources and needs. Native actions performed collection, pouring, drinking, returns, and training.

| Journey | Observed result |
| --- | --- |
| Milk and vessel in separate ground bags | About 0.4102 L moved from the 5 L milk bucket into the empty bottle and was drunk. Both exact item IDs returned to their distinct original bag IDs. Pending returns reached zero and meditation resumed. |
| Milk bucket on the ground | About 0.4 L moved into the bottle. The bucket retained its exact world object throughout. Drinking completed and meditation resumed. |
| Tainted mixture | A mixture of 4.999 L milk and 0.001 L tainted water was rejected as a supply. No transfer was selected. |
| Target contaminated during pouring | After about 0.0463 L milk entered the vessel, the fixture added 0.001 L tainted water. Further pouring stopped. The exact vessel returned with its unsafe contents preserved. No drink occurred. |
| Movement during a partial pour | Actual directional movement cancelled the loop with its reason. Both exact items returned to their original bags. The source retained about 4.548 L and the vessel retained about 0.452 L, preserving the original 5 L total. No drink occurred. |
| Healthy milk and water mixture | About 0.4014 L was transferred and drunk. The world source stayed in place and meditation resumed. |
| Missing or nonempty vessel | No pour occurred and existing contents stayed unchanged. Noncritical training remained available. |
| Owned containers and multiple empty vessels | Native care completed and meditation resumed. Multiple possible recipients counted as one supply source. |

Those native actions used the final controller and fluid implementation. Later report-only adjustments removed a false missing-vessel warning when a compatible empty vessel was already available and a duplicate warning shared by food and hydration. Full portable and installed-interpreter checks cover those adjustments.

## Native multiplayer checks

An ordinary `access=user` client joined an owned loopback server that advertised Lifestyle, AutoMindful, and the client-only development fixture. Lua checksum enforcement was disabled. The server granted real inventory item IDs before the fixture arranged fluid contents and starting needs. No AutoMindful server implementation supplied the action effects.

With owned source and vessel, native server transfers moved about 0.02523 L milk for the small remaining thirst, then about 0.39966 L for hunger. The 5 L source retained about 4.57511 L, the drinking vessel emptied, meditation resumed, and native Meditation XP increased. This follows the common policy of satisfying the first need before reassessing the remaining one. It was not a repeated failed-pour loop.

Native `ISFluidTransferAction:update` does not change fluid amounts on a client. The observed source and target changes followed the server's reconstructed native action and synchronization, establishing the server round trip. Fixture attempts with client-created, server-unknown item IDs produced setup errors before this successful path; those earlier errors are retained and distinguished in the evidence.

A fresh ordinary-client session used the exact final runtime package and an empty vessel inside a carried schoolbag. The fixture placed server-granted items into the bag through a native inventory transfer. AutoMindful collected the vessel, requested 0.50856 L milk, drank it, and returned the same empty vessel ID to the same bag ID. The source retained about 4.49144 L. Pending returns reached zero, meditation resumed, and native Meditation XP increased. Starter food was consumed before this pour, so the requested amount matched the remaining hunger of about 0.25428.

## Evidence and limits

Evidence is retained outside Git under `${XDG_STATE_HOME:-$HOME/.local/state}/app-verification/automindful/fluid-transfers/`. The complete check report is `final-checks-r2/report.json`; the CI-equivalent report is `final-portable/report.json`. Native single-player evidence is under `sp-native-r2/`; multiplayer paths are under `mp-client-r2/` and `mp-client-r3/`.

All owned native clients, servers, displays, and disposable caches were removed after verification. Selected reports, logs, screenshots, package hashes, and the installation receipt remain outside Git. The user's running game, saves, settings, and Steam sign-in were not changed.

The native game still owns transfer filters, capacity, action completion, and multiplayer acceptance. Safety checks do not make unsafe fluids healthy. Existing drinks are never discarded to create a recipient. The controller checks the filled vessel before queuing the native drink; a server or another mod can still change state during an action. This update does not establish every mod combination or a normal-speed level 0–10 journey.
