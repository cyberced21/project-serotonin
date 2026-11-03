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
