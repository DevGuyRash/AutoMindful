# AutoMindful

![AutoMindful logo](workshop/preview.png)

AutoMindful automates yoga and meditation in Project Zomboid's [Lifestyle: Hobbies](https://steamcommunity.com/sharedfiles/filedetails/?id=3403870858). It uses Lifestyle's normal actions and XP, takes care breaks, and resumes toward level 10. The window can stay closed while the loop runs.


## Install

1. Subscribe to [AutoMindful](https://steamcommunity.com/sharedfiles/filedetails/?id=3837554362) and [Lifestyle: Hobbies](https://steamcommunity.com/sharedfiles/filedetails/?id=3403870858).
2. Enable both for your game and restart the client.
3. For a manual installation, copy `mods/AutoMindful` into your Zomboid user folder's `mods` directory. Linux normally uses `~/Zomboid/mods/AutoMindful`.

If you already have a development copy under `~/Zomboid/Workshop/AutoMindful/Contents/mods/AutoMindful`, check which directory the game actually selects for mod ID `AutoMindful`. A new copy in `mods` does not replace the files in that staging directory. Update the selected copy, check its `42/mod.info` version, and restart the client. Local installation does not update the public Workshop item.

AutoMindful uses client Lua for Build 42.22 and later. It has no server scripts. Once AutoMindful is loaded on the client, AutoMindful itself does not require a server mod or server-side setup. Lifestyle's normal gameplay requirements still apply. The mod does not bypass server checks.

## Start a job

Right-click and open Lifestyle's **Wellness** menu. Lifestyle's own **Yoga** or **Meditate** stays one click away; beside it, **AutoMindful** lists what your survivor can do now:

| Job | What it does |
| --- | --- |
| Yoga, Meditation | Train that skill to level 10. At level 10, practise while idle. |
| Yoga and Meditation | Take turns. Offered while both are below 10, or once both are there. |
| Reach a moodle tier | Practise until a Mindfulness or Zen tier is active, then stop. Only tiers you can reach are listed. |
| Recovery | Look after needs in the background without training. |

A job that is blocked says why. One that makes no sense right now is not listed. AutoMindful sits down or stands up by itself, so both practices are offered in either posture.

Right-click a deployed **yoga mat** for **Train Yoga here**: the survivor walks onto it and starts.

While a job runs Lifestyle hides Wellness, so right-click **your survivor** instead: **AutoMindful** then offers **Stop**, **Switch to** and **Show window**. Right-clicking anything else shows nothing from AutoMindful. Switching needs no separate Stop. Loading a save or rejoining a server does not start a job.

If you would rather always see the entry, turn on **Always in the right-click menu** in Settings. A client-only loader that restores Lua without mounting loose images shows built-in game icons instead of AutoMindful's artwork.

## The window

Press **0** to open or close it, if that key is free, or choose **Show window**. Closing it never stops a job. The window fits its contents; drag a corner to choose your own size, and right-click it to go back.

| Tab | What it shows |
| --- | --- |
| Now | Idle: active needs and the jobs you can start. Running: what it is doing and why, XP gained, **Stop** and **Switch**. |
| Supplies | Known food, drink, reading and painkillers, how far care may reach, and what is still borrowed. |
| Log | Recent decisions with their reasons, and **Copy report**. |
| Guide | What Yoga, Meditation, Mindfulness and Zen do at your rank. |
| Settings | Everything in **Options > Mods > AutoMindful**, applied as you click. |

The **_** button shrinks a running job to one line that stays on screen, with its progress and **Stop**.

Hover over Lifestyle's Zen moodle for its tier and XP effects. On the character's **Skills** tab, **Yoga** sits below **Meditation** with Lifestyle's own progress; hover a box for that rank's benefits. The row never registers a perk or grants XP.

### Moodle tiers

Under **Settings**, choose how far each practice should go in **Training both**, **at level 10**, and when started for **relief**. The default is the highest tier your rank can reach; **No minimum** turns it off. A tier is never forced past Lifestyle's own limits, and urgent care always comes first. **Recovery finishes its tier** keeps a started target even if the need that started it clears.

### How far care may reach

**Look for supplies** has three answers: **Walk to nearby supplies** (default, within the search radius), **Only what is within reach**, and **Only what you carry**. The radius defaults to 10 tiles and can be 2 to 30 in Mod Options.

On a trip AutoMindful walks with the game's own pathfinding to a loaded square on the same floor, rechecks access and safety there, uses what it came for, returns borrowed items at the source, and walks back to the training spot. If fast-forward was on, it is restored on arrival. It never opens or unlocks doors, enters vehicles, breaks windows, or moves loot remotely. Locked, safehouse, moving-vehicle and unsafe-corpse storage is skipped.

A source that failed is left alone until its surroundings change, and each further failure lengthens the wait. When the game finds no path to two things in the same room, the rest of that room is ruled out with them, and the next known source is tried from where the survivor already is. Opening unknown containers is limited to three fruitless trips per need before backing off.

Unknown contents are unknown, never empty. AutoMindful looks into an unopened container only when nothing known will do, between practices, or at a critical need. If the walk home fails three times the job stops with a reason. Borrowed items are returned when their origin is reachable; otherwise they stay with you and the window says so.

## Prepare supplies

Training and **Recovery** use the same survival rules. The first hunger or thirst moodle is handled at the next break between practices. A running practice is only broken off at the second moodle, and only when a usable supply is confirmed: stopping Yoga early costs XP and its Zen, and stopping Meditation resets its focus.

Low health pauses training for XP, not safe survival care: eating and drinking come before everything else, including returning what was borrowed. Nearby zombies, bleeding or fire pause a job; it continues about ten seconds after the danger has passed. If nothing known can meet a critical need, AutoMindful looks into nearby containers rather than waiting.

- Bring food, safe hydration, and useful literature for a long session. Available resources do not need to be consumed all at once.
- Native opening recipes handle supported cans and sealed items when the required tools are available. Items without a usable native opening recipe need manual preparation.
- Safe milk and other nourishing drinks can help where their native properties provide hunger or thirst relief. Worn hydration containers can also be used. Poisoned, tainted, alcoholic, spoiled, burnt, frozen, or dangerously uncooked sources are rejected. AutoMindful rechecks the exact item or water source at the native bite or sip, so something that becomes unsafe after selection is not deliberately consumed.
- Bulk liquid in a bucket, large container, or other source that cannot be drunk from directly can fill a clean empty drinking vessel. Keep an empty bottle or cup in inventory, or enable adjacent supplies to borrow one nearby. AutoMindful pours only the useful portion, drinks it, and returns each borrowed container to its own origin. Existing drinks are preserved.
- Nearby sinks, baths, toilets, showers, and ground water containers can supply clean water when adjacent collection is enabled. Native plumbing, remaining water, reach, locks, safehouses, and water safety still apply. Direct drinking takes the amount needed for current thirst rather than draining the source or requiring it to be picked up.
- Unread literature is preferred. When fiction becomes eligible for rereading under the game's cooldown, the oldest native reading date is preferred. Already-read print media and books still on cooldown are not forced into a useless reading loop.
- Use a lit place for reading. Yoga can also relieve boredom when its normal requirements permit it.

**Pain relief:** Normal training can use one plain stock **Painkillers** dose at 10/100 pain, even when pain is steady. It looks in carried supplies first, then permitted adjacent or known scouted stock. It does not search unknown containers for medicine. Meditation may pause for care; yoga finishes the current pose. Recovery uses normal pain care while active.

AutoMindful re-doses only if pain is still above 10 and the game has shown that the previous confirmed effect has worn off. It won't remove protective gear, stack doses, or combine doses with sedatives or intoxication. If the previous request never confirms, it will not retry it while the pain remains high. The mod uses the game's own medication action.

**Lifestyle restroom and hygiene:** With Lifestyle hygiene enabled, AutoMindful can visit a usable, permitted toilet. It starts the normal toilet action as soon as the walk settles and the action queue is clear. It only uses toilet paper, tissues or napkins, never rags, notes or cash. It uses Lifestyle’s flush rules and can attempt a native unclog when an unbroken plunger is in the main inventory. On a successful care trip, it checks for other active needs nearby before walking back once to the original training spot. Further walks stay within the original scouting range; an interaction already reachable from the current spot can still be used. Manual actions always take priority. If no usable toilet is found, it keeps training at the first urgency tier and uses Lifestyle's normal on-ground action only when it becomes available and safe. For low hygiene, it can use one eligible perfume or cologne dose to reduce the current negative moodle, even if it does not clear it. If needed, it seeks a water source that offers the game's **Wash Yourself** body action. This is not an automatic Lifestyle shower or bath and does not change clothes. When the survivor is already clean, the remaining Lifestyle hygiene penalty can fade naturally. It does not wash clothes or do other chores. A body wash may remove makeup as in vanilla. If exact care or the return route cannot finish, existing safety and return rules still apply.

Every component of a fluid mixture must be safe, including small amounts of harmful liquids. The source is checked before pouring and the vessel is checked again before drinking. Unsafe contents stay in their container. AutoMindful does not empty a vessel or pour leftovers back into another source.

Borrowed books, unused food or drink, opening tools, and attributable leftover containers are returned to their original reachable source. Borrowed empty drinking vessels retain their origin through filling and drinking. Your own supplies and worn equipment stay yours. If a return is blocked or its source is no longer reachable, the item stays in inventory and the window explains it. Outside a care trip, the mod does not walk away to return an item. It never moves unrelated inventory.

Supply choices compare the portion that would help your current needs. A useful drink or food that restores both can win; a tiny dual-purpose item does not automatically beat an adequate source. Otherwise, equally useful water choices prefer the largest current reserve, including permitted nearby plumbing. Food choices favor an adequate convenient portion over unnecessary preparation or borrowing, then what will not add unhappiness, then what spoils first. A can counts as food when an opener is in the same cupboard. Calories do not make butter or another rich food win by themselves. See [supply selection](docs/supplies.md) for the policy and examples.

Zomboid's separate automatic-drinking option can still use carried water before a care break. AutoMindful leaves that preference unchanged. For exclusive control by these care actions, turn off **Automatically drink water when thirsty** under the game's **Options > Accessibility**.

## Keep control of the loop

You can eat, drink, transfer an item, or let another mod run a workout while AutoMindful is active. AutoMindful pauses, keeps your actions in their original order, and resumes after the queue and native activity have been quiet for 0.75 seconds. If you keep taking over, it waits longer each time. A long workout is fine. Continuous queued work takes priority; two timed actions do not run at once. Between training actions AutoMindful briefly leaves the queue open for work that only starts when the survivor is idle. A pause does not end the session or show a completion card.

You can also open the world map or read a paper map during yoga or meditation. Training waits for your map to close or collapse, not just for the short reading animation to end. The minimap and another local player's map do not pause you. If another interface removes a training action without leaving any identifiable activity, AutoMindful waits and rechecks. Single-skill training retries the interrupted exercise. Train both remembers its next turn through care and foreign actions; a blocked skill keeps its turn instead of being displaced by fallback practice. After a practice or when a long seated meditation sees substantial endurance recovery, AutoMindful briefly leaves the native queue open so another action can become ready. It does not have to recognize the other mod. If nobody starts an action, the selected training resumes; the pause does not count as a completed turn. A silent start or a canceled practice gets up to three retries after 0.75, 1.5 and 3 seconds of quiet. Completing real practice resets that budget; preparing gear or opening a map does not. Each retry rechecks your current needs and Lifestyle's requirements.

Ordinary walking pauses training or Recovery and resumes from the new spot once you settle. Walking away from a supply trip abandons that route rather than forcing you back. **Stop** stops only AutoMindful; it leaves your actions and other mods' actions alone. Explicit cancel, attacking, held aim, running or sprinting with movement input, unexpected displacement, and floor changes can still stop the mode. Attacking, player input to jog or sprint, and world cancel input still end training even when the native action stops and the input is released before the next update. A running or sprinting animation flag with no movement input is not a stop by itself. A canceled native handle that still belongs to the same exercise after five seconds disarms training without touching other work. A right-click does not cancel, even where the game briefly reports it as aiming; holding aim for half a second does. If training repeatedly disappears without an identifiable action, the session stops instead of staying armed indefinitely. When an interruption does not abandon the route, the mod settles identifiable borrowed items, drops the old plan, checks that the training square is still accessible, and returns before choosing new work. It will not repeat a spent portion or claim another action's empty can. When the game reports two failed paths home, the final try can use the survivor's saved ground position on the same tile rather than its center. It never changes the training tile or adds a fourth attempt.

You can start training while seated on furniture. AutoMindful waits for anyone else's action, uses the game's get-up action and waits for it to finish before sitting on the floor for meditation. If Lifestyle still owns the seat, AutoMindful waits for you to leave it normally.

When training stops or reaches its target, a small click-through HUD card shows the elapsed session time and any measured progress, even if the AutoMindful window is closed. If Lifestyle's XP data cannot establish an exact gain across a level change, the card reports the level change instead. Care breaks and supply trips do not end the session. The card fades after about four seconds; open AutoMindful for the full stop reason or pending returns.

Meditation needs sitting on the ground and cannot start above Lifestyle's boredom limit. Yoga needs standing and may require a complete two-tile mat. Native exhaustion, embarrassment, injuries, unsafe surroundings, and missing essentials can limit what the survivor can do. AutoMindful uses normal game time and XP rates; reaching both level caps can take many game days.

**Meditation** targets only Meditation ranks, and **Yoga** targets only Yoga ranks. Either skill may still be used for care. A single-skill loop stops with its blocking reason if care cannot make that skill available. **Train both** has three cycling choices, under **Settings**. A change applies at the next safe decision:

- **Alternate** (default): switch after a completed practice.
- **Lowest progress first**: prefer the skill with less progress, counting its level and the fraction of the next level earned.
- **Closest to level 10 first**: prefer finishing the more advanced skill, then train the other.

The window shows the next owed skill and Lifestyle's current blocker when it is known.

Low endurance does not block Meditation. In Yoga training, AutoMindful may meditate while the native Lifestyle menu reports that low endurance blocks Yoga, if Meditation is available without a gear change. It stops that fallback at the first eligible check, then yields to the queue and returns to Yoga when safe. If another native requirement takes over, the fallback ends. Train Both retains its bounded interim Meditation while the owed Yoga turn waits. No extra AutoMindful endurance cutoff is used. Fatigue that requires sleep is a separate care condition.

**Practice for relief.** With supported Lifestyle settings, AutoMindful can take a separate Yoga or Meditation care break. It prefers suitable immediate supplies and checks the current rank and native requirements without dropping or removing gear. Recovery can use Basic Mindfulness for panic, Strong for pain, and Perfect for stable health loss when native healing is available.

If no usable food is confirmed, eligible Meditation can build Strong Mindfulness for hunger starting at the first hunger moodle. Strong Mindfulness requires Meditation rank 6. An active Strong or Perfect tier can ease hunger, but neither adds calories or water. AutoMindful checks for an actual drop in hunger instead of treating the moodle tier as proof. Available food and safe water take priority. An unreachable water source does not rule out otherwise eligible Meditation for hunger. Care does not use up a Train Both turn. Turn off practice-based relief in Mod Options if you do not want Yoga or Meditation used for care.

**Practice at max rank:** Start **Train Both** after both skills reach level 10 to alternate Yoga and Meditation while idle, regardless of training order. If only one is maxed, Train Both still trains only the unfinished skill. Start **Yoga** or **Meditation** at its cap to practice only that one, with the usual optional care breaks. Max-rank practice leaves room for other actions and pauses for them; it does not require XP gains. A training session started below the cap switches to Recovery once its selected skill, or both skills in Train Both, reaches level 10. Unfinished hunger relief is not cut short by a level-up or by full endurance. Unlike Recovery, max-rank practice does not need an active care need to start a session.

**Recovery** looks after the survivor without training. It works at any rank and has three gears, which it picks by itself:

- **Working:** while you, or another mod, keep the action queue busy, a carried bite or sip goes between two actions. Nothing of yours is cancelled, replaced or reordered.
- **Here:** while you stand around, it eats and drinks what is within reach. The longer the survivor is left alone (mouse, keyboard and movement all count), the more it does: a walk for a second moodle after 5 seconds and for a first one after 15, resting, reading and practising for relief after 10, sleep after a minute.
- **Away:** after 3 minutes without input, or at once with **I am going AFK**, it does everything: small needs, a nearby bed and back, filling carried bottles, looking into containers. A step, a key or an aim ends it.

**Danger** comes in degrees. Chased, touched or on fire: hands off. Zombies only in view: no walking, practice or sleep, but eating, drinking, bandaging and a painkiller go on, and someone dying of thirst may still walk to water. Bleeding is bandaged with what is carried or within reach, best dressing first. In a parked vehicle it uses what you carry. The same rules stand behind every training job.

**Looking ahead:** while Recovery runs, the window shows how long the known food and drink would last in real time, carried and within reach, and what would go wrong first. Rates are measured on your survivor. When you leave with something that would likely kill an unattended survivor, it says so at that moment. Later trouble (starving with nothing to eat, zombies, a wound without a bandage, every walk failing) shows a card and plays a sound only you hear, again every few minutes while it lasts.

**It does not give up.** A route that will not settle, an interrupted action or an internal error makes Recovery back off and try again. **Stop** ends it; Escape only makes it step back. If it was on when you left the game, it goes on when you load in. It cannot reconnect you to a server.

**Last resort:** after a minute of Dying of Thirst with nothing clean left, it drinks plain unsafe water. It never eats rotten or poisonous food. Each of these is a switch under **Settings > Recovery**.

Recovery rests normally when endurance is low. Meditation does not directly refill endurance. Yoga and Meditation are used only when the current skill and benefit make them useful for a need; they are never training turns.

## Report a problem

AutoMindful writes what it decided and why to `Zomboid/Lua/AutoMindful/log-N.txt`: five files of up to 4 MB, newest session named in the **Log** tab. Each line has the time, the world clock, the job, the event, the reason, and the survivor's state at that moment: position, posture, needs with moodle levels, health, hands, load, nearby zombies, and the action queue with who owns each action. Trips include the destination's contents as known at the time; supply choices list every candidate with its score or the reason it lost.

Set the detail under **Settings > Log detail**. **Copy report** puts the current state and recent events on the clipboard. The console only gets a job's start, end, refusals and errors. Nothing is sent anywhere.

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
