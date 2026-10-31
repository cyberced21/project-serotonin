# Deeper logging

Decided 2026-10-30 with the user (their vision, then /grill-me). Branch `logging` off `main`, in the
worktree `../project-serotonin-logging`; one commit per phase. Follows docs/TODO.md *Deepen tree
logging*. The crumbs work (branch `crumbs`) edits `resource_node.gd` round `_break`, `to_dict`,
`from_dict`, `_reset_visuals` and the rock pieces: the tree side keeps out of those, and puts its
work in `trunk_carve.gd`, the notch and talent functions, and the tree's own helpers.

## What we're building

- **Layers.** A trunk is rings: two of bark (the rough outer bark, then the softer inner bark) and
  five of wood (pale sapwood out to darker heartwood at the core). Each hit puts work into the layer
  it has reached where it lands (most straight in, less round the sides, as the notch spreads now).
  Outer layers are quick, the heartwood takes the most.
- **Layers come off.** When a layer is cut through where you strike, it pops off as a slab: bark in
  strips, wood in a big wedge, in that layer's colour, and the notch jumps a layer deeper. Between
  pops the hit only dents the layer a little. The notch's faces show each ring's colour, so you can
  read how deep you are.
- **Clean cuts** (into the notch's mouth) take the whole current layer off at once there, with the
  big chip and snap. Chain cut still counts runs of them.
- **Stability.** The tree stands on the wood that's left at the notch's ring (bark doesn't hold
  anything). When enough of it is cut away the tree topples by itself. The point it goes is set per
  tree so a plain chop from one side still takes about 15 / 20 / 25 swings (starter and birch, oak,
  pine); `hits_left` becomes "swings left at a plain chop", read off that, for the sway, creak and
  talents.
- **The fall goes toward the cut**: the way it's cut deepest, the uncut side (the hinge) steering
  it. If you stand in its path it swings at least 60° aside, to whichever side is clear. It leans
  more and creaks as it nears the point.
- **The knot** (the tree's fault). Every tree grows one: a dark bump in the bark somewhere round the
  chopping band. Strike it and a crack runs in: it counts `KNOT_EXTRA` more cuts there, so several
  layers pop off at once, with a crack and a burst of bark. Once a tree; it's lost if the notch's
  stripped bark reaches it first. It's saved with a started notch.
- **Heartwood** (Forester) now makes the knot glow so it's easy to spot, and striking it drops a
  heartwood log, as before. Its old chance and the wait before the knot shows go.
- **Back cut** (Forester): everyone fells toward the cut now, so its swing from the far side of a
  deep notch cracks the hinge instead: still ×4, with "Back cut!", a crack and a creak. Dominoes keeps
  felling into the trees along the fall.
- **Sounds** reuse the wood stacks we have (snap, fibres, creak); new sounds wanted go in
  docs/TODO.md for a later CC0 pick on a page.

## Phases

1. **Layers.** `TrunkCarve` keeps work per direction and turns it into a stepped depth through the
   seven layers; layer colours on the notch's faces; `hit()` reports the layers that came off; save
   keeps the work (an older save's depth is turned back into work). Headless test
   `tools/test_logging.gd`.
2. **Slabs and clean cuts.** Layers popping off as strips and wedges in their colour; a clean cut
   finishes the layer.
3. **Stability and the fall.** Wood cross-section, the per-tree fall point (a plain chop measured on
   the tree's own trunk), `hits_left` read off it, fall toward the cut and aside from you, lean and
   creak as it nears.
4. **The knot.** On every tree, struck for a crack, lost to the blaze, saved; Heartwood's glow and
   drop.
5. **Talents.** Back cut as a hinge crack; `tools/talent_model.gd` follows the knot and the
   stability fall; re-run it and the talent tests.
6. **Wrap-up.** docs/TODO.md, README notes, as-built notes here.

## As built (2026-10-30)

All six phases on `logging`, headless-checked, **unplayed**.

- `TrunkCarve.LAYERS` holds each layer's toughness, swatch and colour; `pace` (work per cut) is set
  so a tree's `max_hits` plain cuts take exactly all seven layers straight in. A hit's spread is
  scaled so the bin nearest it takes the whole hit. `DENT` 0.3 of a layer shows between pops.
- Stability is the wood (not bark) left at the ring, as a share of its cross-section. A plain chop
  leaves about 0.78; the fall point is measured per trunk (`ResourceNode._plain_chop()`, cached) and
  sits between the last two cuts. `hits_left` is the count kept, clamped to the plain cuts that
  match the current stability, so a plain chop counts exactly as before. A notch from one side and a
  back cut from the other took 16 swings on a 15-swing tree.
- The knot is `TrunkCarve.knot_*` (saved with the notch), drawn by `ResourceNode._place_knot()` as a
  child of the trunk so it sways with it. One strike took the bark and the first sapwood layer.
- Heartwood's log is a chance (`HEARTWOOD_CHANCE` 0.12) now that every tree has a knot: every strike
  paying out read +229% in the model.
- `from_dict` gained one line (`_place_knot()`), near the crumbs branch's edit there; it should merge
  cleanly but check when both land.
- Open (docs/TODO.md): playtest, the three sounds wanted, Dominoes at `--human=0.7`.

## Out of scope

- Bucking the fallen trunk into logs (still in docs/TODO.md).
- New sounds (listed for a CC0 pick later).
- Villagers' chopping (unchanged).
