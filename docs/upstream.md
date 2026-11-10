# Lifestyle action and recovery reference

AutoMindful targets Project Zomboid Build 42 and Lifestyle: Hobbies with the hidden Yoga skill. The traced official Workshop item is [Lifestyle: Hobbies](https://steamcommunity.com/sharedfiles/filedetails/?id=3403870858), mod ID `LifestyleHobbies`, installed version `0.4.0.3`. Source paths below are relative to Lifestyle's `common/media/lua/`. These files remain in the user's Workshop installation and are not copied into AutoMindful.

## Native entry points

`client/ISMeditation/ZenWellnessContextMenu.lua` owns the active meditation and yoga menus. `ZenWellnessContextMenu.Options.Meditation.onAction({}, option, player)` and its Yoga equivalent select the current skill, animations, duration, bonuses, and sandbox options. Their `canPerform` functions report current gates. `ZenWellnessContextMenu.isValid` rejects death, a busy action queue, a vehicle, sleep, or furniture seating. Meditation requires sitting on the ground. Yoga requires standing.

The older `MeditateContextMenu.lua`, `YogaContextMenu.lua`, and `YogaSkill.lua` are deprecated. They do not define the active yoga progression. The short client timed-action files are also deprecated. The actual implementations live in `shared/TimedActions/LSMeditateAction.lua` and `shared/TimedActions/LSYogaAction.lua`.

AutoMindful calls the active menu entry points rather than reproducing their level tables or constructing replacement training actions. It uses the same upstream bag removal and heavy-item handling as manual training. Bags remain in your inventory after unequipping. Restore equipment yourself after the routine.

## Meditation

Meditation is `Perks.Meditation`. The context menu rejects boredom above 30. During the action, normal stat updates increase boredom and neck pain at low skill. Boredom above 10 raises aversion, which reduces XP and worsens boredom or pain. Low boredom, skill, the Disciplined trait, higher meditation focus, mindfulness, being taught, and Yoga's Zen effect influence upstream results. Boredom is a menu gate rather than an automatic stop check inside `LSMeditateAction:update`.

The native action stops when the player aims, enters a vehicle, moves, runs, or receives `IsMeditationDisturbed`. `client/LSIsListeningEffects.lua` can mark meditation disturbed and enqueue `ToneDeafSuffering` when disliked music interrupts a player without Disciplined. The native action clears its disturbed flag during stop. Meditation stops restore held items and stop its sound. Its periodic stat updates award Meditation XP through Lifestyle's existing command handler, and normal completion awards a final update.

AutoMindful takes a care break at boredom 20, before the menu's hard gate. It reads useful leisure literature, or practices normal yoga when reading is unavailable. It resumes meditation through the same upstream entry point after recovery. Reading never substitutes for meditation XP. A player-supplied action or persistent external disturbance stops the routine and reports the reason.

## Yoga

Yoga is a hidden skill, not `Perks.Yoga`. `client/Helper/HSMng.lua` owns `HiddenSkills.getSkill`, `getLevel`, and progression. The current skill tuple is `{level, currentXP, XPForNextLevel}`. Thresholds for levels 0 through 9 are 100, 250, 500, 750, 1000, 1250, 1750, 3000, 4000, and 9000 XP. Upstream requires XP to exceed a threshold to level up and carries the overflow. AutoMindful reads this state and never writes it.

The yoga menu checks `SandboxVars.Yoga.RequiresMat`, `Exhaustion`, and `Embarrassment`. A required mat must already be deployed under the player's square as the complete matching two-tile native yoga mat. Carrying a rolled-up mat does not satisfy the native check. The exhaustion setting can disable its gate or require endurance above 0.8, 0.6, or 0.3. The embarrassment setting can disable its gate or block at moodle level 1, 2, or 3. AutoMindful calls `canPerform` to honor those choices.

Each completed pose awards XP and normally reduces boredom by 5, pain, stress, and stiffness. A random pose failure can end the session with embarrassment and no XP for that pose. Normal completion can award bonus XP and Zen. The next session works through the native action again at the new level. Stopping early can remove earned Yoga XP and some Zen. AutoMindful normally lets yoga finish, even when a selected skill reaches level 10 mid-session. An urgent survival need or explicit cancellation can still interrupt it and incur the normal penalty.

Yoga's embarrassment fades through the existing `client/LSEffects/LSPerMinute.lua` updates. AutoMindful waits for that recovery if it blocks yoga, and meditates while yoga is blocked when the selected mode and boredom allow it. It sits on the ground to recover endurance before the next session. It does not reset embarrassment, make poses succeed, skip cooldowns, change multipliers, or reduce XP thresholds.

## Survival and supplies

The installed game's `shared/TimedActions/ISReadABook.lua`, `ISEatFoodAction.lua`, `ISDrinkFluidAction.lua`, `ISWaitWhileGettingUp.lua`, and native inventory transfer utility supply the existing client actions. AutoMindful runs one batch at a time and uses their ordinary inventory, duration, animation, item-consumption, and multiplayer behavior. Hydration uses the current fluid-consumption action because the older `ISDrinkFromBottle` path refers to a missing thirst packet constant in the tested Build 42.22.2. It waits when the native fluid action's fullness check prevents drinking.

Useful literature has a negative boredom change and is not a skill-training book or an Uninteresting item. Illiterate characters can use picture books and pictures that native reading permits. Already-read named titles and print media are excluded because native `ISReadABook:complete` skips their morale benefit. Each selected piece is attempted at most once per routine, even if an upstream item lacks a unique title. Native print media may open its normal reading window.

Food must be ready to eat, unsealed, unfrozen, unburnt, unrotten, untainted, nonpoisonous, and nonalcoholic. Dangerous raw food and food requiring another item are excluded. Open canned food, cook unsafe ingredients, and thaw meals beforehand. Hunger and calorie checks both matter during a long routine. Foods with substantial calories help sustain repeated yoga sessions. Boredom-reducing food can also help indirectly, through its normal effects.

Drinks are unsealed, portable containers of pure, clean water with capacity at most 3 liters. The normal bottle action consumes water. The routine does not use tainted fluids, mixed drinks, alcohol, plumbing, cooking, or refill recipes. Keep enough water available for the whole run.

Optional nearby collection uses the game's current adjacent loot containers, on the same floor and within one square. The native synthetic ground inventory has no container square, so dropped supplies use each world item's actual square. Native loot discovery still owns reachability. AutoMindful checks inventory room and transfers only the next needed item. It does not walk, open doors, search a building, deploy mats, empty other containers, or collect from inaccessible distant storage. Supplies inside carried bags are available without opting into nearby collection. Supply inspection reports usable items in inventory and optional adjacent loot separately.

When ordinary fatigue reaches 0.6, AutoMindful uses `ISWorldObjectContextMenu.onSleepWalkToComplete` to sleep on the current floor. That native function checks nearby zombies, pain, and panic and performs the game's ordinary sleep handling. AutoMindful also respects the normal one-hour sleep cooldown. It waits through sleep and resumes after waking. On servers with `SleepNeeded=false`, it does not invent a fatigue requirement. A server that requires sleep but disables it produces an explicit stop. A floor sleep is less comfortable than a bed and can cause the game's normal effects. A pillow on the training square or in hand improves the native floor-sleep category.

AutoMindful stops for movement, aiming, entering a vehicle, dragging a corpse, death, fire, bleeding, nearby visible or chasing zombies, health at or below 50, missing essential supplies, or repeated failed actions. It does not heal injuries, fight, smoke, take medicine, manage Lifestyle hygiene or toilets, or override sleep restrictions. Severe pain and panic can require recovery before sleep. A safe, quiet, lit training spot and sufficient provisions are necessary for unattended progress. Ordinary world threats can still make training unsafe.

## Client and multiplayer behavior

AutoMindful contains client Lua only. Lifestyle must work normally in the session. Its own native actions still own XP, hidden-skill synchronization, mood changes, animations, and any commands sent to the server. AutoMindful adds no server command, XP grant, fake item, or checksum bypass. Build 42.22 normally reloads the server's advertised code-mod list during connection, so ordinary native multiplayer loading requires the server to list AutoMindful. Listing the mod does not add executable server code. The server can also reject the underlying actions according to its configuration. Client-only packaging does not override the server's authority.

Selected skill goals are level 10. Both mode alternates training when useful and uses yoga's boredom and pain recovery while Meditation remains unfinished. A single-skill mode can use Yoga as a normal boredom-recovery activity if reading is unavailable. Missing mats or a zero upstream XP multiplier cannot be repaired by automation. The routine reports blockers and stops after six accumulated game hours spent training with no observed XP change, across repeated sessions. Care breaks do not count as training time.
