# TODO — parked for later

Open work only, in one place. When an item is done, delete it (git and `plans/*.md` keep the history).
Design background for most of these is in [3d-research-notes.md](3d-research-notes.md).

## Mood ([plans/mood-pass.md](../plans/mood-pass.md))

- [ ] **Tune the mood pass by eye** in the debug menu's Sky tab (F1 → Sky, Save writes `data/sky_look.tres`): sunrise/sunset palettes, noon softness, haze distance, the water mist, night brightness (the clearing under its trees is darkest). Checked from screenshots only.
- [ ] **Night length:** deep night is now about 2.5 min (was 5) because the twilight colours reach into it; see the plan's notes for the two levers.
- [ ] **Night darkness:** nights are much darker now; tune `DayNightSky`'s night ambient (0.32) and moonlight (0.24) by eye.

## Calm feel ([plans/calm-feel.md](../plans/calm-feel.md))

- [ ] **Play the calm feel**: stroll/jog speeds and the glide (`player.gd` *Ground*), whether gathering still feels satisfying without hit-stop (the stuck tool's `bite_hold`, `impact_kick`, `shake_break`), gentler popups, mantle heights (Player inspector: *Mantle*). Checked headless only.

## Fishing

- [ ] **Play the rod by hand** — reworked 2026-10-27 to *wait for the take, then pull* (no fight). The bot lands everything (tools/fishing_playtest.gd); tune the strike windows (0.42–0.6 s) and the hook moment's punch by feel: `data/fish/*.tres` *Rod* group, `RodFishing._hook_moment` / `_yank`. A strike up to 0.12 s before the take, after the tap-tap, hooks too (`FishingLure.EARLY_GRACE`).
- [ ] **Play the spear vs rod balance by hand** — the bench's pond numbers are even on XP (rod 292, spear 259 XP/min) but the spear lands ~3x the fish, because the bot never misses and walks straight to the next one. Fish a pond with each for ten minutes and compare; the levers are `SpearFishing.catch_xp` / `flee_catch` / `multi_xp_bonus`, `RodFishing.catch_xp`, and each species' `notice_rate` / `nibbles`. Schools' regrowth (`FishSchool`, 15–25 s a fish) caps the spear.
- [ ] **The fisher's tier 3** asks for pike and char, which now need iron fishing tools (smithy tier 3): check the building order still flows.
- [ ] **Listen to the rod's sounds** (`tools/synth_fishing.py`): every cue is synthesized and unheard; the cast whip, nibble vs. tap, and the take's `hooked` stinger carry the gameplay, so they have to be told apart by ear. `yank` and `flop` are new too. The old fight's sounds (hiss, bulge, strain, snap, thrash, hoist, reel) are unused now.
- [ ] **Faster regrouping** — scattered schools drift back together slowly (~1 m spread after 8 s); tune cohesion in `scripts/fish_school.gd`.
- [ ] **Skittishness tuning** — play-test `scare_radius`, `nerve`, `calm_down` per species in `data/fish/*.tres`.
- [ ] **Save fish?** — ponds currently start full on every load (deliberate); revisit if it feels exploitable.

## Water ([plans/water.md](../plans/water.md))

Swum once (2026-11-01); wakes and splashes not yet seen in motion.

- [ ] **Swim it more**: wave height, swim speed, breath (25 s), the float, how deep the lake reads, refraction strength (`water.gdshader` `refraction`), caustic brightness (`terrain.gdshader` `caustic_strength`).
- [ ] **Spear while diving vs the rod**: same catches and XP as the shore spear (`SpearFishing.under_reach` 1 m past the spear); bench it (`tools/fishing_bench.gd`) or fish the lake both ways and compare. Char now hug the lake bed (`swim_band`).
- [ ] **Listen to the swim sounds** (`SwimSounds` levels): strokes, the plunge, the hush under water (on Master, following the Ambience slider by hand), the gasp, climbing out.
- [ ] **Caustics on rocks** in the water (only the terrain has them).

## Woodcutting and logging ([plans/woodcutting-overhaul.md](../plans/woodcutting-overhaul.md), [plans/logging.md](../plans/logging.md))

- [ ] **Logging, unplayed:** headless-checked only (`tools/test_logging.gd`, `tools/test_logging_world.gd`). Not seen in motion: the layer colours in the notch, the slabs, the knot's look and whether it's easy to spot, the fall toward the notch.
- [ ] **Logging sounds:** the layer pop, knot crack and hinge crack reuse the clean-cut and creak stacks. Wanted from a CC0 pick (on a page): a wood slab popping free, a knot cracking open, the hinge splitting.
- [ ] **Dominoes vs Heartwood at `--human=0.7`:** +58% vs +27% (trees fall 60° aside of you now and crush more neighbours); fine at the default bot. Tune `CRUSH_SHARE` / `DOMINOES_LOGS` or `HEARTWOOD_CHANCE` after a playtest.
- [ ] **Playtest the chop feel** (bot-verified only: gallery stills, not seen in motion or played).
- [ ] **Tune the synthesized wood sounds by ear** in play (`tools/synth_wood_sounds.py`, each sound is one function; the stacks' levels are in `audio/woodcutting/*.tres`).
- [ ] **The Pinewood stand, play it** ([plans/pinewood-stand.md](../plans/pinewood-stand.md)): headless-checked only. Watch for the swap at 14 m (a copy becoming a real tree: an old-growth tree's shimmer pops in), stumps of felled trees seen from afar, and whether a forest gated at Woodcutting 25 (pines) feels like a wall of ghost outlines early on.
- [ ] **The stand's frame cost** (plans/pinewood-stand.md phase 5): `perf_census.gd` before/after and `perf_probe.gd` standing in and jogging through the forest. Needs a game window.
- [ ] **Talent model at level 40 with the whole forest:** Old growth +36% vs Momentum +16% (gap 16%, want 15%; 11% at `--human=0.7`). Seeded old-growth picks make it jumpy; look again after a playtest.
- [ ] **The notch on birch** shows less (pale cut wood on white bark); a darker cut colour for it if it reads poorly.

## Mining ([plans/ores.md](../plans/ores.md), [plans/crumbs.md](../plans/crumbs.md), [plans/mine.md](../plans/mine.md))

- [ ] **The fault, unplayed:** whether it's easy enough to spot in play (stills only), and whether the settle wants a quiet tick sound.
- [ ] **Iron, not yet measured or played:** swings to break it now (it no longer topples: `knock` 0, `shatter_at` 0.5, like copper), and how it sits next to the other ores in a real world.
- [ ] **Playtest the other ores** and tune: swings per ore (`knock`, `shatter_at` in `make_models.py`), how often you find the fault, ore spill rate, glint (`ore_roughness` / `ore_metallic` / `ore_glow`), the dirt patch on quarry sand.
- [ ] **Sounds** for knocking pieces out, collapses and faults still reuse the split and break sounds.
- [ ] **Crumbs, playtest:** unplayed and unheard. Dent size (CRUMB_KNOCK, WALL_KNOCK), how soon a piece crumbles (SKIN_SPENT 0.5, WALL_SPENT 0.25), whether the falling bits read as rock or as confetti, the dust amount.
- [ ] **Crystal close-up:** no crystal rock in the overworld for `ore_closeup.gd` (they're in the mine): its glitter is unseen.
- [ ] **Dig-face veins:** iron veins read almost white (the palette's `ore.iron` is pale silver), and coal veins on the weathered face read like black cracks.
- [ ] **No stone item:** stone pieces of a dig face give XP only; the game has no stone item or use for one.
- [ ] **The mine, play it:** bot-tested only, never seen in a game window. Guesses: how long a dig face takes (two layers, ~30 swings each with a stone pick), the seams' regrowth (15 minutes), the trophy chance per face (1 in 10), every project and add-on cost, the ride's 20 s, the lamp light, the mine's darkness and its fog, the sound levels. The pick hardness is a tier lower than planned (level 2 needs copper, level 3 iron): check it flows.
- [ ] **Play the shaft:** the cage is the inter-level lift's posts and boards (no walls or gate), the shaft's rock is the level's; the rope's creak is the lift sound.
- [ ] **Edda doesn't go down the mine** herself: she shores your fresh cells overnight and writes about what you find. Villagers can't walk the mine (no paths, a teleport in).
- [ ] **The fossil** has one look, not picked on a page, and hasn't been seen on the wall.
- [ ] **The mine's lights:** every shored cell can have a lamp (an OmniLight3D); only the level you're on is shown, but a fully open, shored level has ~15 lights. Watch the frame rate.

## Tools and levels ([plans/tool-progression.md](../plans/tool-progression.md), [plans/levels.md](../plans/levels.md))

- [ ] **Play it by hand.** Everything is bot-tested and screenshotted only: the gate and the under-level penalty (is the 40% floor, reached 10 levels under, too forgiving?), the recipe quantities (`Tools.RECIPES`, first guesses), and the cutscene's pacing (8.6 s; ~9.3 s real with the blows' hit-stops).
- [ ] **Listen to the forge and tool sounds** (`tools/synth_forge.py`): flare, drone, the three blows, hiss, reveal swell, thunder, bell, beam, shockwave, and the copper / iron / crystal rings. All unheard.
- [ ] **Greta's hammer pose** in the cutscene is the arm only (her work animation's hammer stays in her hand); a real hammer swing and the blank in her tongs would sell it more.

## Village, home and tavern ([village-design.md](village-design.md), [plans/home.md](../plans/home.md), [plans/tavern.md](../plans/tavern.md))

- [ ] **Villager rig:** real skeletal animation.
- [ ] **The home, play it:** bot-tested and Blender-rendered only, never seen in a game window. Costs, the visit rate, the note chance, well rested's size are guesses. The painted texture tiles (the kit's grain on our stone, wood and plaster) aren't seen in a window either.
- [ ] **Trophies, play them:** the rates are guesses (one about every hour or two); the feather and shell glint is a plain emissive mesh.
- [ ] **The tavern, play it:** bot-tested only. Tier and terrace prices, the dice styles, how long the evening runs, night walks home (an hour of night is ~36 s, so the walk takes most of one) are all guesses.
- [ ] **Saves while sitting:** a save taken seated puts you back on the seat's spot standing (inside the stool); harmless, but could stand you up first.
- [ ] **Villagers on the dice seat** play only against you; two villagers could play each other.
- [ ] **The keeper and Ollie have no house of their own** at the tavern (Maud "lives upstairs": she goes in at the door).
- [ ] **Stairs, play them:** walking the stairs and porch steps by hand (the step-up's feel, the eye easing up).
- [ ] **Small things left from the polish audit:** the two signposts' and the landslide mud's colliders reach 0.3-0.9 m past them; a villager standing in a doorway blocks it; the quarry's leaning pickaxe and torch have no collider; woodpile and firewood logs stack with 5-8 cm gaps.

## The dog ([plans/dog.md](../plans/dog.md))

- [ ] **Play him:** only bot-tested. Look at the poses (sit, lie, the wiggle, the shake), how close he keeps, whether the hints feel rare enough. His sound levels are untuned by ear in game.
- [ ] **Strays screenshot:** `dog_shots.gd`'s first view faces the pond, not the strays.
- [ ] **Small dogs in tall grass:** the terrier half disappears in the grass field.

## The road east and the market ([plans/market.md](../plans/market.md))

- [ ] **Play it:** bot-tested only. Barter prices, the wall's cost, how often she comes, the specials' prices are all guesses.
- [ ] **The trader's route** through the village ignores buildings and props (no collision on the cart): watch for it clipping the crates by the town hall.
- [ ] **The retaining wall goes up without a builder** (it's far from the village): a villager could walk out to build it.
- [ ] **The landslide's mud** is a prop on the road, not terrain: the road's surface paint runs under it.

## The world ([plans/world.md](../plans/world.md), [plans/world-pass.md](../plans/world-pass.md))

- [ ] **The land feels barren** (user, 2026-10-29): smooth now, but sparse. Later: more scenery and life between the places (groves, hedgerows, wildflowers along the creek, stone walls, lone trees on the hills, animals).
- [ ] **Roomier top-tier interiors** (world pass phase 4, not done): each house's top tier rebuilt toward the planned size (up to 10 x 12 m; they're 6 x 6 to 8 x 10 now) and refurnished, its seats, beds, spots and add-ons moved to suit (`tools/blender/kit_buildings.py`), then test_interiors, test_home, test_visits, test_day.
- [ ] **A little waterfall** where the creek leaves the north rim (world pass phase 6, not built), and reeds and stepping stones at the lake.
- [ ] **The new places' uses** (their own chunk): fruit from the orchard, wool from the shepherd's flock, flour from the mill for Rosa.
- [ ] **Fixture projects' effects**: restoring the barn, mending the granary and opening a cottage only change how they look; first guesses at a small effect each (plans/world-pass.md, "Open").
- [ ] **Walk it:** nothing here is played yet; only slope maps and headless checks. Look for odd road bends, the creek's banks, where the biomes fray, and the view from the rim hills.
- [ ] **The world pass is unplayed and unheard**: every animal call, birdsong and place sound has a first-guess level; walk it with the sound on and tune (`SoundSpot`, `Animal.KINDS`).
- [ ] **The picked rabbit, bunny, frog and pigeon are characters** (Quaternius, upright, with Wave and Punch): look at them in the game before using them as wildlife (phase 8), else simple models of our own.
- [ ] **Walks across the green take longer**: villagers walk briskly over 20 m (`Villager.BRISK`) and go further for the terrace and the tavern (`OUTING_RANGE`); watch test_day's timings and how it feels in play.
- [ ] **The haven at dusk**: check Fireflies finds its pool on its own (it looks for still water); if not, give the haven a cluster.
- [ ] **Hens hide in long grass** (they're life-size): clear the grass in the farm yard, or scale them up a touch.
- [ ] **Only one lone oak on the knolls** (place_country.gd wanted four): place more by hand in the map editor.
- [ ] **Biome cards vs ground:** `Biome.biome_at` still uses the plain shapes (ellipse, discs); the painted ground now uses warped ones, so a card can come a few metres early or late.
- [ ] **A "leaves" footstep set** for the forest floor (it sounds like grass for now).

## The map editor ([plans/map-editor.md](../plans/map-editor.md))

- [ ] **Buildings and places, play it** ([plans/map-editor-places.md](../plans/map-editor-places.md)): checked by moving the tavern, orchard and your home headless and putting them back; nobody has moved one in the editor and walked it. The first Save & bake after a move regenerates the land (bringing in the stale-terrain drift below).
- [ ] **`test_day` assumes the tavern by the green:** its evening (everyone sat by 21:48, home by 00:42) fails with the tavern moved far out. Scale its waits by the walk if the tavern ever moves for good.
- [ ] **Still fixed with the green:** the two drawn road lines (`WorldMap.VILLAGE_PATH`, `EAST_ROAD`) don't follow a moved green; the mine mouth, the quarry, the clearing, the creek and the lake don't move at all.

- [ ] **Use it:** lay out Hearthvale by hand (`python tools/map_editor/serve.py`, http://127.0.0.1:8765/), bake, play.
- [ ] **Not walked in-game yet:** the imported world bakes back the same counts and the tests pass, but nobody has looked at it in a window.
- [ ] **The Pinewood's core-to-edge slide** (pine in the middle, birch at the rim) became one average mix on import: split the forest into an inner and an outer patch to get it back.
- [ ] **The forest trail shifts a little** the first time the terrain is regenerated (the road router no longer steers round the old country's grove trees and rocks, only round the layout's points).
- [ ] **The committed terrain is stale:** `terrain_data/` is ~8,000 cells (up to 3.8 m, on the Frostpeak path and in the Pinewood) off what `tools/generate_test_terrain.gd` makes today (found 2026-10-30). Regenerate on purpose and walk those spots (it also brings in the pads under the village's south-east fixtures, plans/map-editor-places.md phase 4).
- [ ] **Hard-coded land** (the bowl, the clearing, the village flat, the quarry pit, Frostpeak, the existing roads) still lives in `generate_test_terrain.gd` and `WorldMap`; only new terrain shapes come from the editor.
- [ ] **Patch themes and rare looks** (NodeSpawner's `theme`, `rare`) aren't in the layout yet; nothing used them before either.

## Menus ([plans/menus.md](../plans/menus.md))

- [ ] **Playtest the menus by hand:** Continue / Play, the pause menu, Save & Quit and its picture, rename / duplicate / delete. Checked by `tools/menu_shots.gd` and the tests, not by playing.
- [ ] **Display settings in a window:** borderless, fullscreen and the window sizes weren't tried on screen.
- [ ] **Key rebinding** in Settings > Controls.
- [ ] **The debug menu's Graphics tab** duplicates Settings > Graphics; keep it or drop it.
- [ ] **Sound on the menu:** the backdrop is silent (no ambience or music).

## Look and sound

- [ ] **Playtest the look in motion:** grass parting and swaying, leaf flutter, the shake and fall of a leaf-card tree, felled-tree chips and leaf drops, lamp flicker. Only stills were checked.
- [ ] **README gameplay shots** (mining, woodcutting, spearfishing, pond) still show the old look; retake them.
- [ ] **Ghost outlines on leaf-card trees** (trees above your level) outline whole card quads, not the leaves.
- [ ] **Old grass tufts** (`grass_tuft` ScatterLayer) now sit among the dense grass; keep them as accents or drop them.
- [ ] **Buildings, props and villagers** got the detail overlay only; real per-model textures (re-UV) would be the next step up close.
- [ ] **Real recordings** to replace the synthesized placeholders: footsteps (all surfaces + water), splash, spear hit, and the biome ambience beds (`audio/footsteps/`, `audio/movement/`, `audio/fishing/`, `audio/ambience/` — swap the `.wav`s, the `.tres` randomizers stay).
- [ ] **The lantern's creak** fires from 0.15 rad/s now (`Lantern.CREAK_SPEED`, was 0.25) so a stroll creaks now and then: listen whether it creaks too often.

## Tech debt

- [ ] **Crumb models on disk:** ~103 MB (32 wall layers of ~3 MB, the rocks 3–4 MB each): the repo and the playtest zip grow. Could drop the per-crumb vertex colour to bytes, or bake walls with fewer split edges.
- [ ] **Merge buildings' tiers** too (~400 draws in the village): after their tier's pop-in, since that animates piece by piece.
- [ ] **The sun's shadows** are the biggest frame cost left (four cascades to 140 m on high): a look decision.
- [ ] **Performance unmeasured:** low and medium presets, other resolutions, the mine (`tools/perf_probe.gd`, `tools/perf_census.gd`).
- [ ] **Dead code:** the seam-crack code in `resource_node.gd` (and `fractured()` in `make_models.py`) is used only by `models/designs/`; `OreWallPlacer` (`scripts/ore_wall_placer.gd`) placed the quarry's ore walls and nothing uses it since the mine.
- [ ] **`wall_tour.gd` / `wall_closeup.gd`** still look for ore walls in the quarry; point them at the mine.
- [ ] **Icons** don't show the baked shade (Workbench renders palette colour only).
- [ ] **Editor bloats `materials/terrain_assets.tres`:** Terrain3D's editor plugin fills in generated placeholder textures and a default grass mesh and saves them as ~13 MB of image data. The low-poly shader uses none of it. Until there's a fix, discard that change (`git checkout -- materials/terrain_assets.tres`).
- [ ] **Flaky tests:** `test_lamps` (lamps catching by full night, timing) and `test_fireflies` (a cricket voice fading in) fail now and then (3 of 3 passes each on 2026-10-30). `test_day` too: "00:42: Rosa's gone home" (her walk back from the tavern racing the clock) failed 2 of 4 runs on 2026-10-30, on main and on `places`.
- [ ] **`test_dog` is slow** (about 4 minutes, all real time): could run the clock faster or split it.
- [ ] **The audit's blind spots** (`tools/audit_world.gd`): MultiMesh scatter isn't checked (headless, instance transforms don't read back); gaps under ~10 cm aren't reported; the tavern's top-tier bottles read as floating though they stand on their shelf (a false positive).
- [ ] **GPU driver resets:** D3D12 lost the device on 2026-10-16 and 2026-10-19 (GTX 1080 Ti, `nvlddmkm` event 153); switched to Vulkan (`rendering/rendering_device/driver.windows`). Watch whether it comes back.

## Ideas (not planned yet)

- **Bait / lures** (a spinner for pike, a fly for grayling) and a personal-best log of fish sizes.
- **More ways to mine:** pry a cracked piece off by pulling the mouse back; keystones (take pieces in the right order or the rest collapses); triple points where three seams meet.
- **Bucking the fallen trunk into logs** with more swings.
- **Full farming:** planting and growing, seasons, a farmer villager and building, Rosa baking with wheat, a farming perk, and something to spend wheat and barley on.
- **Tunnels** off the mine's dig faces into a drift.
- **A grapple or rope** for chasms and cliff-face nodes.
