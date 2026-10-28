# Cozy sound: music, a warmer soundscape, night ambiance

Chunk 3 of [cozy.md](cozy.md) (its section 9, plus section 2's night ambiance). Grilled
2026-10-27. Branch `cozy-sound` off `main`.

Status: **phases 1 and 2 built** 2026-10-27: the Music bus and wave system, and ten picked CC0
tracks, one per slot (audio/music/SOURCES.md; levels from `tools/measure_music.gd`). **Not heard
in game yet.** The shortlist page (https://claude.ai/artifact/KFsWkG9bSzt6AWRfhzDy6H) holds 46
candidates if a slot wants more variety later. Next: phase 3, moment cues (pick). Most phases stop
for a pick by ear: I can measure sounds, not hear them.

## Where we start (2026-10-27)

- **No music** at all.
- Gathering: every sound synthesized (`tools/synth_gathering.py`, `audio/gathering/`); the chop and
  the clink were approved as final on 10-19, and are now being reworked for coziness (S7).
- Footsteps: grass, dirt, rock, sand (`audio/footsteps/`, `scripts/footsteps.gd`).
- Ambience: three loops, field / forest / quarry (`tools/synth_ambience.py`), one per biome mood.
- Fishing: a large synthesized set (`tools/synth_fishing.py`).
- Buses (`default_bus_layout.tres`): Master, Effects, SFX, Debris, Ambience, Movement. Effects are
  dry (no reverb). Settings has volume sliders per bus, no Music.

## Decisions

| # | Topic | Decision |
|---|-------|----------|
| S1 | Music source | **Licensed tracks, CC0 only** (public domain: no credit, no strings). |
| S2 | Instruments | **Acoustic guitar and piano.** |
| S3 | When | **In waves**: a piece (2–4 min), then **2–5 min of ambience only**, at random. |
| S4 | Variation | **Morning / day / evening / night sets**, **per area** (village, forest, lake, mine), **tavern music** heard from the tavern at night (lands with cozy chunk 8), and **moments**. |
| S5 | Picking tracks | **A shortlist page**: about 4 CC0 candidates per slot with links, licence and length; you listen and tick; I download only the picks (each download asked first). |
| S6 | Moment cues | **Synthesized**: short soft guitar/piano-like phrases (1–3 s) in the music's key, replacing the level-up, discovery and upgrade stings. |
| S7 | Gathering | **Reworked for cozy: warm and woody.** Wood: a rounded "tock", soft woody body, gentle crunch, like a mallet on a log, never sharp. Rock: a muted stony "clack" with a small pleasant ring, no metal screech. |
| S8 | Fishing | **Same cozy pass**; the bite cues must stay clearly readable. |
| S9 | Footsteps | **Weight and body** (a soft low heel thud), **crunch per surface**, **quiet and varied** (no two steps alike). **CC0 recordings**, cleaned, with a synthesized heel thud layered under. |
| S10 | UI | **Wood and paper**: soft wooden taps, page flips, a gentle pop for pickups; nothing beepy. |
| S11 | Ambience | **Day / dusk / night sets** (birds; settling birds and first crickets; crickets, frogs, an owl, a rare far wolf), **water** (lapping ponds, a babbling river, louder as you near), **wind in trees** (leaves in the forest, soft gusts on hills), **village life** (distant chatter, the smithy's hammer, a dog, chimney crackle). |
| S12 | Recordings | **CC0 field recordings** for what synthesis does badly (animals, birds, voices, footsteps); **synthesis** for everything percussive (chops, UI, cues, heel thud). You approve each by ear. |
| S13 | Space | **Gentle reverb per place**: a soft short room in the forest, wider and airy on open hills, a cosy wooden room indoors, a long echo in the mine. Subtle. |
| S14 | Review | **A takes page per batch**: A/B/C/D renders to play side by side; you pick, I refine from your pick. |
| S15 | Mix | **Ambience > effects > music**: the world is the bed, actions sit just above it, music is a soft layer under all; a **Music** volume slider in Settings. |

### Change of direction (2026-10-27, during phase 3)

The user is wary of synthesis: past synthesized sounds came out rough, high-pitched and strident.
So **effects come from free CC0 sound packs first** (Kenney, OpenGameArt, ...), medieval/fantasy
in feel, picked by ear on a listening page like the music. Synthesis only where no pack has a
fitting sound, and only with the user's go-ahead. This replaces S6 (cues), S7/S8 (gathering and
fishing reworks), S9's heel thud, S10 (UI) and S12's "synthesis for everything percussive".
Phase 3's cue candidates are on https://claude.ai/artifact/ArHc9iicrEwvrQJg5hi1bx (Fupi's Win
Jingle on 12 instruments, its first notes as short cuts, wobbleboxx's 13 level-up sounds).
Kenney's Music Jingles couldn't be downloaded (its signed link had expired).

## Phases

One commit each; phases marked **(pick)** stop for your choice.

1. **Buses and the music system.** Add Music and per-place reverb buses (keep the menus branch's
   bus order in mind); Settings gets a Music slider. A `Music` autoload: waves with random gaps,
   slots by time of day and area, crossfades, ducks under moment cues and cutscenes, saves nothing.
   Silent placeholder slots until tracks arrive. Mix levels set to S15.
2. **Music shortlist (pick).** A page of CC0 candidates per slot (morning, day, evening, night,
   village, forest, lake, mine; tavern later), guitar and piano. Download your picks (asked
   first), trim/loudness-match, wire them into the slots.
3. **Moment cues (pick).** Synthesized guitar/piano phrases for level-up, discovery, upgrade, forge
   reveal; takes page; replace the stings.
4. **Footsteps (pick).** CC0 recordings per surface (grass, dirt, rock, sand), cleaned and
   loudness-matched, many variations; a synthesized heel thud under each; takes page.
5. **Gathering (pick).** Warm-and-woody rework in `synth_gathering.py`: wood tock/crunch, rock
   clack/ring, per species and ore; break and fall sounds to match; takes page.
6. **Fishing (pick).** The same softening in `synth_fishing.py`, keeping the nibble, take and
   hook readable apart; takes page.
7. **UI (pick).** Wood and paper: panel open/close, upgrade, pickup, menu clicks, tabs; takes page.
8. **Ambience (pick).** Day/dusk/night beds crossfaded with `DayNight` (the biome's loop becomes
   its day bed); CC0 birds, crickets, frogs, owl, rare far wolf; water emitters on each
   `WaterBody`; wind in the trees; village life emitters. Takes page for the recordings.
9. **Fireflies.** Soft blinking points over grass, ponds and the forest edge, dusk to midnight,
   drifting away from you (cozy section 2's visual half).
10. **Reverb per place and a final mix.** Reverb zones per biome (forest, hills, mine/quarry;
    indoors waits for interiors), levels balanced in the real buses (`tools/record_sfx_chain.gd`),
    then an in-game listen.

## Not in this chunk

Tavern music itself (with the tavern, chunk 8), indoor reverb (interiors, chunk 9), new footstep
surfaces like wooden planks and gravel (when docks, porches and gravel paths exist).
