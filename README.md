# AutoMindful

![AutoMindful logo](workshop/preview.png)

AutoMindful automates yoga and meditation in Project Zomboid's [Lifestyle: Hobbies](https://steamcommunity.com/sharedfiles/filedetails/?id=3403870858). It uses Lifestyle's normal actions and XP, takes care breaks, and resumes toward level 10. The window can stay closed while the loop runs.

## Install

1. Subscribe to [AutoMindful](https://steamcommunity.com/sharedfiles/filedetails/?id=3837554362) and [Lifestyle: Hobbies](https://steamcommunity.com/sharedfiles/filedetails/?id=3403870858).
2. Enable both for your game and restart the client.
3. For a manual installation, copy `mods/AutoMindful` into your Zomboid user folder's `mods` directory. Linux normally uses `~/Zomboid/mods/AutoMindful`.

If you already have a development copy under `~/Zomboid/Workshop/AutoMindful/Contents/mods/AutoMindful`, check which directory the game actually selects for mod ID `AutoMindful`. A new copy in `mods` does not replace the files in that staging directory. Update the selected copy, check its `42/mod.info` version, and restart the client. When using LuaBuddy, its `Zomboid/LuaBuddy/diagnostics.json` records the selected source and roots. Local installation does not update the public Workshop item.

AutoMindful uses client Lua for Build 42.22 and later. It has no server scripts. Ordinary Build 42 multiplayer loading still requires the server to advertise AutoMindful, and Lifestyle's normal server components must be available. The mod does not bypass server checks.

## Start from the right-click menu

1. Choose a safe training spot. Deploy a complete yoga mat if the sandbox requires one.
2. Right-click near your survivor and open Lifestyle's **Wellness** menu.
3. While standing, open **Yoga**. While sitting on the ground, open **Meditate**.
4. Choose **Open AutoMindful** for the window, or **Train yoga** or **Train meditation** for a skill loop. **Check supplies** opens the live report without interrupting training.

The original single-session Lifestyle action remains in the submenu. **Train both** is available in the AutoMindful window. Context menus follow Lifestyle's posture and availability rules instead of appearing everywhere by default.

During a running session, **AutoMindful (running)** lets you reopen the window even while Lifestyle hides its normal menu for timed actions. Closing the window or pressing Escape hides it without cancelling training. Loading a save or rejoining a server does not start the loop automatically.

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

**Use adjacent supplies** is separate from scouting. Turn it on if you want the survivor to use supplies within reach even with scouting off. It starts off disabled. Previewing nearby stock does not enable collection.

### Walk to supplies and return

**Scout nearby for supplies** appears in both the **AutoMindful** training window and **Options > Mods > AutoMindful**. Both controls change the same saved setting. Scouting is on by default; an existing saved off choice stays off until you turn it on in either place. Under **Options > Mods**, **Nearby search radius (tiles)** defaults to **10** and can be set from 2 to 30. Scouting includes adjacent supplies and starts a trip only when carried or adjacent supplies cannot meet a training need.

AutoMindful searches loaded squares on the same floor within a circular radius of the training spot, walks using native pathfinding, then rechecks normal adjacent access and safety before collecting or using supplies. Entertainment means eligible boredom-reducing literature. It returns borrowed items while still at the source, then walks back to the original training square before resuming. The live window and **Check supplies** use the same configured radius and source classification as care. Counts show known item contents, not guaranteed reachability. Uninspected or unconfirmed containers and unloaded parts of the area are reported separately, never presented as empty.

When no known supply can satisfy a need, the enabled care-trip option can scout an actual uninspected/unconfirmed container. It does not walk every tile. At the destination, the ordinary adjacent loot interface discovers the contents; AutoMindful waits up to three seconds for a useful response, then returns and skips an unproductive source for the rest of that training session. New contents discovered later can still turn an unknown container into a known useful source. Critical hunger or thirst only permits trips to known supplies, not exploratory visits. In multiplayer the explored flag can precede the server response, so an empty replicated list remains unconfirmed. Opening the report never performs this scouting. Known-stock preview remains available even with care trips off.

Discovery checks regular world containers, loose ground items, ground bags, eligible human corpses, and standard vehicle storage on the same floor. Vehicle storage includes open-access trunks/beds, trailer trunks, installed seats and gloveboxes. Closed access doors, moving vehicles and unsupported custom storage layouts are skipped; AutoMindful never opens/unlocks doors, enters vehicles or breaks windows. Vehicle trips use native interaction-area pathfinding and recheck native access before collecting or returning supplies. Repositioned vehicles cancel the outbound trip rather than pulling you beyond the scanned target. Animal bodies, fake-dead bodies and bodies with scheduled reanimation are excluded; that is not a guarantee that an area is safe. Vehicle/corpse discovery reads direct contents, not every nested bag. The maximum setting is 30 tiles; one shared snapshot is cached for a second to avoid repeating the whole scan for every need and UI refresh.

Use a safe, clear route. Walls, locks, safehouses, darkness, missing opening tools and native pathfinding can prevent a trip; no supplies are transferred remotely. The radius limits destinations, not the path length. In singleplayer AutoMindful switches fast-forward to normal speed before starting a supply walk: the game will not accept a walk above speed 2. If the game reports no path to a source, the mod skips it and can try another from the training spot. If there is no path home, it stops and explains why instead of training in the wrong place. Manual movement, cancellation, Stop and danger still take precedence. Borrowed items remain protected by the normal return rules.

## Prepare supplies

- Bring food, safe hydration, and useful literature for a long session. Available resources do not need to be consumed all at once.
- Native opening recipes handle supported cans and sealed items when the required tools are available. Items without a usable native opening recipe need manual preparation.
- Safe milk and other nourishing drinks can help where their native properties provide hunger or thirst relief. Worn hydration containers can also be used. Poisoned, tainted, alcoholic, spoiled, burnt, frozen, or dangerously uncooked sources are rejected.
- Bulk liquid in a bucket, large container, or other source that cannot be drunk from directly can fill a clean empty drinking vessel. Keep an empty bottle or cup in inventory, or enable adjacent supplies to borrow one nearby. AutoMindful pours only the useful portion, drinks it, and returns each borrowed container to its own origin. Existing drinks are preserved.
- Nearby sinks, baths, toilets, showers, and ground water containers can supply clean water when adjacent collection is enabled. Native plumbing, remaining water, reach, locks, safehouses, and water safety still apply. Direct drinking takes the amount needed for current thirst rather than draining the source or requiring it to be picked up.
- Unread literature is preferred. When fiction becomes eligible for rereading under the game's cooldown, the oldest native reading date is preferred. Already-read print media and books still on cooldown are not forced into a useless reading loop.
- Use a lit place for reading. Yoga can also relieve boredom when its normal requirements permit it.

Every component of a fluid mixture must be safe, including small amounts of harmful liquids. The source is checked before pouring and the vessel is checked again before drinking. Unsafe contents stay in their container. AutoMindful does not empty a vessel or pour leftovers back into another source.

Borrowed books, unused food or drink, opening tools, and attributable leftover containers are returned to their original reachable source. Borrowed empty drinking vessels retain their origin through filling and drinking. Your own supplies and worn equipment stay yours. If a return is blocked or its source is no longer reachable, the item stays in inventory and the window explains it. Outside a care trip, the mod does not walk away to return an item. It never moves unrelated inventory.

Supply choices compare the portion that would help your current needs. A useful drink or food that restores both can win; a tiny dual-purpose item does not automatically beat an adequate source. Otherwise, equally useful water choices prefer the largest current reserve, including permitted nearby plumbing. Food choices favor an adequate convenient portion over unnecessary preparation or borrowing. Calories do not make butter or another rich food win by themselves. See [supply selection](docs/supplies.md) for the policy and examples.

Zomboid's separate automatic-drinking option can still use carried water before a care break. AutoMindful leaves that preference unchanged. For exclusive control by these care actions, turn off **Automatically drink water when thirsty** under the game's **Options > Accessibility**.

## Keep control of the loop

You can eat, drink, transfer an item, or let another mod run a workout while AutoMindful is active. AutoMindful pauses, keeps your actions in their original order, and resumes after the queue and native activity have been quiet for 0.75 seconds. A long workout is fine. Continuous queued work takes priority; two timed actions do not run at once. Between training actions AutoMindful leaves a half-second opening for work that only queues when the survivor is idle. A pause does not end the session or show a completion card.

**Stop training**, cancel input, combat, running, sprinting, a floor change, or moving more than 1.5 tiles from the activity ends the session. Small position adjustments are fine. The reference follows AutoMindful's own supply walks, not a player's movement or an unrelated queued path. Looking at a context menu does not cancel. On an interrupted supply trip, the mod settles identifiable borrowed items, drops the old plan, checks that the training square is still accessible, and returns before choosing new work. It will not repeat a spent portion or claim another action's empty can.

You can start training while seated on furniture. AutoMindful waits for anyone else's action, uses the game's get-up action and waits for it to finish before sitting on the floor for meditation. If Lifestyle still owns the seat, AutoMindful waits for you to leave it normally.

When training stops or reaches its target, a small click-through HUD card shows the elapsed session time and any measured progress, even if the AutoMindful window is closed. If Lifestyle's XP data cannot establish an exact gain across a level change, the card reports the level change instead. Care breaks and supply trips do not end the session. The card fades after about four seconds; reopen AutoMindful for the full stop reason or pending returns.

Meditation needs sitting on the ground and cannot start above Lifestyle's boredom limit. Yoga needs standing and may require a complete two-tile mat. Native exhaustion, embarrassment, injuries, unsafe surroundings, and missing essentials can limit what the survivor can do. AutoMindful uses normal game time and XP rates; reaching both level caps can take many game days.

**Meditation** trains only meditation, and **Yoga** trains only yoga. A single-skill loop stops with its blocking reason if care cannot make that skill available. **Train both** permits alternating skills, including yoga to relieve boredom that blocks meditation.

Low stamina does not block or interrupt meditation. In Train both, meditation can continue while stamina recovers for yoga. Yoga keeps its recovery break, with a visible stamina target. Fatigue that requires sleep remains a separate care condition.


## Configure access

Open **Options > Mods > AutoMindful** to assign **Open AutoMindful window** to a key. It starts unbound to avoid taking another control. The shortcut is suppressed while typing or chatting.

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
