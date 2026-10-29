# The road east, the market stall and the trader

Chunk 7 of [cozy.md](cozy.md) (its section 5: the landslide, the market, traders). Grilled
2026-10-29. Branch `market` off `main`.

## Where we start (2026-10-29)

- Hearthvale is one curated valley (plans/world.md); no road leads out of it. Roads are laid by the
  terrain generator from `WorldMap.ROADS` (least-cost routes) and written to `scripts/world_roads.gd`.
- Projects (`Projects.SPOTS`, the noticeboard) are paid builds with a town hall tier and, since the
  dog, an optional `needs` (another project, or the dog). `VillageDecor` builds them in view.
- Resource nodes (`ResourceNode`, scenes like `rock.tscn`) are placed by hand in main.tscn or by
  `NodeSpawner`; the stone pick (tier 0) is what you start with.
- Villagers (`Villager`) belong to a `Building`, with spots to walk between, a panel on E.

## Decisions (grilled 2026-10-29)

- **The road east**: a new road from the village up through a pass in the eastern rim hills, "the
  road to the wider world". Partway up, a **landslide** buries it: a fan of mud and fallen boulders
  with the road disappearing under it.
- **Clearing it: dig, then build.** The boulders are mining nodes you break with any pick (they drop
  stone-ish copper ore and a little coal); they don't come back. Once they're all broken, the
  **retaining wall** (timber cribbing along the slope) goes up on the noticeboard (logs and iron,
  town hall tier 2) and is built with the usual build moment. With the wall up, the road is open.
- **Reachable from the start**: the road and the slide are there from day one.
- **Barter only**, no currency.
- **The market stall**: a noticeboard project builds a stall in the square, run by a villager
  (E opens it). Open every day: fixed, lossy swaps, about 3 of something for 1 of something else,
  same family first (logs for logs, ore for ore, fish for fish, crops for crops), across families
  dearer. Gathering stays the main way to get things.
- **The trader**: once the road is open, a travelling trader drives a horse-drawn cart over the
  pass every second morning, parks by the market for the day (better rates while she's there) and
  leaves at dusk. She brings things you can't get otherwise: **dog coats and collars, decorations**
  (a weathervane, a painted cart, hanging flower baskets) **and lantern glass colours**. One of
  each is on her cart per visit, rotating.

## Phases (one commit each)

1. **The road east.** A road from the village through the eastern rim to the world's edge, in
   `WorldMap.ROADS`; a pass cut gently through the rim; regenerated terrain. Done: walkable end to
   end, on the map, lamps can line it.
2. **The landslide.** A mud fan over the road partway up (terrain + a painted surface), a dozen
   boulders as one-off mining nodes (saved when broken), a few scenery rocks; the road beyond is
   blocked by the fan until it's cleared. Done: test breaks them all and they stay broken.
3. **The retaining wall.** A project that needs every boulder broken; timber cribbing model; built
   in view; `Projects`/a `Roads` flag says the road east is open. Done: test pays for it.
4. **The market stall.** Model, a stall villager, the barter panel (what you give, what you get,
   have/need), the fixed rates table. Done: test trades both ways, refuses what you can't afford.
5. **The trader.** Her cart and horse (toy parts like the villagers and dog), arriving over the pass
   every second morning, parking, leaving at dusk; better rates while she's in; her rotating
   specials. Done: test fast-forwards days and sees her come and go.
6. **The specials.** Dog collars/bandanas and coats (Companion gains a collar), three
   decorations with spots, lantern glass colours (Lamps gains a tint). Done: buying each changes
   the world.
7. **Sounds.** Cart wheels and hooves, the stall, the slide's dig; CC0, picked by ear on a page.
8. **Pictures and checks.** Screenshots, README, TODO, the plan as built.
