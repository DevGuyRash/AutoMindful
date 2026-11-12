# AutoMindful

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
4. Choose **Open AutoMindful** to see the full window, or **Train yoga** or **Train meditation** for a quick start. **Check supplies** opens the live report without interrupting training.

The original single-session Lifestyle action remains in the submenu. **Train both** is available in the AutoMindful window. Context menus follow Lifestyle's posture and availability rules instead of appearing everywhere by default.

During a running session, **AutoMindful (running)** lets you reopen the window even while Lifestyle hides its normal menu for timed actions. Closing the window or pressing Escape hides it without cancelling training. Loading a save or rejoining a server does not start the loop automatically.

## Use the live window

| Section | What it shows |
| --- | --- |
| Activity | Current training, care break, pause, or stop reason. |
| Progress | Skill levels, XP toward the next level, and a brief green gain or red loss indicator. |
| Supplies | Usable food, hydration, and literature in inventory and reachable nearby containers. |
| Preparation and returns | Requirements, warnings, and borrowed items waiting to go back. |

Counts refresh while the window is open, including after walking, inventory changes, and toggling collection. **Check supplies** refreshes immediately and confirms that the check happened. It does not collect or consume items. Counts represent usable items, not servings or days. A nourishing drink can count toward both food and hydration.

Drag the window's bottom or right resize handle to make more room. Its size and position are remembered. The Activity area expands for its status text; the main content scrolls when the available window space is too small. XP bars show progress within the current level. Exact XP changes appear briefly when the underlying skill exposes enough information; otherwise a level change is shown.

You can start with no food or water. Empty supply counts are warnings, not a start requirement. AutoMindful uses provisions when available and continues while the survivor's condition permits training. It stops for a genuine blocking condition rather than an empty inventory alone.

**Use adjacent supplies** starts off disabled. Enable it to let the loop borrow nearby provisions and appropriate opening tools as needed. You can change this setting during training. Previewing nearby stock does not enable collection.

## Prepare supplies

- Bring food, safe hydration, and useful literature for a long session. Available resources do not need to be consumed all at once.
- Native opening recipes handle supported cans and sealed items when the required tools are available. Items without a usable native opening recipe need manual preparation.
- Safe milk and other nourishing drinks can help where their native properties provide hunger or thirst relief. Worn hydration containers can also be used. Poisoned, tainted, alcoholic, spoiled, burnt, frozen, or dangerously uncooked sources are rejected.
- Nearby sinks, baths, toilets, showers, and ground water containers can supply clean water when adjacent collection is enabled. Native plumbing, remaining water, reach, locks, safehouses, and water safety still apply. Direct drinking takes the amount needed for current thirst rather than draining the source or requiring it to be picked up.
- Unread literature is preferred. When fiction becomes eligible for rereading under the game's cooldown, the oldest native reading date is preferred. Already-read print media and books still on cooldown are not forced into a useless reading loop.
- Use a lit place for reading. Yoga can also relieve boredom when its normal requirements permit it.

Borrowed books, unused food or drink, opening tools, and attributable leftover containers are returned to their original reachable source. Your own supplies and worn equipment stay yours. If a return is blocked or its source is no longer reachable, the item stays in inventory and the window explains it. The mod does not walk away to return an item or move unrelated inventory.

Supply choices compare the portion that would help your current needs. A useful drink or food that restores both can win; a tiny dual-purpose item does not automatically beat an adequate source. Otherwise, equally useful water choices prefer the largest current reserve, including permitted nearby plumbing. Food choices favor an adequate convenient portion over unnecessary preparation or borrowing. Calories do not make butter or another rich food win by themselves. See [supply selection](docs/supplies.md) for the policy and examples.

Zomboid's separate automatic-drinking option can still use carried water before a care break. AutoMindful leaves that preference unchanged. For exclusive control by these care actions, turn off **Automatically drink water when thirsty** under the game's **Options > Accessibility**.

## Keep control of the loop

**Stop training** cancels explicitly. Clear movement, sustained aiming, or another gameplay action taking control also cancels, with a short reason above the survivor. Looking at the window or context menu does not cancel. Inventory transfers can pause the automatic work and let it resume afterward.

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

See [verification](docs/verification.md) for the native and portable checks, [candidate verification](docs/verification-0.1.2.md) for the observed gameplay scope and [upstream notes](docs/upstream.md) for Lifestyle's action lifecycle.

## Publish

This public repository owns [workshop-publisher.json](workshop-publisher.json), its existing Workshop item ID, and checked release assets. The shared [Steam Workshop publisher](https://github.com/DevGuyRash/steam-workshop-publisher) remains generic. See [Workshop publishing](docs/workshop.md) for manual local or cloud publishing and authentication.
