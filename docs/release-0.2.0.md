# AutoMindful 0.2.0

The window, the right-click menu and the log are new.

- **Right-click:** one AutoMindful entry beside Lifestyle's own Wellness actions, listing only the jobs that apply, with reasons for blocked ones and submenus for tiers. While a job runs it appears on your survivor with Stop and Switch to. A yoga mat offers Train Yoga here. Elsewhere, nothing.
- **Window:** tabs for Now, Supplies, Log, Guide and Settings. It fits its contents, shows active needs only, switches jobs without stopping, and shrinks to one line. Settings apply as you click; the separate settings window is gone.
- **Supplies:** one choice of how far care may reach replaces two overlapping switches.
- **Log:** decisions, actions, candidates, containers, objects and the survivor's state go to `Zomboid/Lua/AutoMindful/log-N.txt` instead of flooding the console. Copy report is in the Log tab.
- **Interruptions:** a practice is only broken off for the second hunger or thirst moodle with a confirmed supply. The first moodle used to forfeit Yoga XP, even to look into unknown containers.
- **Trips:** failed sources are not retried on a timer, a room that cannot be entered is given up after two tries, the next known source is tried on the way, and blind searches back off. A critical need with nothing known now searches nearby containers instead of waiting.
- **Pauses instead of stops:** nearby zombies, bleeding and fire pause training. A brief right-click no longer ends it. Stalled care, vehicles that move and awkward tiles no longer end the session. Fast-forward during a walk no longer cancels it and is restored afterwards.
- **Fixed:** low-health loop that returned a borrowed item forever instead of drinking; hunger suppressing the search for water; carried drinks banned for the session after one late server receipt; hunger Meditation cutting itself short over boredom; misleading "no food" reasons; the permanent yoga mat warning.
- **Care:** toilet visits never use bandage rags, notes or cash. Canned food counts when the opener is in the same cupboard. Equal meals prefer no unhappiness, then what spoils first.
- The loot window is no longer refreshed every second.
- Two modes that nothing could start (endurance meditation, recover to full) are removed. Recovery covers both.
