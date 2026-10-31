# TODO — parked for later

Everything we decided to come back to, in one place. Tick items off (`- [x]`) as they're done.
Design background for most of these is in [3d-research-notes.md](3d-research-notes.md).

## Mood ([plans/mood-pass.md](../plans/mood-pass.md))

- [ ] **Tune the mood pass by eye** in the debug menu's Sky tab (F1 → Sky, Save writes `data/sky_look.tres`): sunrise/sunset palettes, noon softness, haze distance, the water mist, night brightness (the clearing under its trees is darkest). Checked from screenshots only.
- [ ] **Night length:** deep night is now about 2.5 min (was 5) because the twilight colours reach into it; see the plan's notes for the two levers.

## Calm feel ([plans/calm-feel.md](../plans/calm-feel.md))

- [ ] **Play the calm feel**: stroll/jog speeds and the glide (`player.gd` *Ground*), whether gathering still feels satisfying without hit-stop (the stuck tool's `bite_hold`, `impact_kick`, `shake_break`), gentler popups. Checked headless only.

## Fishing

- [x] **Pike as a predator:** every 25–45 s it stalks the nearest perch, lunges (ripple, the school scatters) and catches one half the time, then glides back to cover. Spooking it calls the hunt off (`FishSpecies` *Hunting* group).
- [ ] **Swimming** — surface swimming in deep water (float, paddle, can't strike well while swimming); maybe diving with a breath meter after that (F2).
- [ ] **Faster regrouping** — scattered schools drift back together slowly (~1 m spread after 8 s); tune cohesion in `scripts/fish_school.gd`.
- [ ] **Skittishness tuning** — play-test `scare_radius`, `nerve`, `calm_down` per species in `data/fish/*.tres`.
- [ ] **Save fish?** — ponds currently start full on every load (deliberate); revisit if it feels exploitable.
- [x] **A lake:** south of the clearing, up a second path. It's 1.35 m deep in the middle, with trout, perch and Arctic char (Fishing 30, keeps to deep water via `FishSpecies.min_depth`).
- [ ] **A stream** feeding the pond. Needs flowing water that isn't a flat `WaterBody` surface.
- [x] **Rod fishing:** cast, bite, fight, land, all timing (plans/fishing.md). Grayling and salmon in generated worlds' rivers (pools at bends, a current that carries the float).
- [ ] **Play the rod by hand** — reworked 2026-10-27 to *wait for the take, then pull* (no fight). The bot lands everything (tools/fishing_playtest.gd); tune the strike windows (0.42–0.6 s) and the hook moment's punch by feel: `data/fish/*.tres` *Rod* group, `RodFishing._hook_moment` / `_yank`.
- [x] **Spear and rod as equal styles** (plans/fishing-parity.md): Q swaps them, fish sizes you can see (Big x2, Huge x3), four forged tiers of each opening the same fish, char and salmon in the shallows at dawn and dusk, one under-level rule, shared hut perks. Tuned with `tools/fishing_bench.gd`.
- [ ] **Play the spear vs rod balance by hand** — the bench's pond numbers are even on XP (rod 292, spear 259 XP/min) but the spear lands ~3x the fish, because the bot never misses and walks straight to the next one. Fish a pond with each for ten minutes and compare; the levers are `SpearFishing.catch_xp` / `flee_catch` / `multi_xp_bonus`, `RodFishing.catch_xp`, and each species' `notice_rate` / `nibbles`. Schools' regrowth (`FishSchool`, 15–25 s a fish) caps the spear.
- [ ] **The spear on the lake at midday** catches nothing (the fish swim too deep for its reach); that's meant (it's the rod's water then), but check it reads as fair in play, e.g. a hover hint.
- [ ] **The fisher's tier 3** asks for pike and char, which now need iron fishing tools (smithy tier 3): check the building order still flows.
- [ ] **Listen to the rod's sounds** (`tools/synth_fishing.py`): every cue is synthesized and unheard; the cast whip, nibble vs. tap, and the take's `hooked` stinger carry the gameplay, so they have to be told apart by ear. `yank` and `flop` are new too. The old fight's sounds (hiss, bulge, strain, snap, thrash, hoist, reel) are unused now.
- [ ] **A river in the main world** so grayling and salmon can go into upgrade costs (they're only in generated worlds; the fisher's tier 3 asks for char, the rod-only fish the main world has).
- [ ] **Bait / lures** (attract certain species: spinner for pike, fly for grayling) and a personal-best log of fish sizes.
- [ ] **Rod in the Settings screen** — prompt assist lives in the debug menu's Player tab (and settings.cfg `[gameplay]`) until `menus` lands.

## Gathering

- [x] **Deepen tree logging** ([plans/logging.md](../plans/logging.md), branch `logging`): the trunk in layers (2 bark, 5 wood) that break away as slabs, clean cuts finishing a layer, the tree going when its wood gives out and falling toward its notch, a knot on every tree (struck: a crack takes several layers), Back cut cracking the hinge, Heartwood's knot glowing. Talents re-checked with `tools/talent_model.gd`.
- [ ] **Logging, unplayed:** headless-checked only (`tools/test_logging.gd`, `tools/test_logging_world.gd`). Not seen in motion: the layer colours in the notch, the slabs, the knot's look and whether it's easy to spot, the fall toward the notch.
- [ ] **Logging sounds:** the layer pop, knot crack and hinge crack reuse the clean-cut and creak stacks. Wanted from a CC0 pick (on a page): a wood slab popping free, a knot cracking open, the hinge splitting.
- [ ] **Dominoes vs Heartwood at `--human=0.7`:** +58% vs +27% (trees fall 60° aside of you now and crush more neighbours); fine at the default bot. Tune `CRUSH_SHARE` / `DOMINOES_LOGS` or `HEARTWOOD_CHANCE` after a playtest.
- [x] **Weak points:** a glowing diamond on one chunk. A swing aimed at it counts an extra hit, gives double XP and a "Weak spot!" burst, then the spot moves (`ResourceNode` *Weak point* group).
- [x] **True tool sinking:** during the bite, a world copy of the tool sticks with its edge buried in the node. The held fist stays on screen holding the handle (`player.gd` `_stick_in_world`).
- [x] **Clean respawn ghost:** one silhouette outline via the stencil buffer (`ResourceNode.ghost_silhouette`, on by default).
- [x] **Iron and oak:** `iron_rock.tscn` (Mining 15) and `oak_tree.tscn` (Woodcutting 15), used in the village's tier-3 costs.
- [x] **More node types:** birch (Woodcutting 8), pine (25), coal (Mining 20) and gold (30), placed around the map.
- [x] **Uses for coal, gold, birch, pine:** they pay for Rosa's and Edda's cottage tiers. The smithy's tier 3 also needs coal, and the town hall's tier 3 needs gold.

### Mining overhaul

- [x] **Feel:** layered impact sounds (`SoundLayers`), chips / dust / sparks per hit (`HitFx`), an impact star, a camera kick and FOV punch (`ShakeCamera.kick`), the tool quivering where it's stuck, pebbles piling up round the rock.
- [x] **Rocks made to break apart:** Voronoi-cut boulders with a `Seam_*` outline per piece and fitted convex collision (`fractured()` in `make_models.py`, `ResourceNode.fit_collision`).
- [x] **Cracks along seams:** every hit on a piece cracks it a step round its outline, tips count double, a full crack splits off exactly that piece; half-cracked pieces keep their progress; no wear-down shedding on seam rocks. Weak points stay on trees only.
- [x] **An ore look each:** copper verdigris, iron basalt columns, coal strata, gold veined geode, crystal snapping off at the base (the other candidates are in `models/designs/`).
- [x] **Overhead pickaxe swing** with a ready stance (`player.gd` `SWINGS`).
- [x] **Real mining sounds** from the GDC 2026 bundle (`tools/cut_sounds.py`, `audio/mining/sfx/`).
- [x] ~~**Iron's crack is faint**~~ superseded: ores no longer crack along seams (see Ore polish).
- [ ] **More ways to mine** (ideas, none picked yet): pry a cracked piece off by pulling the mouse back; keystones (take pieces in the right order or the rest collapses into rubble); ore only from the faces a split exposes; triple points where three seams meet crack all three pieces.
- [x] ~~**Fewer, bigger pieces**~~ superseded by the ore polish.

### Ore polish ([plans/ores.md](../plans/ores.md))

- [x] **Copper breaks where it's struck** (phase 1): 36 pieces drawn as one mesh (`node_rock.gdshader` hides broken ones), 2–3 out per hit, unsupported pieces collapse, shatter at 35% gone; ore spills from vein pieces; exact saves; weathered/fresh baked shading with glinting ore; dirt decal and pebbles; variants rebuilt. Spawns in 5–12 ms (was ~50).
- [x] **Copper playtested**; it felt good. Fixed from it: white blobs by the rocks (`pow(shade, 2.2)` gave NaN pixels the glow smeared out; squared now).
- [x] **The fault:** one piece of every ore rock worked loose, standing a few cm proud and tipped out, a dark crack round it (`fault_shadow` darkens the gap's fresh walls), settling with a pinch of grit every few seconds; hit it and up to six pieces break out (`FAULT_*` in `resource_node.gd`). Replaced a crack decal and a steady trickle of dust.
- [ ] **The fault, unplayed:** whether it's easy enough to spot in play (stills only), and whether the settle wants a quiet tick sound.
- [x] **Every ore breaks its own way** (phases 2–5), its rules in its `.pieces.json` (`support`, `knock`, `shatter_at`, `tough`, `grounded`): iron columns topple (~7 swings), coal plates drop a layer (~7), gold's tough shell hides a gold heart (~9; the quartz-heart candidate is `models/designs/gold_geode_quartz`), crystal shards snap and bring the crystal down (~8). Swings measured hitting one spot; the fault and collapses cut them.
- [x] **Ore pickups and icons** are chunks of their rock's fresh inside (phase 6); **scenery rocks** and **building stone** weathered the same way (phases 7–8).
- [x] **Iron remade** (`iron_limonite` in `make_models.py`; the columns stay in `models/designs/`): a lumpy, pitted rust-red boulder with glinting hematite patches, breaking open steel-grey with red streaks under a brown rind. Rust is baked into the shade (`bake_weathering`'s `tint`): the palette has no rust swatch. Pickup and icon to match.
- [ ] **Iron, not yet measured or played:** swings to break it now (it no longer topples: `knock` 0, `shatter_at` 0.5, like copper), and how it sits next to the other ores in a real world.
- [ ] **Playtest the other ores** and tune: swings per ore (`knock`, `shatter_at` in `make_models.py`), how often you find the fault, ore spill rate, glint (`ore_roughness` / `ore_metallic` / `ore_glow`), the dirt patch on quarry sand.
- [ ] **Sounds** for knocking pieces out, collapses and faults still reuse the split and break sounds.
- [ ] **`.pieces.json` in exports:** add `*.json` to the export include filter when an export preset exists.
- [ ] **The seam-crack code** in `resource_node.gd` (and `fractured()`) is now used only by `models/designs/`; drop it if those designs go.
- [ ] **Icons** don't show the baked shade (Workbench renders palette colour only).

### Ore walls ([plans/ore-walls.md](../plans/ore-walls.md))

- [x] **Panels dug piece by piece** (`OreWall`, `make_models.py` `ore_walls`): 3 x 4 m, 4 m deep, eight layers of ~70 Voronoi pieces; the piece struck is the one with the nearest seed; dug stays dug (saved per panel).
- [x] **Veins** threaded through each panel from its seed (`node_surface.gdshaderinc` WALL), richer with depth and further down the pit; a vein piece needs its ore's pick, drops 1 ore and its XP.
- [x] **Runs** (`OreWallRun`): pillars between panels, a cap rock over them, bedrock behind; dug in, a panel is a roofed alcove, lit from within as it deepens.
- [x] **Loose slabs** (two a layer): struck, or undercut, the whole slab comes down (synthesized `slab` sound). Stragglers crumble once 85% of a layer is gone.
- [x] **Placed** round Greystone's five rings (161 panels, in place of the terrace ore rocks) and a generated world's pit (`OreWallPlacer`).
- [ ] **Playtest:** everything is bot-verified only (screenshots, headless tests). Swings per layer (~30 with a crystal pick, untried with a stone one), slab frequency, vein amount (one vein, sometimes two, ~12–25 vein pieces a layer), whether the alcove light looks like light or like a lamp.
- [ ] **No stone item:** the plan had stone pieces drop stone 1 in 4, but the game has no stone item or use for one; they give XP only.
- [ ] **Iron veins read almost white** (the palette's `ore.iron` is pale silver), and **coal veins on the weathered face read like black cracks**.
- [ ] **Lone panels** (a run of one, between a ramp and stairs) look like a stray cube.
- [ ] **Props keep their stretch of wall bare** (ladders, scaffolds); the scaffolds could move onto the caps.
- [ ] **Panel save ids follow the terrain:** a panel is keyed by its ring, run and place in the run, so regenerating Greystone's terrain (or changing the placer) can hand dug progress to a different panel.
- [ ] **The cap top sits ~5 cm under the level above** (the terrain shows through near the back); fine so far.
- [ ] **Debug menu:** no teleport to a wall or reset of dug walls yet.
- [ ] **Tunnels:** an alcove's back opening into a drift (the plan's "later").

### Woodcutting overhaul

Plan and decisions: `plans/woodcutting-overhaul.md`.

- [x] **Felling axe** with a flat side chop of its own in `SWINGS`; the woodcutter villager carries it too.
- [x] **A notch carved into the trunk** (`TrunkCarve`): set by the first hit, deepened toward the swinger, 65% through by the fall, saved with the game. Replaces the weak point on trees.
- [x] **Clean cuts** into the notch's mouth: an extra hit, double XP, a big chip, a snap.
- [x] **Felling from the notch:** the trunk splits there, hangs on the hinge, falls sideways to the swinger toward the clear side, and leaves the cut stump with growth rings.
- [x] **New trees** picked from rendered candidates (`tree_designs`): round starter, airy birch, spreading oak, classic pine; the scenery forest matches.
- [x] **Feel:** wood chips and dust, bark peeling, canopy shake and leaves, sway and creak late in the chop.
- [x] **More feel:** wedge-shaped chips in twos and threes, a pile of chips building up round the foot (`lingering_rubble`) until it regrows, torn hinge fibres on the stump and the log's end, "Timber!", earth and leaves kicked up along the trunk where it lands and twigs snapping off.
- [x] **Felled crowns no longer prop the tree up:** a carved tree's crown collides at `FELLED_CROWN_SCALE`, its log at its own size (the art pass's big crowns caught hillsides and stood the trunk back up); it also counts as landed once it comes to rest on its crown.
- [ ] **Playtest the new chop feel** (bot-verified only: gallery stills, not seen in motion or played).
- [x] **Wood sounds, synthesized** (`tools/synth_wood_sounds.py`; the GDC bundle's stand-ins sounded wrong): thunk, bite, chips, snap, creak, fibres tearing, crown rushing, landing.
- [ ] **Tune the synthesized wood sounds by ear** in play (each sound is one function in the script; the stacks' levels are in `audio/woodcutting/*.tres`).
- [ ] **The notch on birch** shows less (pale cut wood on white bark); a darker cut colour for it if it reads poorly.
- [ ] **Bucking the fallen trunk into logs** with more swings (left out of this overhaul).

## Tools and levels ([plans/tool-progression.md](../plans/tool-progression.md))

- [x] **Tools gate, levels are soft:** `Tools` autoload, `tool_tier` on every node, under-level penalty and XP bonus (`Skills.UNDER_*`), the spear's gate soft too.
- [x] **Greta forges:** Forge tab, `Tools.RECIPES`, smithy-tier cap, +1 hit power per tier above a node, the Crystal Forge's streak double hit.
- [x] **The forge moment** (`ForgeCutscene`), per-tier escalation, the first-swing shockwave; tier models, icons, sparks, rings and swing pitch.
- [x] **Fresh start:** save version 2; older saves renamed aside (`*.pre-tools.bak`).
- [ ] **Play it by hand.** Everything is bot-tested and screenshotted only: the gate and the under-level penalty (is the 40% floor, reached 10 levels under, too forgiving?), the recipe quantities (`Tools.RECIPES`, first guesses), and the cutscene's pacing (8.6 s; ~9.3 s real with the blows' hit-stops).
- [ ] **Listen to the forge and tool sounds** (`tools/synth_forge.py`): flare, drone, the three blows, hiss, reveal swell, thunder, bell, beam, shockwave, and the copper / iron / crystal rings. All unheard.
- [ ] **Greta's hammer pose** in the cutscene is the arm only (her work animation's hammer stays in her hand); a real hammer swing and the blank in her tongs would sell it more.
- [ ] **`SaveGame.register` and freed nodes:** registering a save id whose previous owner was freed errors ("Trying to assign invalid previously freed instance", the typed `old` in `register`). Seen only in a test that reused ids; would bite a scene reload that re-registers.
- [ ] **Levels: per-level perks and talent choices** — the next plan, [plans/levels.md](../plans/levels.md).

## Village

Design notes are in [village-design.md](village-design.md).

- [x] **Upgrade effects:** tiers give perks (`TierEffect`, summed by `Village.stat`). Smithy: chance of a double hit. Lodge: extra logs. Fisher: calmer fish, then bonus fish. Town hall: an XP bonus.
- [ ] **Villager rig:** real skeletal animation. (Schedules: done, [plans/tavern.md](../plans/tavern.md); they still keep to the village.)
- [x] **A growing village:** town hall tier 2 brings Rosa the baker's cottage, tier 3 Edda the prospector's. They build themselves when unlocked (`Building.unlock_hall_tier`).
- [x] **Give the newcomers a job:** both cottages upgrade like the houses. Rosa: Bakery → Bakehouse, walk and sprint 8% / 15% faster (`run_speed`). Edda: Assay Shed → Assay Office, +1 ore per rock, then rocks grow back 30% faster (`extra_ore`, `rock_regrow`).
- [x] **Sitting:** villagers idling on a `Bench` spot sit on the seat (`Villager._animate_sit`).
- [x] **Talk ray occlusion:** a villager behind a pole still counts if their head, chest or hips is in plain sight (`player.gd` `_villager_behind_clutter`).
- [ ] **Interiors:** the tavern is the first you can walk into (plans/tavern.md); the rest are solid shells (cozy chunk 9).

## Biomes

Plan and decisions: [plans/biomes.md](../plans/biomes.md).

- [x] **The Pinewood, Greystone Quarry, Goldmeadow and the ring road**, with their own ground, light, fog, ambience and arrival cards (`WorldMap`, the `Biome` autoload, `data/biomes/`).
- [x] **Crystal and the Crystal Forge:** Mining 40 on the quarry floor; the smithy's fourth tier (`BuildingTier.hall_tier` lets it need only town hall tier 3).
- [x] **Farming lite:** the Farming skill, a sickle, wheat and barley in Goldmeadow.
- [x] **Time trial** round the ring road: gate, eight checkpoints, splits, saved bests, medal banners on the gate.
- [ ] **Mining tunnels** off the quarry's levels. Cut them into any level wall away from the haul road (see the generator's `_ramp_t`).
- [ ] **Full farming:** planting and growing, seasons, a farmer villager and building, Rosa baking with wheat, a farming perk, and something to spend wheat and barley on.
- [ ] **Tune the medal times** (170 / 125 / 95 s are first guesses; `TimeTrial` exports in `scenes/biomes/road.tscn`) after some real laps.
- [ ] **Lap ghost:** a see-through figure replaying your best lap.
- [ ] **Trophy / achievement spot** in or near the town hall: medals, discoveries, maxed skills.
- [ ] **A "leaves" footstep set** for the forest floor (it sounds like grass for now).

## Menus and worlds

Plan and decisions: [plans/menus.md](../plans/menus.md).

- [x] **Main menu, worlds, pause, settings, New World:** a menu over a drifting view of the clearing, a folder per world (`user://worlds/`), Esc pauses, four settings tabs, world settings with a live map, small and large worlds, a loading screen.
- [ ] **Playtest the menus by hand:** Continue / Play, the pause menu, Save & Quit and its picture, rename / duplicate / delete, the old saves moving into folders on first start. Checked by `tools/menu_shots.gd` and the tests, not by playing.
- [ ] **Display settings in a window:** borderless, fullscreen and the window sizes weren't tried on screen (the machine was busy).
- [ ] **A large world in a window:** its load time (~20 s headless) and how it looks; the one windowed check came out washed out white (probably snow under Frostpeak's fog where the camera landed, not confirmed).
- [ ] **Key rebinding** in Settings > Controls (left for later in the plan).
- [ ] **A second quarry on large worlds** (the plan's "if it fits"): the quarry is one stamp, one `Biome.quarry_*`, one set of levels today.
- [ ] **Repeated biomes' arrival cards** show the first site's kind (`Biome.kind_names` is per biome, not per site).
- [ ] **Small worlds are 384 m**, not the planned 256 (at 256 the rim would start 44 m from the middle, over the hub).
- [ ] **The debug menu's Graphics tab** now duplicates Settings > Graphics; keep it or drop it.
- [ ] **Sound on the menu:** the backdrop is silent (no ambience or music).

## Generated worlds

Plans and decisions: [plans/procgen.md](../plans/procgen.md), [plans/procgen-variety.md](../plans/procgen-variety.md), [plans/menus.md](../plans/menus.md) (world settings, sizes, loading). Merged into `main` 2026-10-19.

- [x] **A world from a seed:** biome ring, water with fish, a quarry pit, trails, spawners and scenery per biome, four baked variants of every gatherable and big scenery model (`scripts/procgen/`, `scenes/procgen.tscn`).
- [x] **A voice per tree species and per ore** (`tools/synth_wood_sounds.py`, `tools/synth_mining_sounds.py`). This changes the hand-built world's sounds too.
- [ ] **Playtest and listen:** walk a few seeds; listen to every tree species and ore (the voices are measured, not heard yet: no steady pulsing, no beating tones, pitch and ring in the intended order).
- [x] **Load time:** the map generates on a worker thread and the spawning and scenery are spread over frames behind a loading screen; a normal world is ready in ~5 s headless (was ~8), a large one in ~20. Caching built rocks could still cut it.
- [ ] **The quarry ambience hum** (55 + 82.5 Hz) repeats 27.5 times a second: a low growl. Worth a listen given how the breeze turned out.
- [x] **Variety:** a kind per biome, Hearthvale (the village) on every seed, rivers, ruins, camps and rare spots, rich and lean resources, an off-centre start (`plans/procgen-variety.md`).
- [ ] **New screenshots:** `docs/images/procgen.png` predates the village, rivers and landmarks (skipped while a game was using the GPU; take them with the shots script when the machine's free).
- [ ] **Walk the new pieces:** climb both ruins to their reward, wade a river and its fords, check the Lakeside Village's fisher meets the pond, see each kind's ground in person.
- [ ] **Hand-sculpting a seed:** a seed you like could be baked to `terrain_data`-style files and edited.
- [x] **Themed nodes** ([plans/themed-nodes.md](../plans/themed-nodes.md), branch `themes`): a theme per biome kind dressing rocks, trees and scenery; shape families; rare looks.
- [ ] **Themed nodes, playtest:** walk a few seeds and judge each theme in person (only screenshots so far: `docs/images/themes/`). Wet (Stillwater, Marsh) is the faintest; the trees' dressing is gentler than the rocks'.
- [ ] **Themed nodes, saves:** which variant a node wears now goes by its cluster's shape family, so a half-mined rock in a procgen save made before this may come back as a different variant (its saved pieces then point at the wrong ones). Fresh seeds are fine.
- [ ] **Themed nodes, load time:** about +0.5–0.75 s a seed (7.5 → 8.25 s windowed, ±1 s run to run); not the doubled variants. Probably the heavier node shader's first compile; check with a profiler.
- [ ] **Themed nodes, the hand-built world:** its spawners and scenery have no theme (`NodeSpawner.theme`, `SceneryScatter.theme`); the biome scenes could each take one.
- [ ] **Themed nodes, not done:** Old Growth trees taller or gnarlier by theme (only the background canopies grow, via `KIND_SCALE`); no trees grow on Frostpeak, so snow on crowns only shows on the rare Frost-touched one.
- [x] **Merge or drop:** merged into `main` (2026-10-19, with the ores work).

## Movement

- [ ] **Grapple / rope** — for chasms and cliff-face nodes.
- [ ] **Agility skill or craftable grapple** — optional movement gating for rare nodes.
- [ ] **Movement tuning:** play-test the momentum numbers (Player inspector: *Momentum*, *Air dash*, *Wall run*, *Speed feel*): bhop gain, the hop window, air control, wall-run length.
- [ ] **Slide / mantle tuning** — play-test speeds and heights (Player inspector: *Crouch / slide*, *Mantle*).

## Art & models

- [x] **Real-model pickups:** drops show the item's model (`Items.model`), tumbling on a fitted box, spinning in as they're collected.
- [x] **Block hands:** a blocky fist and sleeve cuff are part of each tool model (`block_hand()` in `make_models.py`).
- [x] **Replace greybox leftovers:** the parkour blocks are low-poly ruins (`ruins()` in `make_models.py`) with exactly the old collision boxes. Chips are wedge shards and bursts are spinning diamond flecks.
- [x] **Scenery:** grass, flowers, bushes and boulders are scattered by `SceneryScatter` (layers in `main.tscn`, models in `make_models.py` `scenery()`).
- [x] **Blender guide:** [blender-guide.md](blender-guide.md), remodelling the rock by hand.
- [ ] **Sculpt / paint the terrain** in the Terrain3D editor (note: re-running `tools/generate_test_terrain.gd` overwrites it).

### Graphics overhaul (Valheim-style, [plans/graphics.md](../plans/graphics.md))

- [x] Phases 0–9: detail textures, smooth textured terrain, smooth shading, leaf-card trees, dense grass, mist / grading / darker nights / firelight, water and sky, presets.
- [ ] **Playtest the look in motion:** grass parting and swaying, leaf flutter, the shake and fall of a leaf-card tree, felled-tree chips and leaf drops, lamp flicker. Only stills were checked.
- [ ] **Night darkness:** nights are much darker now; tune `DayNightSky`'s night ambient (0.32) and moonlight (0.24) by eye.
- [ ] **README gameplay shots** (mining, woodcutting, spearfishing, pond) still show the old look; retake them. (The rod fishing shot is a playtest bot's, from a generated world's river.)
- [ ] **Ghost outlines on leaf-card trees** (trees above your level) outline whole card quads, not the leaves.
- [ ] **Old grass tufts** (`grass_tuft` ScatterLayer) now sit among the dense grass; keep them as accents or drop them.
- [ ] **Buildings, props and villagers** got the detail overlay only; real per-model textures (re-UV) would be the next step up close.

## Audio

- [ ] **Real recordings** to replace the synthesized placeholders: footsteps (all surfaces + water), slide scrape, mantle, splash, spear hit, and the biome ambience beds (`audio/footsteps/`, `audio/movement/`, `audio/fishing/`, `audio/ambience/` — swap the `.wav`s, the `.tres` randomizers stay).
- [x] **Mining sounds:** cut from the GDC 2026 sampler (`tools/cut_sounds.py`).
- [x] **Even mining levels:** every clip at the same loudness, one source per layer, and the plain hit ducks under a crack tip or a split (`ResourceNode._hit_sounds`). Measured with `tools/measure_mix.py`: a plain hit stays within a 3.4 dB window (was 10.7), a tip hit lands 2 dB above it, a split 3.7 dB.
- [x] **Synthesized mining sounds** (`tools/synth_mining_sounds.py`, 2026-10-17, `procgen` branch) replace the GDC clips below, with a voice per ore. Re-run `tools/measure_mix.py` and rebalance the stack volumes after a listen.
- [x] ~~**Better source material for mining (next):**~~ superseded by the synthesis above. playtested, the sounds are even now but still don't feel right. The sampler has almost no real rock: ice cracks, a metal pipe on concrete, body punches and a broom sweeping crumbs stand in for stone cracking, the pick's bite, the thump and gravel, and the split crunch is a "gore smash". Find a real rock / mining library (stone impacts, pick on rock, rubble, gravel), then point the recipes in `tools/cut_sounds.py` at it: the layer stacks, the loudness matching and the ducking all stay. Re-run `tools/measure_mix.py` and rebalance the layer volumes after.

## World & tech

- [x] **Editor re-save dropped villager lines:** in the editor, non-`@tool` scripts run as placeholders, and a placeholder silently refused the saved `PackedStringArray` when the script's default was a bare `[]` / `[...]` literal. So `BuildingTier.lines` and `BuildingDef.night_lines` loaded empty (or as the default), and the next editor save wrote them out that way. Their defaults are now `PackedStringArray(...)`, and an in-editor re-save keeps all 75 lines. **Rule:** give exported packed arrays a `PackedXArray(...)` default, never a bare array literal. (Fields equal to their script default, like Tier 1's `name = "Lean-to"`, are left out of the file on purpose. That's normal and loses nothing.)
- [ ] **Editor bloats `materials/terrain_assets.tres`:** Terrain3D's editor plugin fills in generated placeholder textures and a default grass mesh and saves them as ~13 MB of image data. The low-poly shader uses none of it. Until there's a fix, discard that change (`git checkout -- materials/terrain_assets.tres`).
- [x] **Day / night:** a 20-minute day (`DayNight` autoload) lit by the `Sky` node. Lamps and windows glow after dark, villagers go home at night, and fish are calmer at dawn and dusk.
- [x] **Stars and moon:** `shaders/sky.gdshader` draws the gradient, a sun disc by day, a moon disc and twinkling stars at night.
- [x] **Terrain collision range:** Terrain3D now builds collision for the whole map up front (`collision_mode` Full/Game, ~0.1 s at 512 m). Revisit if the world gets much bigger.
- [x] **Saved node keys:** every placed node has a `save_id`. Saves keyed by the old scene path carry over automatically.
- [ ] **GPU driver resets:** on 2026-10-16 the game lost its graphics device on Direct3D 12 (GTX 1080 Ti; Windows logged a TDR, `0x141`), and again on 2026-10-19 a moment after a generated world appeared (`nvlddmkm` event 153, `0x887a0005`). Switched to Vulkan (`rendering/rendering_device/driver.windows`) the same day; watch whether it comes back.

## World ([plans/world.md](../plans/world.md), branch `world`)

Generated worlds are gone (the procgen items above are history); Hearthvale is the one world.

- [x] Procgen removed; old generated worlds deleted on startup.
- [x] One rolling land: warped hills, organic flats, valleys between places, a rim of hills, slopes relaxed to ~30°.
- [x] The creek, with grayling and salmon, and the footbridge over it.
- [x] Roads routed over the land and graded from both ends (`scripts/world_roads.gd` is written by the generator).
- [x] Biome borders warped and frayed; Goldmeadow's fields on a curving grid.
- [x] The quarry keeps its stone faces (the ore walls), loses the mantle stairs; its mountainside is gentle.
- [ ] **The land feels barren** (user, 2026-10-29): smooth now, but sparse. Later: more scenery and life between the places (groves, hedgerows, wildflowers along the creek, stone walls, lone trees on the hills, animals).
- [ ] **Walk it:** nothing here is played yet; only slope maps and headless checks. Look for odd road bends, the creek's banks, where the biomes fray, and the view from the rim hills.
- [x] **In-game screenshots:** `graphics_tour.gd --set=world` (docs/images/graphics/world/, sheet in docs/images/world/tour.jpg), the maps (docs/images/world/classic_*.png). They caught Frostpeak too low for its snow (raised to 64 m) and the rim hills being called Frostpeak by height (`Biome.biome_at` now goes by distance only).
- [x] **Frostpeak shaped:** a summit, three spurs and a high western shoulder (`PEAK_RIDGES`), rounded crests, steep flanks that read as rock bands, snow on the gentler high ground, gullies down the sides; the relax pass leaves its faces alone.
- [ ] **Biome cards vs ground:** `Biome.biome_at` still uses the plain shapes (ellipse, discs); the painted ground now uses warped ones, so a card can come a few metres early or late.
- [x] **Saves:** a saved position under the new ground loads on top of it (`Player.from_dict`); one in the air just lands.
- [ ] **Flaky tests:** `test_lamps` (lamps catching by full night, timing) and `test_fireflies` (a cricket voice fading in) fail now and then; both did on `main` before this.

## The dog ([plans/dog.md](../plans/dog.md), branch `dog`)

- [x] Phases 1-7: three breeds in three coats, following, meeting the strays, petting / water / fishing, the lantern, night and the doghouse projects, hints. `tools/test_dog.gd` checks all of it headless; `tools/dog_shots.gd` takes the screenshots.
- [x] **His sounds:** picked by ear 2026-10-29 (https://claude.ai/artifact/JrjwYkzQz8V8HPKMutSGo6), audio/dog/ (SOURCES.md), cut by `tools/cut_dog_sounds.py`. Levels untuned by ear in game.
- [ ] **Play him:** only bot-tested. Look at the poses (sit, lie, the wiggle, the shake), how close he keeps, whether the hints feel rare enough.
- [ ] **Strays screenshot:** `dog_shots.gd`'s first view faces the pond, not the strays.
- [ ] **Small dogs in tall grass:** the terrier half disappears in the grass field.
- [ ] **The test is slow** (about 4 minutes, all real time): could run the clock faster or split it.

## The road east and the market ([plans/market.md](../plans/market.md), branch `market`)

- [x] The road east through a pass; the landslide (boulders, mud) and the retaining wall project; the market stall and barter; the trader and her specials (dog collars, decorations, lantern glass); her sounds (audio/trader/SOURCES.md). `tools/test_market.gd` (15 s).
- [ ] **Play it:** bot-tested only. Barter prices, the wall's cost, how often she comes, the specials' prices are all guesses.
- [x] **In-game screenshots:** docs/images/market/ (`tools/market_shots.gd`); they caught the slide lying along the road instead of across it.
- [ ] **The trader's route** through the village ignores buildings and props (no collision on the cart): watch for it clipping the crates by the town hall.
- [ ] **The retaining wall goes up without a builder** (it's far from the village): a villager could walk out to build it.
- [ ] **The landslide's mud** is a prop on the road, not terrain: the road's surface paint runs under it.

## Villager days and the tavern ([plans/tavern.md](../plans/tavern.md), branch `tavern`)

- [x] The walking network (`VillagePaths`), the villagers' day (`VillagerDay`), windows by who's home, Rosa's terrace, the Sleepy Hound (ruin + 3 tiers, Maud, the walk-in room), sitting, Hound's Luck dice (`DiceRules`, `Die`, `DiceGame`), Ollie's fiddle and dancing, the room's sounds. `tools/test_paths.gd`, `tools/test_day.gd` (~2 min), `tools/test_dice.gd`.
- [x] **Sounds picked by ear** on the Sleepy Hound Sounds page (audio/tavern/SOURCES.md). The band has one tune for now, "Rejoicing", so it repeats: more could go in the library's "tavern" slot.
- [x] **In-game screenshots:** docs/images/tavern/ (`tools/tavern_shots.gd`). They caught a villager coming over to play dice who stopped to chat with you on the way (and then never sat down), and the seated view aiming before you'd reached the stool.
- [ ] **Play it:** bot-tested only. Tier and terrace prices, the dice styles, how long the evening runs, night walks home (an hour of night is ~36 s, so the walk takes most of one) are all guesses.
- [ ] **Saves while sitting:** a save taken seated puts you back on the seat's spot standing (inside the stool); harmless, but could stand you up first.
- [ ] **Villagers on the dice seat** play only against you; two villagers could play each other.
- [ ] **The keeper and Ollie have no house of their own** at the tavern (Maud "lives upstairs": she goes in at the door).
- [ ] **test_lamps and test_lantern fail on main too** (found on this branch): "all burning by full night (48 of 52)" and "walking swings it enough to creak".

## Your home, interiors and add-ons ([plans/home.md](../plans/home.md), branch `home`)

- [x] The village's houses from the Quaternius kits (own colours), walk-in, furnished; your home (tent to homestead), sleeping, well rested, desk notes, head home; villagers' visits and porch evenings; add-on slots (slot 1 for five buildings). The palette from the packs. Tests: `test_home`, `test_interiors`, `test_visits`, `test_addons`, `test_kit_building`.
- [ ] **Play it:** bot-tested and Blender-rendered only, never seen in a game window. Costs, the visit rate, the note chance, well rested's size are guesses.
- [x] **The trophy wall** ([plans/trophies.md](../plans/trophies.md)): trophies as labelled records, the seven finds, the picked models, hanging, the mantel, visitor remarks, the mayor's framed note. `test_trophies`, `test_trophy_wall`.
- [ ] **Trophies, play them:** the rates are guesses (one about every hour or two); the feather and shell glint is a plain emissive mesh. (They now chime when you come near, and the dog finds them: plans/mine.md.)
- [ ] **`test_trophy_wall` fails one check** ("swap: the pike up, the log back in your pack", a call on a null node); it failed before the mine work too.
- [x] **Second add-on slots** and forks for every building, the town hall's, the prospector's and the tavern's too (plans/mine.md phase 9). Villagers still only react to your home's add-ons.
- [x] **The tavern** rebuilt from the kit as the long hall (plans/mine.md phase 10); its top tier is 8 x 12, not the 8 x 14 picked, to stay clear of your home.
- [ ] **Interiors are smaller than planned** (6 x 6 to 8 x 10, not up to 10 x 12) to fit the village's plots; the world pass after cozy can give them room.
- [x] **The old `.glb` models** of the rebuilt houses and the tavern, and their `make_village.py` builders, are gone.
- [x] **Painted texture tiles:** our stone, wood and plaster take the kit's own grain (look D, plans/mine.md phase 8). Not yet seen in a game window.
- [x] **The camps** have bedrolls now: villagers sleep in sight at the lean-to, the forge camp, the open forge, the fisher's tent and the meeting hut (`test_camps`).

## The mine ([plans/mine.md](../plans/mine.md), branch `mine`)

- [x] Greystone as a working quarry: ore walls out, copper, coal and iron rocks on every level, the CC0 mine packs' pieces as dressing, greenery, a puddle, the boarded mine mouth (`test_quarry`).
- [x] The mine under it: three hand-drawn levels of cells, dig faces that give way two layers in, seams that grow back, shoring and lamps (fresh cells the next morning), the way in and out, the lift, the pump, the roof-fall supports, the rails and the minecart ride, the mine map (M), Edda's notes, fossils and geodes, its sounds (`test_mine`).
- [x] The second add-on slots and every building's forks, the tavern from the kit, walk-in camps, trophy hints (`test_forks`, `test_camps`).
- [ ] **Play it:** bot-tested only, never seen in a game window. Guesses: how long a dig face takes (two layers, ~30 swings each with a stone pick), the seams' regrowth (15 minutes), the trophy chance per face (1 in 10), every project and add-on cost, the ride's 20 s, the lamp light, the mine's darkness and its fog, the sound levels.
- [x] **Screenshots** of the quarry, the mine's levels, the map, the ride, the tavern and some add-ons (`tools/mine_shots.gd` -> docs/images/mine/). The mine reads dark but warm; the prospector's add-ons are half hidden in their shot.
- [ ] **The pick hardness moved down a tier** from the plan: level 2's rock needs a copper pick, level 3's an iron pick (the crystal pick needs the crystal that's only on level 3).
- [ ] **Edda doesn't go down the mine** herself: she shores your fresh cells overnight and writes about what you find. Villagers can't walk the mine (no paths, a teleport in).
- [ ] **The fossil** has one look, not picked on a page, and hasn't been seen on the wall.
- [ ] **The tools `wall_tour.gd` / `wall_closeup.gd`** still look for ore walls in the quarry; point them at the mine.
- [ ] **The mine's lights:** every shored cell can have a lamp (an OmniLight3D); only the level you're on is shown, but a fully open, shored level has ~15 lights. Watch the frame rate.

## Polish pass (branch `polish`, off `mine`)

`tools/audit_world.gd` builds a fresh Hearthvale with every tier, add-on, project and mine cell and looks it over headless: the player walking every doorway and stair (real physics), villagers at work facing their work, seats, meshes hanging in the air or buried, colliders with nothing in them or reaching past their mesh, solid-looking things you walk through, props poking into buildings.

- [x] **Stairs:** no interior stair could be climbed (its steps were too tall for the capsule); stairs now collide as their ramp (`Building`), and the player steps up anything up to 0.4 m (porch steps, dock edges, kerbs: `player.gd` `_step_up`, the eye eased up after). The cottages' stairs left a gap at their head to fall through, and your home's stuck out under the loft floor (you hit your head going down, with a drop behind its head): both moved. The town hall's charter stood at its stair's foot.
- [x] **Villagers facing their work:** Bram chopped facing away from his block at every tier, Edda turned her back on her ledger, Ollie fished facing away from the pond at the camp. **Every kit chair stood backwards** (its back in front of whoever sat in it: `chair()` in `kit_buildings.py`).
- [x] **Floating things:** chandeliers under a roof hung from nothing (a tie beam carries them now), the quarry crane stood 6 m up in the air, the well's and noticeboard's roofs were upside down (a V, the ridge floating over it), the market awning sloped the wrong way (its scalloped edge hanging below it), the door's window glass stayed in the doorway when the door swung open, the "workbench" desks were the kit's drawers alone (in mid-air), the bakery flue stood off the oven, hanging signs, bells, the lodge's lantern, the open forge's tool rack, the lookout's rail, grindstones without an axle, the bellows handles, the lamplighter's ladder rungs (off the rails), the flowers over the planters, shelves off the wall.
- [x] **Screenshots** (`tools/polish_shots.gd` -> docs/images/polish/): the stairs from foot and head, chairs, chandeliers on their beam, desks, doors open with their glass, the well, noticeboard and market awning, the crane on the quarry floor. They showed one more: **add-on pieces came out white** (the lookout, the lamplighter's ladder, the hall's flagstones): the importer gives them a blank default material, so `Building` never painted them; now it does.
- [ ] **Play it:** walking the stairs and porch steps by hand (the step-up's feel, the eye easing up).
- [ ] **The audit's blind spots:** MultiMesh scatter isn't checked (headless, instance transforms don't read back); gaps under ~10 cm aren't reported; the tavern's top-tier bottles read as floating though they stand on their shelf (a false positive).
- [ ] **Small things left:** the two signposts' and the landslide mud's colliders reach 0.3-0.9 m past them; a villager standing in a doorway blocks it; the quarry's leaning pickaxe and torch have no collider; woodpile and firewood logs stack with 5-8 cm gaps.
- [ ] **`test_lantern` fails on `mine` already** (the walking swing). `test_worlds` wants `--save-root=user://test_worlds`. (Fixed in the world pass: `test_lamps` now waits for a new road's posts to go up before dusk; `test_projects` counts the mine's shoring project.)
- [x] **Mine faces that wouldn't take a swing** (asked 2026-10-29): with tunnel dug up to a hidden cell from two or more sides, the rock boxes of one face's alcove (and the far face's own stand-in box) stood flush with the other faces into it and caught every swing. They stop 0.3 m short now (`MineLevel.ALCOVE_CLEAR`, `OreWall.BACK_CLEAR`); `test_mine` digs up to a cell from three sides and swings at each face.
- [x] **The way out is a cage in a shaft** over the way-in cell (`MineShaft`): E rings for it and it comes down out of the roof, E again rides it up to the quarry; you come down in it, and it goes back up once you've stepped off. Replaces the door on the wall.
- [x] **The mine's mouth** stood half sunk in the quarry's sloping wall: it stands at the foot of the slope now with a timbered passage back into the rock (`MineMouth._depth`).
- [ ] **Play the shaft:** the cage is the inter-level lift's posts and boards (no walls or gate), the shaft's rock is the level's; the rope's creak is the lift sound.

## The world pass ([plans/world-pass.md](../plans/world-pass.md), branch `world-pass`)

- [ ] **Roomier top-tier interiors** (phase 4, not done): each house's top tier rebuilt toward the planned size (up to 10 x 12 m) and refurnished, its seats, beds, spots and add-ons moved to suit (`tools/blender/kit_buildings.py`), then test_interiors, test_home, test_visits, test_day.
- [ ] **Fixture projects' effects**: restoring the barn, mending the granary and opening a cottage only change how they look; first guesses at a small effect each (plans/world-pass.md, "Open").
- [ ] **The picked rabbit, bunny, frog and pigeon are characters** (Quaternius, upright, with Wave and Punch): look at them in the game before using them as wildlife (phase 8), else simple models of our own.
- [ ] **Walks across the green take longer**: villagers walk briskly over 20 m (`Villager.BRISK`) and go further for the terrace and the tavern (`OUTING_RANGE`); watch test_day's timings and how it feels in play.
- [ ] **The world pass is unplayed and unheard**: every animal call, birdsong and place sound has a first-guess level; walk it with the sound on and tune (`SoundSpot`, `Animal.KINDS`).
- [ ] **A little waterfall** where the creek leaves the north rim (phase 6, not built), and reeds and stepping stones at the lake.
- [ ] **The haven at dusk**: check Fireflies finds its pool on its own (it looks for still water); if not, give the haven a cluster.
- [ ] **Hens hide in long grass** (they're life-size): clear the grass in the farm yard, or scale them up a touch.
- [ ] **The new places' uses** (their own chunk): fruit from the orchard, wool from the shepherd's flock, flour from the mill for Rosa.
- [ ] **Only one lone oak on the knolls** (place_country.gd wanted four): place more by hand in the map editor (plans/map-editor.md).

## The map editor ([plans/map-editor.md](../plans/map-editor.md), branch `map-editor`)

- [ ] **Use it:** lay out Hearthvale by hand (`python tools/map_editor/serve.py`, http://127.0.0.1:8765/), bake, play.
- [ ] **Not walked in-game yet:** the imported world bakes back the same counts and the tests pass, but nobody has looked at it in a window.
- [ ] **The Pinewood's core-to-edge slide** (pine in the middle, birch at the rim) became one average mix on import: split the forest into an inner and an outer patch to get it back.
- [ ] **The forest trail shifts a little** the first time the terrain is regenerated (the road router no longer steers round the old country's grove trees and rocks, only round the layout's points).
- [ ] **Hard-coded land** (the bowl, the clearing, the village flat, the quarry pit, Frostpeak, the existing roads) still lives in `generate_test_terrain.gd` and `WorldMap`; only new terrain shapes come from the editor.
- [ ] **Patch themes and rare looks** (NodeSpawner's `theme`, `rare`) aren't in the layout yet; nothing used them before either.
- [ ] **Ore walls** stay on the quarry's rings (OreWallPlacer); not a line brush.
