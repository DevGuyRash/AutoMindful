# 0.1.2 verification

This report records the local and native verification for version 0.1.2. The candidate was kept unpublished during local testing; the user subsequently requested publication through the updated desktop Steam publisher. Release and Workshop publication follow [the publishing procedure](workshop.md).

The runtime contains nine client Lua modules, native Build 42 Mod Options, and the required `LifestyleHobbies` dependency. It adds no server code and does not award XP, change native skill thresholds, or copy upstream training actions.

## Automated checks

The verification entry point builds the complete versioned archive before running the portable controller/supply, UI/context, XP progress, supply policy, consumable, water-source, and release-integrity suites. It also compiles the native Java helpers and runs each Lua suite in a fresh installed Kahlua environment. With installed references, the core and XP suites exercise real Lifestyle Lua and the water suite exercises real `ISTakeWaterAction.lua`; game and network receivers remain explicit boundary doubles.

Important regressions include native-recursive carried-bag lookup, completion of returned loans, transfers from the actual current container, hunger-based portions without an extra calorie reserve, empty reserve starts, native critical need stops, oldest eligible rereads, separate opening-tool sources, and native source positions for ground bags without `SourceGrid`.

The final review also reproduced an opener disappearing after a borrowed can was collected. Supply use now revalidates the item, returns the unopened can, and continues noncritical training. The controller contract covers that transition and a later successful retry after the opener becomes available again. This specific race was checked in the portable and installed Kahlua suites with explicit game-boundary doubles, rather than in another native multiplayer session.

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

## XP, layout, and supply follow-up

A fresh disposable native client exercised the XP and resizing update. Clicking Meditation started native sitting and meditation and showed `1.25 / 75 XP`; Yoga remained `0 / 100 XP`. Controlled native XP adjustments in the test fixture produced a green `+10 XP` and a red `-3 XP`, with rising and fading indicators. These fixture adjustments are outside the product archive. The first window had no Activity scrollbar and no unnecessary outer scrollbar. Dragging the native resize handle reduced it to `540 × 487`, where outer scrolling became necessary; expanding it to `827 × 801` removed that need, and reopening preserved the geometry.

With boredom 40, no eligible literature, and yoga available, the actual Meditation button stopped at the meditation blocker without queuing yoga. Selecting Train both then stood up and queued native yoga.

The source-selection pass exposed an independent native behavior: Zomboid's automatic drinking consumed carried water before a care break. The controlled comparison was repeated after disabling that option through the real Options > Accessibility screen in the disposable cache only. The native action then selected a `5 L` ground bucket over an owned `0.5 L` bottle, leaving the bottle unchanged and about `4.5916 L` in the bucket. With both needs around `0.20`, a `1 L` milk container won over the bucket, retained about `0.5996 L`, and meditation resumed. Once hunger was restored, the same milk was preserved while the bucket supplied thirst relief. The product does not change the user's automatic-drinking option or install its global native hook.

This native snapshot preceded the final controller bookkeeping adjustment that marks both triggered care needs before the first supply action. Portable and installed Kahlua integration checks cover that adjustment in both directions: milk followed by plain water for residual thirst, and milk followed by plain food for residual hunger. The current complete verification run has 14 passing checks with a stable source fingerprint. The XP, UI, selection, and portion code match the native follow-up snapshot.

## Low-stamina meditation regression

The user's running eight-module candidate entered the generic resting phase when meditation was requested at roughly 10% stamina. Source review confirmed that AutoMindful waited for 95% endurance before any training and interrupted running meditation below 20%, even though Lifestyle's meditation gate and action do not impose an endurance requirement.

The corrected controller reserves that recovery policy for yoga. A disposable native client started meditation through the actual button at seeded endurance `0.10`. Lowering endurance to `0.05` while it was running left `LSMeditateAction` queued and produced actual Meditation XP of `2.5 / 75`. Stamina rose naturally between samples; the product adds no stamina-restoration effect. Both mode also ran meditation while yoga was unavailable at low endurance. With boredom above 30 and no eligible reading, Both waited for yoga recovery and then stood and started yoga once endurance was raised above the recovery target. Yoga-only remained resting near 90% and resumed above 95%, without substituting meditation.

Three controller integration regressions cover low-stamina start and continuation in Meditation and Both, yoga recovery hysteresis, and recovery when boredom and endurance temporarily block both activities. The previous controller fails the new start regression. All 14 portable and installed Kahlua checks pass for the corrected source. Native artifacts are under `low-stamina-native/`; the full check report is `low-stamina-checks/report.json`.

## Native multiplayer checks

An owned loopback server advertised Lifestyle, AutoMindful, and the client-only test fixture. The survivor had ordinary `access=user`; Lua checksum enforcement was disabled in this test environment.

Native meditation progressed from level 0 to 2 across the sample, survived window hiding, and retained progress across reconnection without automatically restarting. A nearby book was collected, read, returned to its original floor square, and meditation resumed while the window stayed hidden. Checking supplies and collection toggles did not cancel training. Manual inventory transfers paused and resumed it; walking cancelled with the visible overhead reason.

A milk carton retained `0.49 / 1 L` after the hydration care break. Nearby world-water drinking also worked with zero hydration items in inventory, followed by meditation. A fresh start with no permitted food or hydration continued while the native needs remained noncritical.

This MP snapshot preceded the final carried-bag completion, hunger-only food policy, and ground-bag source-position fixes. Those branches were checked against native single-player actions and the matching native API contracts. The MP result does not establish strict-checksum compatibility, every mod combination, or all container variants.

## Evidence and limits

Evidence is retained outside Git under `${XDG_STATE_HOME:-$HOME/.local/state}/app-verification/automindful/ui-loop-update/`. The single-player observations are in `live-1/sp-observations.json`; multiplayer observations are in `mp-client-1/report.json` and `native-journey.log`. Named screenshots, logs, package manifests, and the final verification report identify the tested candidates.

The XP and supply follow-up artifacts are under `xp-supplies-native/`; the current full check report is `xp-supplies-final-passed-checks/report.json`. `docs/supplies.md` records the shared ranking rule and independently calculated example outcomes.

The installed game was Linux x86-64 Project Zomboid `42.22.2 3d39148846`, with bundled Java 25 and official Lifestyle: Hobbies `0.4.0.3`. The SP fixture requested accelerated sandbox XP settings; MP observations and a model reaching level 10 establish different facts. No normal-speed level 0–10 journey in both skills was completed for this candidate. Every plumbing sprite was not consumed from individually. Native metadata, cooldowns, source capacity, taint, permissions, and server restrictions still apply.

All owned test clients, servers, displays, sockets, and disposable caches were removed. Native tests used separate caches and did not edit personal profiles, saves, or installed upstream files.
