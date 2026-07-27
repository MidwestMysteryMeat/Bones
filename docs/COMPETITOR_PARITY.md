# Table UX parity notes

Research pass: 2026-07-27. Bones is play-money entertainment, so these are UX
references rather than monetization or real-money casino requirements.

## Shipped in the responsive table pass

- Dedicated, clipped dice lane with physical 3D motion and stable landings.
- One responsive layout for status, bets, dice, help, chips, and actions.
- Point objective plus an ON/OFF puck that cannot leave the viewport.
- Recent-roll strip with special treatment for sevens and doubles.
- Contextual bet rules and live payout labels on hover.
- Adjustable dice animation speed; screenshake can already be disabled.
- Results stay hidden until both dice physically settle.
- Existing interactive practice dice and full bet reference remain available
  under HOW TO PLAY.

## References and remaining high-value parity work

| Reference | Useful pattern | Bones status |
|---|---|---|
| [Dicey Dungeons 0.15](https://diceydungeons.com/blog/2018/12/25/version-15.html) | Tooltips, previews, animation-speed controls | Tooltips and dice speed shipped; bet-result preview is next |
| [Slice & Dice on Steam](https://store.steampowered.com/app/1775490/Slice_Dice/) | 3D dice physics, undo, many modes, leaderboards and achievements | Physics, modes, leaderboards and achievements exist; bet undo needs rules work |
| [Evolution First Person Craps](https://games.evolution.com/first-person/first-person-craps/) | Interactive tutorial and “My Numbers” potential-payout display | Tutorial exists; potential-payout panel is next |
| [Evolution Live Craps launch](https://www.evolution.com/news/evolution-launches-worlds-first-online-live-craps-game) | Reduced-complexity Easy Mode | Backlog: beginner layout that hides proposition bets |
| [Electronic craps game description](https://wsgc.wa.gov/sites/default/files/2025-02/Craps_Crapless_Craps_Easy_Craps_game_description_Washington-specific_v2.5.1_0.pdf) | Last results, clear, double, repeat, keep-bets controls | Recent results shipped; bet-management controls need engine support |
| [Balatro on Steam](https://store.steampowered.com/app/2379780/Balatro/) | High-contrast visuals, reduced effects, controller support | Screenshake toggle exists; high-contrast mode and full focus navigation remain |

Priority order for the next table pass:

1. Clear/repeat/double controls with correct contract-bet rules.
2. “My bets” exposure and potential-payout preview.
3. Easy Mode plus first-run guided bet placement.
4. UI-scale/high-contrast settings and full controller focus navigation.
