# Noticeboard redesign

The playtest (2026-11-03): looking at the noticeboard tanks the frame rate, and the board is
getting too full to read (37 notices on a fresh Hearthvale). Grilled 2026-11-03; look B picked
from https://claude.ai/artifact/AzxuVny7RXB2JDzSvhoczx.

## Why it was slow (measured with tools/bench_noticeboard.gd, headless, main at f8aa4af)

- Looking at the board: **25.6 ms of CPU every frame.** The hover prompt counts open projects
  with `Projects.all()`, then `is_locked()` for each, and `is_locked()` → `get_project()` builds
  `all()` again: about 40 full rebuilds a frame, each re-measuring every road's length.
- Opening the board (and every inventory change while it's open): **~285 ms.** The same
  `all()`-per-note pattern (`is_locked`, `can_pay`), plus `MapView.map_font()` making a new
  SystemFont for every label.
- GPU: nothing board-specific changes when you look at it (only one instance shader parameter).

## Decisions

- **Five categories**, from what's posted: *The green* (benches, flower boxes, well, bunting,
  fountain, market stall, terrace), *Mending* (granary, barn, cottage, mill wheel, orchard wall,
  footbridge, the road east's wall, the cart shed), *Roads* (one card per road with its lamps and
  its paving together), *The mine* (all the mine's jobs), *Your dog* (kennel, paint, porch).
- **Look B:** a category list down the left (open count, and a gold mark when something there is
  affordable now), and one wide paper strip per notice on the cork: title, a line of what it
  adds, the cost (have/need), Pay. A road's card has a Lamps row and a paving row, each with its
  own cost and Pay.
- **Locked notices** (waiting for the town hall) fold into one quiet line per category:
  "Later, at town hall tier 2: …".
- **Done notices** fold into a "Done (n)" strip at the bottom of each category, closed by
  default, click to unfold the ticked list.
- **Opens on** the category you last looked at (for the session); the first time, The green.
- Panel sized as shares of the window (MenuUI.place), as now.

## Phases

1. **Speed.** `Projects.all()` cached until something changes (Projects/Lamps/Roads/Companion
   changes, town hall tier, a frame later for needs the world decides); `is_locked`/`can_pay`
   look up by id in the cache; road lengths cached; the map font cached. Bench before/after.
2. **Categories.** Each project gets a `cat`; `Projects.categories()` lists them in order.
   Test in test_projects.
3. **The new board.** NoticeboardPanel rebuilt as look B: left list, strips, road cards, later
   line, done fold, remembered category. Test in test_projects (opens, switches, pays).
4. Bench again, run touched tests, notes.
