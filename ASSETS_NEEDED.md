# Assets needed

**Short answer: nothing is required. The game is fully playable, silent, straight from
a clone — `love .` and it runs.**

The repo tracks **zero media files** (all 59 tracked files are text: Lua, Markdown,
`.gitignore`, `LICENSE`, `FUNDING.yml`). Every visual is drawn with `love.graphics`
primitives, every font is LÖVE's built-in Vera Sans, and the two particle textures are
generated in memory at runtime.

**There are no unguarded load sites.** A missing-asset crash is structurally impossible
here: the only file-path loads in the codebase are both wrapped in
`love.filesystem.getInfo` checks (`src/audio/sfx.lua:39-41`, `src/audio/sfx.lua:43-44`),
and `sfx.play` no-ops with a one-time console note when a cue has no source
(`src/audio/sfx.lua:52-60`).

What *is* worth documenting is that the **audio layer is already fully wired to 12
specific filenames that are not in the repo.** Drop those files in and the game has
sound with no code changes. That is the entire manifest.

---

## 1. Audio — 12 named slots, all optional, all currently absent

`src/audio/sfx.lua:12-25` declares the paths. On disk, `assets/sfx/` and
`assets/music/` exist as **empty directories** (git does not track empty dirs, so a
fresh clone won't have them — create them, or the `getInfo` check simply keeps
returning nil and the game stays silent).

| path/pattern | type | format | dimensions | used for | required/optional | fallback behavior |
|---|---|---|---|---|---|---|
| `assets/sfx/dice_rattle.ogg` | SFX | OGG Vorbis, `"static"` | ~0.5–1.5 s | dice shake as the throw begins | optional | silent; logged once |
| `assets/sfx/dice_land.ogg` | SFX | OGG Vorbis, `"static"` | ~0.2–0.4 s | each die settling — played per die with pitch `0.95 + i*0.05` | optional | silent |
| `assets/sfx/win_chime.ogg` | SFX | OGG Vorbis, `"static"` | ~0.5–1.5 s | a winning settle | optional | silent |
| `assets/sfx/lose_thud.ogg` | SFX | OGG Vorbis, `"static"` | ~0.3–0.8 s | losing settle, seven-out, elimination | optional | silent |
| `assets/sfx/chip_place.ogg` | SFX | OGG Vorbis, `"static"` | ~0.1–0.3 s | a bet is placed on a spot | optional | silent |
| `assets/sfx/chip_slide.ogg` | SFX | OGG Vorbis, `"static"` | ~0.2–0.5 s | **declared but never played** — see orphan note | optional | silent |
| `assets/sfx/streak_riser.ogg` | SFX | OGG Vorbis, `"static"` | ~1–2 s | win-streak riser; pitch ramps `min(2, 1 + streak*0.08)` (`sfx.lua:70`) | optional | silent |
| `assets/sfx/jackpot_fanfare.ogg` | SFX | OGG Vorbis, `"static"` | ~2–4 s | jackpot payout, BR kill, BR match win | optional | silent |
| `assets/sfx/unlock_reveal.ogg` | SFX | OGG Vorbis, `"static"` | ~1–2 s | shop unlock reveal | optional | silent |
| `assets/sfx/ui_click.ogg` | SFX | OGG Vorbis, `"static"` | ~0.05–0.15 s | button click — only 2 call sites today, see gap note | optional | silent |
| `assets/sfx/near_miss_whoosh.ogg` | SFX | OGG Vorbis, `"static"` | ~0.5–1.5 s | near-miss slow-mo; ducks music to 0.25 then recovers (`sfx.lua:74-78, 85-93`) | optional | silent |
| `assets/music/casino_ambience.ogg` | music | OGG Vorbis, `"stream"`, **seamless loop** | 1–3 min | looping background bed, volume-ducked on near-miss | optional | no music |

Mono is fine for the SFX; the music should be stereo. Use OGG — the paths are
hardcoded with the `.ogg` extension, so a `.wav` would need a code edit.

### Where each cue fires

| cue | fire sites |
|---|---|
| `dice_rattle` | `states/pve.lua:149`, `states/match.lua:70`, `states/battleroyale.lua:153`, `states/tutorial.lua:99` |
| `dice_land` | `states/pve.lua:177`, `states/match.lua:78`, `states/battleroyale.lua:167`, `states/tutorial.lua:107` |
| `win_chime` | `states/pve.lua:199`, `states/match.lua:96`, `states/battleroyale.lua:106` |
| `lose_thud` | `states/pve.lua:203`, `states/battleroyale.lua:119`, `:122`, `:140` |
| `chip_place` | `src/ui/hud.lua:294`, `states/match.lua:66` |
| `chip_slide` | — **orphan**: declared at `sfx.lua:18`, played nowhere |
| `streak_riser` | `states/pve.lua:200` (streak ≥ 2), `states/battleroyale.lua:115` |
| `jackpot` | `states/pve.lua:210`, `states/match.lua:102`, `states/battleroyale.lua:136`, `:144` |
| `unlock` | `src/ui/shop_ui.lua:166` |
| `ui_click` | `src/ui/shop_ui.lua:39`, `states/battleroyale.lua:415` |
| `near_miss` | `states/pve.lua:168` |

### Coverage gaps a future audio pass would want

These are real, already-firing game events with **no cue key at all**. Listed so a
sound designer doesn't have to re-derive them from the sim:

- **Craps table moments**: point established / puck flips ON, seven-out specifically
  (currently reuses `lose_thud`), bet rejected (`src/ui/hud.lua:261-264`),
  chip-denomination change (keys 1–4, `src/ui/hud.lua:279-286`), bet-lock countdown
  ticks (`info.lockClock`, `src/ui/hud.lua:545-552`).
- **Solo Run**: tier advance (`states/pve.lua:217-220`), bust / run end (`:221-223`),
  cash out (`:304`, `:328`, `:339`), achievement toast (`:214-216`).
- **Boneyard (battle royale)**: the mode emits 9 distinct event types in
  `states/battleroyale.lua:98-148` — `hit`, `break` (point break), `backfire`,
  `sevenout`, `pressure`, `armed`, `rake` (storm), `kill`, `win` — but only
  win/lose/jackpot are sounded. Kill currently reuses `jackpot`; player death reuses
  `lose_thud`. Each deserves its own cue.
- **Meta**: daily reward claim (`states/menu.lua:32-36`), shop purchase vs. equip as
  distinct from `unlock`, match-end standings.
- **Universal UI click.** `widgets.button` (`src/ui/widgets.lua:53`) has no sound hook,
  so roughly every button outside the shop is silent even with `ui_click.ogg` present.
  One `sfx.play("ui_click")` inside `widgets.button` would fix all of them at once.
- **Footstep-equivalent**: none — there is no continuous motion audio; the dice tumble
  (`src/fx/dice_render.lua`) is silent between rattle and land.

---

## 2. Visual slots where an image could substitute

Nothing here is needed. Everything visible is `love.graphics` primitives. Ranked by
how much art leverage you'd get for how little refactoring:

| slot | current drawing | file:line | asset that would drop in |
|---|---|---|---|
| **Particle coin** | 12×12 `ImageData`, pixels written by `mapPixel` | `src/fx/particles.lua:18-27` | one 12×12+ PNG w/ alpha — **zero refactoring**, swap the function body |
| **Particle spark** | 4×4 white `ImageData` | `src/fx/particles.lua:31-33` | one small white PNG w/ alpha — zero refactoring |
| **Table felt + rail** | solid green rect, woven diagonal lines, vignette layers, wooden rail rects (36 lines; comment at `:38` says "without a bitmap asset") | `src/ui/screen.lua:32-67` | one tileable felt texture + one rail strip — **cleanest single-image swap in the codebase** |
| **Puck (ON/OFF)** | two circles + centered text | `src/ui/hud.lua:313-333` | two small PNGs (white ON / black OFF) |
| **Chip selector** | 4 plain buttons with number labels; denominations `{5, 25, 100, 500}` (`src/core/config.lua:29`) | `src/ui/hud.lua:525-534` | 4 chip PNGs |
| **Buttons** | rounded rect + stroke + text; hover ×1.3 brightness, disabled ×0.4 alpha | `src/ui/widgets.lua:53-70` | one 9-slice image in 3 states covers every button in the game |
| **Panels / dock / status rail** | rounded rect + gold stroke | `src/ui/hud.lua:304-311` (used by `:338`, `:395`, `:457`, `:503`) | one 9-slice frame serves all four consumers |
| **Betting board (15 spots)** | rounded rects, hover brighten, gold stroke, text labels + payout detail | `src/ui/hud.lua:392-445` | board image needs 9-slice or per-spot quads driven by `hud.layoutFor` (`:98-232`) |
| **Roll-history badges** | circles color-coded (red 7 / gold doubles / green other) + number | `src/ui/hud.lua:479-496` | small numbered badge sprites |
| **Shop die swatch** | 30×30 rounded rect with a single 4 px pip — the crudest drawing in the game | `src/ui/shop_ui.lua:66-69` | per-die icon set, obvious win |
| **BR panels + HP bars** | rect frame, state-colored ring, HP bar as two rects w/ 3-stop color | `states/battleroyale.lua:215-285` | frame + bar sprites |
| **Title wordmark** | `config.TITLE:upper()` printed in Vera Sans — there is **no logo asset** | `states/menu.lua:59-60` | a logo PNG |
| **Fonts** | 5 sizes, all `newFont(<number>)` = built-in Vera Sans | `src/ui/screen.lua:22-26` | a `.ttf` in `assets/fonts/` (dir exists, unreferenced by any code) |

Text-only screens with no image slots at all: run summary and standings
(`src/ui/results_ui.lua`), leaderboards (`states/leaderboards.lua:17-73`), settings
(`states/settings.lua:14-65`), all 5 tutorial pages (`states/tutorial.lua`), lobby
panels (`src/ui/lobby_ui.lua:16-95`).

### Do not replace the dice with sprites without reading this first

`src/fx/dice_render.lua` is a software 3D renderer — a beveled cube of 6 faces + 12
chamfered edges + 8 corner triangles (`:179-239`), quaternion tumble, perspective
projection (`:281-288`), Lambert diffuse + specular (`:313-319`), 12-gon pips
(`:331`, layouts at `:241-251`), contact-shadow ellipse (`:606-607`). Die colours
already come from cosmetics (`cosmetic = { body, pip, glow }`,
`src/meta/dice_catalog.lua:18-21`), so **recolouring is supported without art.**

A sprite sheet would replace `dice_render.lua:616-659` but would **lose the continuous
3D tumble — the game's signature effect — and break `tests/dice_render_test.lua`**,
which asserts projected cube geometry, ballistic tumble, physical face-up detection,
and tray containment. `assets/dice/` exists as an empty directory but no code reads it.

---

## 3. Notes

- `.gitignore` is three lines (`*.love`, `.DS_Store`, `Thumbs.db`) — it does **not**
  exclude media. Any `.ogg` you add to `assets/` will be tracked by default. Only the
  packaged `.love` build artifact is ignored.
- `love.graphics.setDefaultFilter("nearest", "nearest")` is set at `main.lua:18` — if
  you add pixel art it will stay crisp; if you add smooth art, change that line.
- `assets/fonts/`, `assets/dice/`, and `assets/ui/` are empty and referenced by **no
  code path**. Only `assets/sfx/` and `assets/music/` have consuming code today.
- `lib/anim8.lua` contains the repo's only `newQuad` call (`:43`) but is **never
  required** — dead vendored code, not an asset dependency. Video is hard-disabled
  (`conf.lua:22` `t.modules.video = false`), so video assets are impossible without a
  conf change.
- The 5 headless test suites (`tests/*.lua`, run with `lua tests/<name>.lua` from the
  repo root) need no assets and pass at **130 assertions, 0 failures** on a bare clone.
