# 0.1.2 candidate verification

This report covers the unpublished local-test candidate. Publication is held for the user's local acceptance. Committing and pushing the candidate does not create a release tag, GitHub release, or Workshop upload.

The runtime contains eight client Lua modules, native Build 42 Mod Options, and the required `LifestyleHobbies` dependency. It adds no server code and does not award XP, change native skill thresholds, or copy upstream training actions.

## Automated checks

The verification entry point builds the complete versioned archive before running the portable controller/supply, UI/context, consumable, water-source, and release-integrity suites. It also compiles the native Java helpers and runs each Lua suite in a fresh installed Kahlua environment. With installed references, the core suite exercises real Lifestyle Lua and the water suite exercises real `ISTakeWaterAction.lua`; game and network receivers remain explicit boundary doubles.

Important regressions include native-recursive carried-bag lookup, completion of returned loans, transfers from the actual current container, hunger-based portions without an extra calorie reserve, empty reserve starts, native critical need stops, oldest eligible rereads, separate opening-tool sources, and native source positions for ground bags without `SourceGrid`.

## Native single-player checks

The native client ran with a disposable cache and the optional verification fixture. Real controls started the actions. The fixture arranged resources and needs; it did not replace the training, opening, eating, drinking, or transfer effects.

| Journey | Observed result |
| --- | --- |
| Context access | Wellness's Yoga submenu opened the window and retained the manual action. Parent tooltips did not obscure commands. |
| Window layout | Framed status, skill bars, supply ledger, controls, and both footer lines rendered. |
| Empty reserves | Meditation started with zero food and water at ordinary hunger/thirst and continued. |
| Live values | Inventory additions, returned food, and walking outside stock range updated the view without checking or reopening. Stored, fresh, and rendered counts matched. |
| Hidden-window care | Book collection, reading, return, and meditation resumption worked while the window was hidden. |
| Carried-bag return | The read book was back in its original carried bag, pending returns reached zero, and meditation resumed. |
| Separate can and opener sources | A can and opener came from different ground bags. The opener and remaining food returned to their distinct source container IDs. |
| Food portion and empty container | The first bite left about `0.0687` of the can's original `0.24` hunger relief. Finishing it returned the new empty tin to the original food bag. |
| Worn milk canteen | A worn canteen containing `0.9 L` retained about `0.3525 L` after restoring the current needs. It stayed worn. |
| Ground water | A `5 L` bucket remained on the ground, retained about `4.4985 L`, and drinking was followed by meditation. No owned vessel was needed. |
| Real plumbing | An actual map sink supplied water with no portable hydration inventory, followed by meditation. Three nearby bathroom water points were discovered. |
| Manual movement | W movement cancelled the loop and displayed the local red overhead reason. |

An initially overloaded test floor correctly prevented a return. The item stayed in inventory with a notice. Successful return checks were repeated with stock below the native floor limit. A suspected stale view was rechecked with exact UI and controller telemetry in a controlled native process and did not reproduce.

## Native multiplayer checks

An owned loopback server advertised Lifestyle, AutoMindful, and the client-only test fixture. The survivor had ordinary `access=user`; Lua checksum enforcement was disabled in this test environment.

Native meditation progressed from level 0 to 2 across the sample, survived window hiding, and retained progress across reconnection without automatically restarting. A nearby book was collected, read, returned to its original floor square, and meditation resumed while the window stayed hidden. Checking supplies and collection toggles did not cancel training. Manual inventory transfers paused and resumed it; walking cancelled with the visible overhead reason.

A milk carton retained `0.49 / 1 L` after the hydration care break. Nearby world-water drinking also worked with zero hydration items in inventory, followed by meditation. A fresh start with no permitted food or hydration continued while the native needs remained noncritical.

This MP snapshot preceded the final carried-bag completion, hunger-only food policy, and ground-bag source-position fixes. Those branches were checked against native single-player actions and the matching native API contracts. The MP result does not establish strict-checksum compatibility, every mod combination, or all container variants.

## Evidence and limits

Evidence is retained outside Git under `${XDG_STATE_HOME:-$HOME/.local/state}/app-verification/automindful/ui-loop-update/`. The single-player observations are in `live-1/sp-observations.json`; multiplayer observations are in `mp-client-1/report.json` and `native-journey.log`. Named screenshots, logs, package manifests, and the final verification report identify the tested candidates.

The installed game was Linux x86-64 Project Zomboid `42.22.2 3d39148846`, with bundled Java 25 and official Lifestyle: Hobbies `0.4.0.3`. The SP fixture requested accelerated sandbox XP settings; MP observations and a model reaching level 10 establish different facts. No normal-speed level 0–10 journey in both skills was completed for this candidate. Every plumbing sprite was not consumed from individually. Native metadata, cooldowns, source capacity, taint, permissions, and server restrictions still apply.

All owned test clients, servers, displays, sockets, and disposable caches were removed. Native tests used separate caches and did not edit personal profiles, saves, or installed upstream files.
