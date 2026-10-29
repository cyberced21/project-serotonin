# The dog: company that follows you

Chunk 6 of [cozy.md](cozy.md) (its section 4). Grilled 2026-10-29. Branch `dog` off `main`, after
`world` is merged (and released).

## Where we start (2026-10-29)

- Villagers (`scripts/villager.gd`) have no rig and no navmesh: the model is separate parts
  (Body, Head, ArmL/R, LegL/R, made by `tools/blender/make_village.py`) posed in code, easing
  toward target poses; they walk in straight lines between spots. The dog is built the same way.
- The lantern (`Lamps`, `scripts/lantern.gd`) is the elder's gift at the first dusk
  (`scripts/lantern_gift.gd`); you can hold it, raise it, hang it.
- Projects (`Projects.SPOTS`) are one-off builds with a town hall tier; `VillageDecor` builds them in
  view (a villager hammers, pieces pop up with a tok, a cheer). Nothing chains yet.
- Sounds come from CC0 packs, picked by ear on a page (memory: sound sourcing).

## Decisions (grilled 2026-10-29)

- **Meeting him:** on the first morning three strays nap round the clearing's pond, one of each
  breed. The first one you pet (E) gets up, a small box asks his name (a suggested default you can
  just accept) and his coat colour; the other two wander off over the hills. A world with no dog
  yet (your current save included) gets the strays at the next dawn, or at once if it's day.
- **Three breeds**, sharing one set of movements: a small scruffy terrier, a medium shepherd-type
  mutt, a big fluffy one (Bernese-like). Each has its own proportions, ears and tail and three or
  four coats. Toy low-poly, separate parts posed in code.
- **Always with you.** He follows at a relaxed distance, sniffs about, trots ahead along roads and
  paths, sits when you stop, lies down when you gather for a while. Past about 50 m behind (a
  sprint, a teleport, ground he can't take) he pops in trotting up just behind you, out of view.
- **Never in the way:** no collision with you; he keeps out from in front of what you're hitting
  and out of your casting line; you target him (to pet) only by looking right at him.
- **Water:** he paddles after you in wading-depth water (ponds, the creek), waits on the bank if
  you go deeper, and shakes himself dry with a spray when he comes out. While you fish he sits and
  watches the float; fish don't flee from him.
- **Pet him** (E): a little wiggle, tail going, a happy whine. No meter, nothing to maintain.
- **Lantern:** once you have it, at dusk he trots over with it in his mouth and walks a little
  ahead to light the way; your hands stay on your tools. Hold the lantern key to take it back and
  raise it yourself; he takes it again when you put it away.
- **Helping is hints only**, never needed, never changes yields: he sniffs and wags at a nearby
  rare-look node or an ore fault, stares at a fish school, and gives a soft woof when you land a
  big fish.
- **Sounds: quiet, mostly.** Panting when trotting, sniffs, a happy whine and tail thumps when
  petted, a single soft woof now and then (a big fish, a hint, answering the rare far-off wolf
  howl). Real recordings from CC0 packs, picked by ear on a page.
- **Night:** before there's a doghouse he lies down at your feet and dozes when you stand still at
  night. With a kennel built and you in the village, he trots off to sleep in it and is waiting
  outside it in the morning.
- **The doghouse is three chained projects** on the noticeboard, each appearing once the one before
  is done, growing in place with the usual build moment: *A kennel* (wood), *Paint it and hang his
  name* (birch, flowers' crops: his name on the sign), *A bowl, a blanket and a porch* (oak, iron).

## Phases (one commit each)

1. **The three dogs as models.** Parts (body, head, jaw, ears, tail, four legs) per breed in the
   Blender scripts, coats as palette variants, the lantern-in-mouth socket. Done: a turntable
   sheet of the three breeds in each coat.
2. **Following.** `Dog` node: ground-snapped, no collision with you; states follow / trot ahead on
   roads (WorldMap.roads()) / sit / lie down while you gather / catch up (pop in behind past 50 m);
   posed walk, trot, sit, lie, sniff. Done: a headless test walks the player round and the dog
   keeps up, never blocks, never ends up stuck or in the air.
3. **Meeting him.** Three strays at dawn by the clearing's pond in a world with no dog; petting one
   opens the name-and-coat box; the others wander off; the dog (breed, coat, name) saves per
   world. Done: a fresh world and an old save both meet him.
4. **Petting, water and fishing.** E to pet (wiggle, tail, whine); paddling in the shallows,
   waiting at deeper water, the shake; sitting to watch the float, fish ignore him. Done: tests
   for the wading rules and that fish don't flee.
5. **The lantern.** He takes it at dusk, walks ahead lighting the way; holding the lantern key
   takes it back. Done: night screenshots, a test that the light follows him.
6. **Night and the doghouse.** Dozing at your feet at night; Projects gains chains (a project that
   needs another done first); the three doghouse projects with their props in `VillageDecor`, his
   name on the sign; sleeping in it, waiting outside in the morning. Done: `test_projects` covers
   the chain; screenshots of each tier.
7. **Hints and sounds.** Sniff-and-wag at rare looks and faults, staring at fish schools, the woof
   for big fish and the wolf howl. Sounds picked by ear on a page, then wired. Done: the page
   picked, tests for the hint triggers.
8. **Pictures and checks.** Screenshots (graphics tour), README, TODO, the plan as built.
