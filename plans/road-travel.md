# Road travel: better roads and the carter's cart

Asked 2026-11-03: moving about feels nice and chill but slow, and the map editor can now make maps
up to 2 km across. No mounts. Instead: upgrade the roads so they're quicker to walk, and, for long
hops, a cart that runs along them.

Today: walk 3.8 m/s, jog (Shift) 5.5 m/s. Village to Goldmeadow or the quarry is ~170-190 m (~35 s
jogging); across a 2048 m map would be ~6 min.

## Picked (2026-11-03, grilled)

**Roads (first)**
- **Faster on it, per level:** walking and jogging both, on the road's own line (within its half
  width of where it was laid: WorldMap.roads()), easing in and out over ~0.5 s. Where roads meet,
  the better one counts. Swimming and crouching unchanged.
- **Levels:** today's dirt paths and gravel roads are the base (+0%: nothing changes on load).
  Each road or path goes up twice: *packed and edged* (+15%, kerb stones along it), then
  *cobbled* (+30%, stone setts).
- **Earned on the noticeboard:** one project per road per level ("Cobble the road to the
  quarry"), priced by length: about 1 stone a metre to pack, 2 to cobble, plus a little wood.
  Packing opens at once; cobbles wait for the town hall's second tier (as the far-road lamps do).
  Built, it's laid overnight: the next morning it looks and sounds different.
- **Stone, a new item:** breaking any rock (and the quarry's walls) also drops a few plain stones.
- **You and your dog** get the bonus (he keeps pace); villagers and the trader keep their own pace.
- **Look and sound:** the road's ground is repainted (packed earth with kerbs, then grey cobbles),
  each with its own footsteps. Texture and sound candidates on a page for the user to pick first.

**The carter's cart (second)**
- A noticeboard project wakes up the Cart Shed: a carter with a pony cart.
- **Stops:** a signpost with a bell at the Cart Shed and at the end of each upgraded road you've
  reached. Pick a stop on a little route card; ride there sitting on the back, free to look
  round, at ~3x the jog (~16 m/s: a 2 km map in about 2 minutes). Hop off anywhere with a key.
- It only runs on packed or cobbled roads, so upgrading roads grows the network.
- **Fetching:** ring the bell and it rolls into view from round the bend a few seconds later
  (one cart, never a long wait).
- **Free** once the Cart Shed project is built.

## Phases (to plan in detail)

1. Stone: the item, dropped by rocks and quarry walls; in the market and the pack.
2. Road levels: saved per road, the speed bonus on its line (you and the dog), the noticeboard
   projects by length, gated as above.
3. The look and sound: candidates on a page, then the picked textures painted on built roads
   (Terrain3D control ids at load) and their footsteps.
4. The cart: the Cart Shed project, the carter and cart, stops at road ends (the map editor shows
   them), the bell, the route card, the ride along the roads' laid lines, hopping off.
5. Checked: tests, a ride end to end on Hearthvale and on a big editor map.

## Open

- Whether the map editor can place extra cart stops by hand (beyond road ends).
- What the cart does on a road that's only partly upgraded (it won't run it yet).

## As built

Branch `roads` (worktree `../project-serotonin-roads`), 2026-11-03.

- **Phases 1 + 2:** `stone` (Items, Market: worth half a copper ore), 1-3 from every broken rock
  (`ResourceNode.STONE_DROPS`). The Roads autoload: each road's level, pending till the morning
  (`DayNight.day_broke`), saved; `bonus_at()` from a grid of the laid segments. Cards
  `road:<id>:<level>` (Projects `BETTER_PREFIX`), priced 0.4 / 0.8 stones a metre and a log every
  10 m (less than the 1-2 a metre first planned: the road east would have been 300+ stones),
  minimum 12 stones. The player's speed eases toward the bonus (`ROAD_EASE`). `tools/test_roads.gd`
  (4.94 vs 3.79 m/s on and beside the cobbled street).
- **Phase 4 (before 3: it waits on no art):** `CartLine` (in main.tscn), `CartStop`, `CartPanel`;
  the `carter` project (needs a packed road); Roads remembers the road ends reached. The seat
  carries the player (`player.gd`: a seat with meta `cart`), standing up off it puts you beside it.
  Stand-ins: the hay cart, no pony, a UI click for the bell. `tools/test_cart.gd`.
- **Phase 3:** picked on the road travel page (an artifact; picks kept in its db): packed = packed
  earth + timber edging boards, cobbled = square setts + kerb stones (ground ids 7 and 8, two new
  `ground.png` slices from tools/make_textures.py; `RoadLook` repaints a better road's cells and
  lays its edging as MultiMesh boxes, gaps where roads meet); footsteps packed_/cobble_01-04;
  the cart = the village kit's wagon (models/cart/wagon.glb), the donkey (Walk / Gallop by pace),
  the keeper's villager look as the carter, hooves + rattle loops and a handbell (audio/cart);
  stone = KayKit's Stone_Brick (models/items/stone.glb, icon rendered with its own material).
  Not yet seen in a game window.
