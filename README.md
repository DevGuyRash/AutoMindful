# AutoMindful

AutoMindful automates meditation and yoga in Project Zomboid's [Lifestyle: Hobbies](https://steamcommunity.com/sharedfiles/filedetails/?id=3403870858) mod. It starts Lifestyle's own actions, takes recovery breaks, and resumes training toward level 10 in both skills. It does not award XP or change training rules.

This is a client Lua mod for Build 42.22 and later. Lifestyle: Hobbies must already be active. AutoMindful contains no server scripts. Build 42 normally replaces the client's active code-mod list on joining a server, so the server must advertise AutoMindful in its mod list for ordinary native loading. Lifestyle's server component must already support its normal actions and XP. AutoMindful does not install Lifestyle on a server or bypass a server's checks.

## Install and start

1. Copy `mods/AutoMindful` into your Zomboid user folder's `mods` directory. On Linux, the usual destination is `~/Zomboid/mods/AutoMindful`.
2. Enable Lifestyle: Hobbies and AutoMindful for your game. Restart the client after installation.
3. Choose a safe training spot. If the server or sandbox requires a yoga mat, stand on a complete, deployed mat.
4. Right-click the world and choose **AutoMindful**.
5. Select **Check supplies**, then **Train both**, **Meditation**, or **Yoga**.

The window shows both skill levels and the current activity or reason training cannot continue. Closing the window keeps training running. Use **Stop training** to cancel. Training starts only when you request it; loading a save never starts it automatically.

## Prepare supplies

Bring ready-to-eat safe food, bottles of clean water, and unread books, magazines, comics, or other literature that reduces boredom. Use a lit place so the character can read at night. Open cans and prepare food before starting. Skill books and already-read stories do not provide a reliable supply of boredom relief. An illiterate character needs readable picture literature or another available way to relieve boredom.

Enable **Use supplies in reachable adjacent containers** to let AutoMindful take useful supplies as needed. Collection is off by default. It uses the game's reachable ground and storage inventories around your current square, checks carrying capacity, and transfers one item at a time. It does not search distant rooms, walk a looting route, or collect another player's inventory. Put provisions beside your training mat for a long session.

Yoga itself reduces boredom and pain when successful, so it can help meditation training without consuming literature. At low levels yoga can fail and cause embarrassment. Recovery and repeated sessions are part of normal progression. Food and water totals in the checklist count items, not the number of days they will last.

## Understand the training loop

Meditation is a normal perk. Yoga is Lifestyle's separate hidden skill. AutoMindful reads each through the corresponding native API. It uses Lifestyle's current level-specific action selection instead of copying pose tables, XP formulas, or animations.

Meditation requires sitting on the ground and cannot start above 30 boredom. Yoga requires standing, can require a complete two-tile mat, and has configurable exhaustion and embarrassment limits. Interrupting yoga early can remove some session XP. AutoMindful lets yoga finish naturally except when you cancel or safety requires stopping. See [the upstream source notes](docs/upstream.md) for the exact lifecycle and dependencies.

Keep the character safe, clothed, and supplied. Automation cannot guarantee safety in a changing world or cure injuries, infection, temperature problems, or unavailable server actions. Long training uses the game's normal passage of time and XP rates and can require many game days. A missing essential provision or an unrecoverable condition stops training with a reason.

## Build

Python 3.10 or later and `luac5.1` are development tools. The installed mod needs neither.

```sh
python3 tools/build.py
```

The build checks every runtime Lua file and creates `dist/AutoMindful-0.1.0.zip` with a `Contents/mods/AutoMindful` layout and a SHA256 manifest. Only the `mods` tree goes into the archive. Upstream game and Workshop content stay in their original installations.

See [verification](docs/verification.md) for repeatable checks and the tested scope.
