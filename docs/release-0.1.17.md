# AutoMindful 0.1.17

- Character Info > Skills shows the available benefits for hovered Meditation and Yoga ranks in plain language. The tooltips preserve native XP, locked state and boosts. Yoga uses Lifestyle's own progression and only shows a non-neutral XP setting when the survivor can still earn XP.
- On the checked Lifestyle 0.4.0.3 implementation, the Yoga tooltips can show a nominal pose limit and how long Zen normally lasts after successful Yoga. The lifetime depends on the rank at which the action started and on when it finishes between in-game ten-minute ticks. It is not a live countdown or a guarantee of an exercise XP modifier.
- Open **Skill Guide** in the AutoMindful Progress section for Mindfulness, Strong Mindfulness, Perfect Mindfulness, Yoga, Zen and lessons. Training controls stay available. The guide distinguishes each current Mindfulness tier's countdown from its normal per-tier duration.

The mod reads available upstream descriptions at hover time. Unverified Lifestyle versions keep available descriptions rather than receiving unverified duration or pose-limit numbers. There are no gameplay stat writes or new dependencies in this change. See [verification](verification.md) for the separate in-game visual, scaled layout and AllTheInfo checks.
