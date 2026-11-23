# AutoMindful

![AutoMindful logo](workshop/preview.png)

AutoMindful automates yoga and meditation in Project Zomboid's [Lifestyle: Hobbies](https://steamcommunity.com/sharedfiles/filedetails/?id=3403870858). It uses Lifestyle's normal actions and XP, takes care breaks, and resumes toward level 10. The window can stay closed while the loop runs.

## Install

1. Subscribe to [AutoMindful](https://steamcommunity.com/sharedfiles/filedetails/?id=3837554362) and [Lifestyle: Hobbies](https://steamcommunity.com/sharedfiles/filedetails/?id=3403870858).
2. Enable both for your game and restart the client.
3. For a manual installation, copy `mods/AutoMindful` into your Zomboid user folder's `mods` directory. Linux normally uses `~/Zomboid/mods/AutoMindful`.

If you already have a development copy under `~/Zomboid/Workshop/AutoMindful/Contents/mods/AutoMindful`, check which directory the game actually selects for mod ID `AutoMindful`. A new copy in `mods` does not replace the files in that staging directory. Update the selected copy, check its `42/mod.info` version, and restart the client. Local installation does not update the public Workshop item.

AutoMindful uses client Lua for Build 42.22 and later. It has no server scripts. Once AutoMindful is loaded on the client, AutoMindful itself does not require a server mod or server-side setup. Lifestyle's normal gameplay requirements still apply. The mod does not bypass server checks.

## Start from the right-click menu

1. Choose a safe training spot. Deploy a complete yoga mat if the sandbox requires one.
2. Right-click near your survivor and open Lifestyle's **Wellness** menu.
3. While standing, open **Yoga**. While sitting on the ground, open **Meditate**.
4. Choose **Open AutoMindful** to open the window. Pick a training mode, **Recovery** to handle needs without targeting XP, or **Recover to Full Endurance** to stop once endurance is full and other actions have settled. **Check supplies** opens the live report without interrupting the current mode.

A normal mod installation shows AutoMindful's artwork: a window for **Open**, a crate for **Check supplies**, a standing or seated figure for each skill and a heart for **Full Endurance**. A client-only loader that restores Lua without mounting loose images uses built-in game icons instead: clipboard, backpack, dumbbell, candle and endurance, respectively. You do not need a separate icon pack. The manual **(once)** action keeps Lifestyle's artwork when available.

The original single-session Lifestyle action remains in the submenu. **Train both** is available in the AutoMindful window. Context menus follow Lifestyle's posture and availability rules instead of appearing everywhere by default.

### Target a moodle tier

Use **Meditate to…** or **Do Yoga to…** in the window or the matching Wellness submenu. Pick a Mindfulness or Zen tier and AutoMindful stops once the game shows that tier or higher. Tiers you already have and targets your skill cannot reach are greyed out. Some native Yoga completions jump straight past a lower tier, which still satisfies the goal.

Under **Options → Mods → AutoMindful**, set separate minimums for Meditation and Yoga during **Recovery**, **Train Both**, or **max-level practice**. All default to **the highest tier**, or you can select **No minimum**. Saved selections are preserved. AutoMindful aims for the highest attainable tier up to your selection: selecting Perfect Mindfulness at Meditation level 6 targets Strong Mindfulness instead. Recovery / relief settings apply whenever AutoMindful chooses that practice to relieve a need, including during training. They do not start practice by themselves. During Train Both or max-level practice, the current practice can keep its turn across sessions until the minimum is observed. Normal actions and care still take priority.


On the character's **Skills** tab, expand **Lifestyle**. **Yoga** sits directly below **Meditation**, with ten rank boxes like the other skills. Hover over the current box or select the row with a controller to see your Yoga XP toward the next rank. The row reads Lifestyle's progress; it doesn't register a perk, grant XP, or add a second row if Lifestyle already shows Yoga.

Hover a Yoga or Meditation rank to see its available benefits as well as progress or lock status. AutoMindful uses Lifestyle's rank descriptions rather than a second set of translated tooltips. Where verified, a vague Yoga note shows a concrete pose limit or a normal in-game Zen duration instead. Open **Skill Guide** under **Progress** and pick Meditation, Mindfulness, Yoga, Zen, or Lessons. The guide separates what the action does from the lasting effects it can grant, including the actual skill XP effects and durations where Lifestyle provides them. Descriptions name the unit and time basis (for example, percentage points per in-game minute). Color distinguishes section labels, key numbers, and cautions, and the guide wraps within the window. Browsing does not end training.

During a running session, **AutoMindful (running)** or **AutoMindful (recovery)** lets you reopen the window even while Lifestyle hides its normal menu for timed actions. Closing the AutoMindful window hides it without cancelling the current mode. Escape can still stop the mode if the game treats it as World Cancel Action. Loading a save or rejoining a server does not start the loop automatically.

## Use the live window

| Section | What it shows |
| --- | --- |
| Activity | Current training, care break, pause, or stop reason. |
| Progress | Skill levels, XP toward the next level, and a brief green gain or red loss indicator. |
| Supplies | Known food, hydration, and literature in inventory and containers within the configured radius. |
| Preparation and returns | Requirements, warnings, and borrowed items waiting to go back. |

Known counts refresh while the window is open from a shared radius snapshot, including after walking, inventory changes, and toggling collection. The nearby column shows the configured tile radius. **Check supplies** forces a fresh snapshot and confirms the check happened. It does not walk, collect, consume, or remotely generate container contents. Counts represent usable items, not servings or days. A nourishing drink can count toward both food and hydration.

Drag the window's bottom or right resize handle to make more room. Its size and position are remembered. The Activity area expands for its status text; the main content scrolls when the available window space is too small. XP bars show progress within the current level. Exact XP changes appear briefly when the underlying skill exposes enough information; otherwise a level change is shown.

You can start with no food or water. Empty supply counts are warnings, not a start requirement. AutoMindful uses provisions when available and continues while the survivor's condition permits training. It stops for a genuine blocking condition rather than an empty inventory alone.

**Use adjacent supplies** starts on for a survivor with no saved choice. When scouting is off, this still lets that survivor use supplies within reach, without walking away. A saved off choice stays off. Previewing nearby stock does not change either setting.

### Walk to supplies and return

**Scout nearby for supplies** appears in both the **AutoMindful** training window and **Options > Mods > AutoMindful**. Both controls change the same saved setting. Scouting is on by default; an existing saved off choice stays off until you turn it on in either place. Under **Options > Mods**, **Nearby search radius (tiles)** defaults to **10** and can be set from 2 to 30. Scouting includes adjacent supplies and starts a trip only when carried or adjacent supplies cannot meet a training need. **Train both** does not send the survivor out for a supply run on startup.

A place that actually supplied care can be checked first on a later trip. Remembered fixtures and containers are hints, not permission or proof that supplies remain. AutoMindful verifies the source and matching supplies again, and uses its normal search if the remembered stop is no longer usable. Carried supplies still take priority.

AutoMindful searches loaded squares on the same floor within a circular radius of the training spot, walks using native pathfinding, then rechecks normal adjacent access and safety before collecting or using supplies. Entertainment means eligible boredom-reducing literature. It returns borrowed items while still at the source, then walks back to the original training square before resuming. The live window and **Check supplies** use the same configured radius and source classification as care. Counts show known item contents, not guaranteed reachability. Uninspected or unconfirmed containers and unloaded parts of the area are reported separately, never presented as empty.

When no known supply can satisfy a need, the enabled care-trip option can scout a specific uninspected or unconfirmed container. Unknown contents do not interrupt an otherwise eligible practice on multiplayer. At the destination, the ordinary adjacent loot interface discovers the contents; AutoMindful waits up to three seconds for a useful response and returns if none arrives. Unconfirmed searches and temporarily unusable known sources have retry delays instead of being blacklisted for the whole session. New contents discovered later can still turn an unknown container into a known useful source. Critical hunger or thirst only permits trips to known supplies, not exploratory visits. In multiplayer the explored flag can precede the server response, so an empty replicated list remains unconfirmed. Opening the report never performs this scouting. Known-stock preview remains available even with care trips off.

Discovery checks regular world containers, loose ground items, ground bags, eligible human corpses, and standard vehicle storage on the same floor. Vehicle storage includes open-access trunks/beds, trailer trunks, installed seats and gloveboxes. Closed access doors, moving vehicles and unsupported custom storage layouts are skipped; AutoMindful never opens/unlocks doors, enters vehicles or breaks windows. Vehicle trips use native interaction-area pathfinding and recheck native access before collecting or returning supplies. Repositioned vehicles cancel the outbound trip rather than pulling you beyond the scanned target. Animal bodies, fake-dead bodies and bodies with scheduled reanimation are excluded; that is not a guarantee that an area is safe. Vehicle/corpse discovery reads direct contents, not every nested bag. The maximum setting is 30 tiles; one shared snapshot is cached for a second to avoid repeating the whole scan for every need and UI refresh.

Use a safe, clear route. Walls, locks, safehouses, darkness, missing opening tools and native pathfinding can prevent a trip; no supplies are transferred remotely. The radius limits destinations, not the path length. In singleplayer AutoMindful switches fast-forward to normal speed before starting a supply walk: the game will not accept a walk above speed 2. If the game reports no path to a source, the mod skips it and can try another from the training spot. If the game reports a failed walk home, AutoMindful briefly waits and can ask the game to retry twice. Every attempt rechecks the original loaded square and normal access. It never substitutes a different tile. If the route still fails, the square is inaccessible, or the native action fails to settle, AutoMindful stops with a reason. Manual movement, cancellation, Stop and danger still take precedence. Borrowed items remain protected by the normal return rules.

## Prepare supplies

- Bring food, safe hydration, and useful literature for a long session. Available resources do not need to be consumed all at once.
- Native opening recipes handle supported cans and sealed items when the required tools are available. Items without a usable native opening recipe need manual preparation.
- Safe milk and other nourishing drinks can help where their native properties provide hunger or thirst relief. Worn hydration containers can also be used. Poisoned, tainted, alcoholic, spoiled, burnt, frozen, or dangerously uncooked sources are rejected.
- Bulk liquid in a bucket, large container, or other source that cannot be drunk from directly can fill a clean empty drinking vessel. Keep an empty bottle or cup in inventory, or enable adjacent supplies to borrow one nearby. AutoMindful pours only the useful portion, drinks it, and returns each borrowed container to its own origin. Existing drinks are preserved.
- Nearby sinks, baths, toilets, showers, and ground water containers can supply clean water when adjacent collection is enabled. Native plumbing, remaining water, reach, locks, safehouses, and water safety still apply. Direct drinking takes the amount needed for current thirst rather than draining the source or requiring it to be picked up.
- Unread literature is preferred. When fiction becomes eligible for rereading under the game's cooldown, the oldest native reading date is preferred. Already-read print media and books still on cooldown are not forced into a useless reading loop.
- Use a lit place for reading. Yoga can also relieve boredom when its normal requirements permit it.

**Pain relief:** Normal training can use one plain stock **Painkillers** dose at 10/100 pain, even when pain is steady. It looks in carried supplies first, then permitted adjacent or known scouted stock. It does not search unknown containers for medicine. Meditation may pause for care; yoga finishes the current pose. Both Recovery modes use normal pain care while active.

AutoMindful re-doses only if pain is still above 10 and the game has shown that the previous confirmed effect has worn off. It won't remove protective gear, stack doses, or combine doses with sedatives or intoxication. If the previous request never confirms, it will not retry it while the pain remains high. The mod uses the game's own medication action.

**Lifestyle restroom and hygiene:** With Lifestyle hygiene enabled, training can visit a usable, permitted toilet and return to the exact training spot. If no usable toilet is found, it keeps training at the first urgency tier and uses Lifestyle's normal on-ground action only when it becomes available and safe. For low hygiene, it can use one eligible perfume or cologne dose to reduce the current negative moodle, even if it does not clear it. If needed, it seeks a water source that offers the game's **Wash Yourself** body action. This is not an automatic Lifestyle shower or bath and does not change clothes. When the survivor is already clean, the remaining Lifestyle hygiene penalty can fade naturally. It does not wash clothes or do other chores. A body wash may remove makeup as in vanilla. If exact care or the return route cannot finish, existing safety and return rules still apply.

Every component of a fluid mixture must be safe, including small amounts of harmful liquids. The source is checked before pouring and the vessel is checked again before drinking. Unsafe contents stay in their container. AutoMindful does not empty a vessel or pour leftovers back into another source.

Borrowed books, unused food or drink, opening tools, and attributable leftover containers are returned to their original reachable source. Borrowed empty drinking vessels retain their origin through filling and drinking. Your own supplies and worn equipment stay yours. If a return is blocked or its source is no longer reachable, the item stays in inventory and the window explains it. Outside a care trip, the mod does not walk away to return an item. It never moves unrelated inventory.

Supply choices compare the portion that would help your current needs. A useful drink or food that restores both can win; a tiny dual-purpose item does not automatically beat an adequate source. Otherwise, equally useful water choices prefer the largest current reserve, including permitted nearby plumbing. Food choices favor an adequate convenient portion over unnecessary preparation or borrowing. Calories do not make butter or another rich food win by themselves. See [supply selection](docs/supplies.md) for the policy and examples.

Zomboid's separate automatic-drinking option can still use carried water before a care break. AutoMindful leaves that preference unchanged. For exclusive control by these care actions, turn off **Automatically drink water when thirsty** under the game's **Options > Accessibility**.

## Keep control of the loop

**Activity** explains what AutoMindful is doing or waiting for. Expand **Recent decisions** to see the last six changes for this survivor in the current session. A supply report with uninspected nearby storage cannot establish that no safe water exists.

You can eat, drink, transfer an item, or let another mod run a workout while AutoMindful is active. AutoMindful pauses, keeps your actions in their original order, and resumes after the queue and native activity have been quiet for 0.75 seconds. A long workout is fine. Continuous queued work takes priority; two timed actions do not run at once. Between training actions AutoMindful briefly leaves the queue open for work that only starts when the survivor is idle. A pause does not end the session or show a completion card.

You can also open the world map or read a paper map during yoga or meditation. Training waits for your map to close or collapse, not just for the short reading animation to end. The minimap and another local player's map do not pause you. If another interface removes a training action without leaving any identifiable activity, AutoMindful waits and rechecks. Single-skill training retries the interrupted exercise. Train both remembers its next turn through care and foreign actions; a blocked skill keeps its turn instead of being displaced by fallback practice. After a practice or when a long seated meditation sees substantial endurance recovery, AutoMindful briefly leaves the native queue open so another action can become ready. It does not have to recognize the other mod. If nobody starts an action, the selected training resumes; the pause does not count as a completed turn. A silent start or a canceled practice gets up to three retries after 0.75, 1.5 and 3 seconds of quiet. Completing real practice resets that budget; preparing gear or opening a map does not. Each retry rechecks your current needs and Lifestyle's requirements.

Ordinary walking pauses training or Recovery and resumes from the new spot once you settle. Walking away from a supply trip abandons that route rather than forcing you back. **Stop All** stops only AutoMindful; it leaves your actions and other mods' actions alone. Explicit cancel, confirmed combat, aiming, running or sprinting with movement input, unexpected displacement, and floor changes can still stop the mode. Confirmed combat, player input to jog or sprint, and world cancel input still end training even when the native action stops and the input is released before the next update. A running or sprinting animation flag with no movement input is not a stop by itself. A canceled native handle that still belongs to the same exercise after five seconds disarms training without touching other work. A right-click to inspect a real menu or map does not cancel; holding aim input outside those screens for half a second does. If training repeatedly disappears without an identifiable action, the session stops instead of staying armed indefinitely. When an interruption does not abandon the route, the mod settles identifiable borrowed items, drops the old plan, checks that the training square is still accessible, and returns before choosing new work. It will not repeat a spent portion or claim another action's empty can. When the game reports two failed paths home, the final try can use the survivor's saved ground position on the same tile rather than its center. It never changes the training tile or adds a fourth attempt.

You can start training while seated on furniture. AutoMindful waits for anyone else's action, uses the game's get-up action and waits for it to finish before sitting on the floor for meditation. If Lifestyle still owns the seat, AutoMindful waits for you to leave it normally.

When training stops or reaches its target, a small click-through HUD card shows the elapsed session time and any measured progress, even if the AutoMindful window is closed. If Lifestyle's XP data cannot establish an exact gain across a level change, the card reports the level change instead. Care breaks and supply trips do not end the session. The card fades after about four seconds; reopen AutoMindful for the full stop reason or pending returns.

Meditation needs sitting on the ground and cannot start above Lifestyle's boredom limit. Yoga needs standing and may require a complete two-tile mat. Native exhaustion, embarrassment, injuries, unsafe surroundings, and missing essentials can limit what the survivor can do. AutoMindful uses normal game time and XP rates; reaching both level caps can take many game days.

**Meditation** targets only Meditation ranks, and **Yoga** targets only Yoga ranks. Either skill may still be used for care. A single-skill loop stops with its blocking reason if care cannot make that skill available. **Train both** has three cycling choices, available in both the AutoMindful window and **Options > Mods > AutoMindful**. They change the same saved setting and apply at the next safe decision:

- **Alternate** (default): switch after a completed practice.
- **Lowest progress first**: prefer the skill with less progress, counting its level and the fraction of the next level earned.
- **Closest to level 10 first**: prefer finishing the more advanced skill, then train the other.

The Activity panel shows the next owed skill and Lifestyle's current blocker when it is known.

Low endurance does not block Meditation. In Yoga training, AutoMindful may meditate while the native Lifestyle menu reports that low endurance blocks Yoga, if Meditation is available without a gear change. It stops that fallback at the first eligible check, then yields to the queue and returns to Yoga when safe. If another native requirement takes over, the fallback ends. Train Both retains its bounded interim Meditation while the owed Yoga turn waits. No extra AutoMindful endurance cutoff is used. Fatigue that requires sleep is a separate care condition.

**Practice for relief:** With supported Lifestyle settings, AutoMindful can take a separate, bounded Yoga or Meditation care break. It prefers suitable immediate supplies and checks the current rank and native requirements without unequipping bags or dropping items for optional care. Recovery can use Basic Mindfulness for panic, Strong for pain, and Perfect for limited, stable health loss. In both Recovery and ordinary training, once hunger reaches 15% and no suitable food is confirmed, Meditation rank 6 or higher can build Strong Mindfulness. An active Strong or Perfect tier can ease hunger passively, even above 30%. AutoMindful can renew it after a measured drop if hunger still needs attention. How much relief you get depends on the survivor, settings and native timing. Lifestyle requires Meditation ranks 3, 6, and 10 respectively and the preceding tier to be active when building the next one. A new tier does not count as relief: AutoMindful can watch the relevant stat while leaving the action queue available. Mindfulness adds no calories. Actual food wins when available. If critical hunger has no food and a bounded native attempt or observation cannot confirm relief, training stops; persistent Recovery waits for food. Care does not use up a Train Both turn. Turn off practice-based relief in Mod Options for supply-only care.

**Practice at max rank:** Start **Train Both** after both skills reach level 10 to alternate Yoga and Meditation while idle, regardless of training order. If only one is maxed, Train Both still trains only the unfinished skill. Start **Yoga** or **Meditation** at its cap to practice only that one, with the usual optional care breaks. Max-rank practice leaves room for other actions and pauses for them; it does not require XP gains. A training session started below the cap still ends when it reaches its goal. Unlike Recovery, max-rank practice does not need an active care need to start a session.

**Recovery** keeps AutoMindful watching for needs without training toward a rank. It works at rank 0 and at both rank caps. It uses the usual supplies, scouting, and Lifestyle care rules. It can use Yoga or Meditation when the current skill, benefit and safety checks make it useful, but it does not use up a training turn. Available food, water and suitable treatment take priority; Mindfulness cannot replace nutrition, water, or urgent care. After its own work, Recovery leaves a brief opening for other actions, and resumption never cancels a queued foreign action. Ordinary walking pauses Recovery or training and resumes after you settle. Walking away from a supply trip abandons that route rather than forcing you back. Running, aiming, combat, unexplained movement, and explicit stops can still end the mode. **Stop All** or an explicit cancel ends the session; safety stops still apply.

The panel's **gear button** opens only AutoMindful's options. It edits the same settings as Mod Options, not a second profile. The main panel remembers where you moved or resized it. On the first open it fits the regular controls and status content when the screen has room; on smaller screens or after you resize it, the body can scroll.

**Recover to Full Endurance** runs the same background care until the game reports 100% endurance and other actions have finished. It lets the survivor rest normally through an idle queue rather than forcing Meditation. The regular **Recovery** mode stays on at full endurance. Press **0** to open the pane if that key is unused; it does not start a mode. Override the shortcut or disable the default in Mod Options.

## Configure access

Open **Options > Mods > AutoMindful** to assign **Open AutoMindful window** to a key. The custom binding starts unassigned; by default, top-row **0** opens the window when the key is free. You can turn off that fallback. The shortcut is suppressed while typing or chatting.

Enable **Always show AutoMindful in the world context menu** there if you prefer the general entry. It starts off disabled. Window position and the nearby-collection choice are remembered for the survivor.

## Build and verify

Python 3.10+ and `luac5.1` are development tools. The installed mod needs neither.

```sh
python3 tools/build.py
python3 tools/verify.py
```

The archive contains only AutoMindful and its license under `Contents/mods/AutoMindful`. The authoritative version is `mods/AutoMindful/42/mod.info`. Game and Workshop libraries remain in their installed locations.

See [verification](docs/verification.md) for the native and portable checks, [0.1.3 verification](docs/verification-0.1.3.md) for the bulk-fluid journeys, [0.1.2 verification](docs/verification-0.1.2.md) for the earlier gameplay scope, and [upstream notes](docs/upstream.md) for Lifestyle's action lifecycle.

## Publish

This public repository owns [workshop-publisher.json](workshop-publisher.json), its existing Workshop item ID, and checked release assets. The shared [Steam Workshop publisher](https://github.com/DevGuyRash/steam-workshop-publisher) remains generic. See [Workshop publishing](docs/workshop.md) for manual local or cloud publishing and authentication.
