# Rod fishing

> **Reworked 2026-10-27 (branch `fishing-yank`): the fight is gone.** Even its designer found the
> fight too hard to play, so a hooked fish is now one big moment instead of a tug of war. The take
> (R2) is loud: the float is dragged right under with a plunge, a zinging line and a bell
> (`hooked`), a burst of spray, a big "!" over the float, the rod bent hard and thrumming. Click
> inside the strike window (now 0.6 s perch .. 0.42 s salmon, still level-scaled) and the fish is
> **yanked out** (`yank`: hit-stop, shake, spray), flies over in a tumbling arc on the line
> (`LandedFish`), lands on the bank ~2.6 m beside you (the view eases round to keep it on screen),
> flops a few times (`flop`) and lies there glinting until you walk up to it. Late: "Too slow", it
> spits the hook and the float stays out. R3 (fight), R9's landing flashes / Clean, R10's rooting,
> look tug, notches and prompt assist, and R6's pike steals are gone; `FishFight` is deleted
> (its level scaling lives on as `FishBite.window_scale`). R11's +1 notch perk became
> *Sharper eyes*: 25% longer to pull. Cast (R5), bite rhythms (R2) and rivers (R7) are unchanged.
> Everything below is the original design, kept for the record.

Branch `fishing` (off `main`), one commit per phase, then a PR. Spearfishing stays as it is; the rod
is the second way to fish, sharing the Fishing skill.

The pitch: **reflexes and timing, not balancing a bar.** Every phase is a timing beat read from
the world (sound, the float, the rod, the water), never a button prompt:
cast (time the release) → bite (read the nibbles, strike on the take) → fight (answer each
telegraphed move) → land (grab on the flash).

## Decisions (grilled 2026-10-19)

| # | Topic | Decision |
|---|-------|----------|
| R1 | Role | The rod owns **deep and far water**: the lake's middle, rivers, the bank. Some species are rod-only (char, grayling, salmon). The spear stays best for shallow schools (multi-catch). Same Fishing skill. Pond fish (perch, trout, pike) bite the rod too. |
| R2 | Reading the bite | A **float plus sound**, the fish only a dim shadow when close. **Nibble** (small twitch, soft *plip*: a fake-out), **tap-tap** (two quick twitches: about to commit), **take** (float dunks, *bloop*, line twang): strike inside a short window (~250 ms perch → ~120 ms pike). Each species has its own tell rhythm (trout nibble fast and impatiently; pike sit still, then slam with no warning). **Striking early spooks the fish** (it leaves). |
| R3 | Fight | Telegraphed moves, each with its own answer. **Pull** (rod creak, steady tug): hold LMB to reel = progress. **Run** (line hiss rises, shadow streaks): release LMB before it bolts. **Headshake** (rod tip jerks 2–3× in rhythm): click on each jerk. **Jump** (water bulges, then a splash): RMB to *bow* (drop the rod tip) on the splash. Progress is a **distance** (how far the fish is), not a tension bar. **3 line notches** (lives): a wrong or late answer costs one, three and it snaps. Species set the mix and tempo; moves come in a random order (react, don't memorize). |
| R4 | Getting the rod | **Distance decides**: water within spear reach (2.8 m) → spear; water beyond it, up to cast range (~14 m, a little more with level) → rod. Once cast, the rod is **locked in hand** until you reel in or the line snaps. |
| R5 | Cast | Aim with the crosshair. **Press** = back-cast, **release on the forward stroke**: a sweet spot (rod tip passing an angle, a *whip* cue). Perfect: lands on the aim point with a soft *plip*, no scare, fish a little curious. Early/late: scatters off target by the error and lands with a *splosh* that spooks fish nearby. Casting **right on top of a school** spooks it even when perfect: lead the fish. |
| R6 | Who bites | **Real fish.** The lure is something fish notice: a calm fish within its species' notice radius breaks from its school, swims to the lure and plays its tell rhythm. That fish is the one hooked, dragged through the water during the fight; its school scatters. **Pike ambush** the lure (no nibbles). A small fish on the line can get **stolen by a pike** (the pike is then on the line). |
| R7 | Rivers | **Grayling** (Fishing 15): hold station facing upstream in the current, spread out; cast *upstream* and let the float **drift** down to them. **Salmon** (Fishing 40): rare, 1–2 per river, in deeper pools at bends; the showpiece fight (jumps, big runs). **Char** gets a fight profile (long deep runs). River fish are very skittish to wading (big scare radius, low nerve), so the spear is allowed but bad there. |
| R8 | Under-levelled | **It bites and you can try.** Windows scale with the level gap: each 10 levels above widens them ~10%; below, they shrink sharply and telegraphs shorten (~5 under: hard but possible; 15+ under: near-impossible, the line snaps with a "Fishing N" hint). An under-level catch gives +50% XP. |
| R9 | Landing & payoff | At your feet the fish thrashes; a **landing window** opens on a rhythm (it flashes side-on): click on the flash to hoist it (hit-stop, rod bend, spray, the flip into the inventory). A miss = one more thrash, costs a notch (if it's the last: it escapes at the very end). **Clean** (no line damage): "Clean!", +25% XP. **Perfect** (clean + perfect cast + strike in the first half of the window): "Perfect!", +50% XP, stronger feedback. Each catch rolls a **size** ("Salmon, 4.2 kg"): bigger fish fight longer and give more XP. **No consumables** in v1 (no bait, no lost lures). |
| R10 | Body & screen | **Rooted, free look** once hooked: WASD barely shuffles (< 1 m/s), no jumping. The rod **tugs your aim toward the fish** (gentle drift on runs, a hard tug on a jump): keep it framed, the cues are partly visual. **Minimal HUD**: only the line notches near the crosshair. All telegraphs diegetic. Optional **prompt assist** (a small icon per move), off by default. |
| R11 | Village | Fisher perks carry over: *calmer fish* also means a bigger notice radius and fewer fake nibbles; the top tier adds **+1 line notch** (its "bonus fish" makes no sense on a line). New fish become items with models and icons. One rod, no tiers. |

### Changes found while building

- **Rivers exist only in generated (procgen) worlds**; the hand-built main world has ponds and the
  lake but no river. So grayling and salmon can't be in the fisher's upgrade costs without locking
  the main world's progress; the rod-only fish in the costs is **char** (main lake). Grayling and
  salmon are for the procgen worlds (and future costs once the main world has a river).
- **Windows sized for human reactions** (~200 ms to see and click), not the bots': the strike
  window is 300 ms (perch) down to 200 ms (pike, salmon), not ~250 → ~120 ms. What makes the
  harder fish harder is rhythm you have to *anticipate*: the take comes a steady beat after the
  tap-tap, a headshake counts in on its own beat (creak, tremble, jerk, jerk...), and the jump's
  splash lands as the bulge peaks. Bows and jerks: ±160 / ±100 ms round the cue.
- **Fight length** comes from net progress per move (pulls reel in, runs give back only 30% of
  their speed): a 9 m fight takes a good player ~7 s for perch, 14–20 s for trout, grayling,
  pike and char, ~25 s for salmon (tools/test_fishing.gd prints it).
- **The float is drawn 1.8× life size** so its twitches read at 10 m.
- **No settings menu on `main`** (it's on the unmerged `menus` branch): the prompt-assist toggle
  lives in `user://settings.cfg` (`[gameplay] fishing_prompts`) and the debug menu's Player tab;
  move it into the Settings screen when `menus` lands.

## Architecture

- `scripts/rod_fishing.gd` (`RodFishing`, a child of the Player like `SpearFishing`): targeting,
  the state machine (idle → back-cast → flight → waiting → fight → landing), input, the rod
  viewmodel and its bend, the line, look tug, HUD notches, prompt assist, sounds.
- `scripts/fishing_lure.gd` (`FishingLure`): the float in the world. Drifts with the water's flow,
  draws fish (notice), runs the bite (approach, tells, take window), reports strikes.
- `scripts/fish_fight.gd` (`FishFight`, RefCounted, pure logic): the move sequence, windows,
  distance, notches, landing flashes; fed time and input, so it can be tested headless.
- `scripts/rod_cast.gd` (`RodCast`, pure): judging a release (timing error → quality, scatter,
  loudness).
- `FishSpecies` gains *Rod* (notice radius, nibbles, tell gaps, strike window, ambush, front-only),
  *Fight* (move weights, tempo, run speed, reel speed), *Size* (kg range) and *River* (holds
  station) groups. `WaterBody.flow` (m/s, downstream) for rivers.
- `FishSchool`: fish engaged by a lure are steered by it; station-holding (grayling); hand back
  escaped fish.
- Procgen: river pools at bends, river stretches stocked (grayling; salmon in pools), flow set.
- Models: rod (three bendable sections + reel), float, grayling, salmon; icons for the new fish.
- Sounds: `tools/synth_fishing.py` → `audio/fishing/` (cast whip, plip, splosh, nibble, bloop,
  line twang, hiss, reel click, rod creak, snap, jump splash, landing splash).
- Tests: `tools/test_fishing.gd` (headless, pure classes only: never touches a save).

## Phases

1. **Rod & cast** — rod model + viewmodel, equip by distance with the lock, timed back-cast and
   release, float flight and landing (plip/splosh, spook nearby, on-top-of-school spook), reel in.
2. **Bite** — notice, approach, species tell rhythms, strike window, early strike spooks, pike
   ambush, river drift.
3. **Fight** — FishFight moves with telegraphs, distance, notches, rod bend, look tug, rooted
   movement, the hooked fish dragged through the water, pike steals.
4. **Landing & payoff** — landing flashes, Clean / Perfect, size rolls, popups, XP, under-level
   scaling.
5. **Rivers** — pools, stocking, grayling holding station, salmon, char profile, flow, skittish
   river fish.
6. **Village & polish** — perks (notice/nibbles, +1 notch), items, models, icons, upgrade costs,
   prompt assist, the synthesized sounds, README / TODO / research notes.

All tuning numbers are exports on `FishSpecies` (`data/fish/*.tres`) or `RodFishing`, so they can
be tuned by feel.

## Status (2026-10-19)

All six phases built on `fishing`. Verified by bots only: `tools/test_fishing.gd` (every species
landed cleanly by an answering bot, always snapped by a lazy one) and `tools/fishing_playtest.gd`
in the real game (lake: 5/5 landed, trout and char; a generated world's river: grayling via the
drift, salmon from the pools). **Not yet played by hand or listened to**: see docs/TODO.md.
