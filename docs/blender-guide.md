# Blender guide: remodel the rock by hand

A first modelling project. You'll take the generated copper rock, reshape it, add a chunk,
colour it from the palette, and get it into the game. Written for Blender 4.2 or later (5.x
works the same). It takes about an hour the first time.

Everything in the game follows the same few rules, so once the rock works, trees, fish and
village buildings use the same steps.

## The rules this game cares about

| Rule | Why |
|---|---|
| **1 Blender unit = 1 metre.** | The rock is about 1 m wide; the player is 1.8 m tall. |
| **Z is up in Blender, the front faces −Y.** | The exporter turns that into Godot's Y-up and +Z-forward. |
| **Object names say what a piece does:** `Body_*`, `Chunk_*`, `Rubble_*`. | `ResourceNode` sorts meshes by name. Body stays until the node breaks, chunks pop off as you hit it, and rubble is what's left while it respawns. Other names are ignored. |
| **Each chunk's origin is at its own centre.** | Chunks fly off and spin around their origin. |
| **The model's ground is at Z = 0.** | The node stands on the terrain at its origin. |
| **Colour comes from UVs, not materials.** | Every face points its UVs at one swatch of `art/palette.png`. The game uses one shared palette material, so materials in Blender are ignored. |
| **Flat shading.** | The low-poly look: one colour per face, hard edges. |

## 1. Open the rock

1. Start Blender, then use **File → New → General**. Delete the default cube (**X → Delete**).
2. Choose **File → Import → glTF 2.0** and pick `models/rock.glb` from the project.
3. Look at the **Outliner** (top right). You'll see `Body_Core`, `Chunk_A` to `Chunk_E`, and `Rubble_0` to `Rubble_2`.

Getting around the 3D view:

| Action | How |
|---|---|
| Orbit | middle-mouse drag |
| Pan | **Shift** + middle-mouse drag |
| Zoom | scroll |
| Frame the selection | **Numpad .** (or **View → Frame Selected**) |
| Front / side / top view | **Numpad 1 / 3 / 7** |

Hide the rubble while you work on the rock: click the eye icons next to `Rubble_*` in the Outliner.

## 2. Reshape a chunk

1. Click `Chunk_A`, then press **Tab** to enter Edit Mode.
2. Press **1** for vertex select. Click a vertex (**Shift**-click to add more).
3. Use **G** to move, **R** to rotate and **S** to scale. Type a letter after, such as **G Z**, to lock to an axis. Click to confirm, or right-click to cancel.
4. **Proportional editing** (**O**, or the circle icon in the header) drags nearby vertices along with the one you grab. Scroll the mouse wheel while grabbing to change its reach. It's good for lumpy stone.
5. Press **Tab** to go back to Object Mode.

Keep chunks chunky. The game's hit feedback reads best when a chunk is clearly a separate lump
sitting on the core.

## 3. Add a sixth chunk

1. **Shift+A → Mesh → Ico Sphere.** In the pop-up panel (bottom left), set **Subdivisions 1**
   and **Radius 0.2**.
2. Move it so it half-sinks into the core: **G**, then drag it into place.
3. To make it rough, go into Edit Mode (**Tab**), select everything (**A**), choose **Mesh → Transform → Randomize**, and set the amount to about 0.04. Then **Tab** back.
4. Rename it: press **F2** and type `Chunk_F`.
5. **Object → Set Origin → Origin to Geometry** puts its origin at its own centre.

More chunks means the rock wears down in more steps. The game spreads the chunks over the hits
it takes, so `max_hits` (6 on the rock) doesn't need to match the number of chunks.

## 4. Flat shading

Select everything (**A** in Object Mode), then choose **Object → Shade Flat**.

## 5. Colour it from the palette

The palette is an 8 × 8 grid of colours in `art/palette.png`, one family per row:

| Row | Family |
|---|---|
| 1 | stone (dark → light) |
| 2 | ore (copper, iron, gold, coal, gems) |
| 3 | wood |
| 4 | leaves |
| 5 | terrain (grass, dirt, rock, sand, snow, moss, path) |
| 6 | metal |
| 7 | accent (reds, orange, yellow, blues, purple, pink) |
| 8 | neutral (black → white) |

To colour faces:

1. Switch to the **UV Editing** workspace (tab at the top). The left is the UV editor, the right is the 3D view.
2. In the UV editor, choose **Image → Open** and pick `art/palette.png`. Set the display to **nearest** if it looks blurry (the sidebar **N → Image**, or the filter dropdown).
3. Select an object and press **Tab** to edit it. Press **3** for face select, then click faces in the 3D view.
4. In the UV editor, hover the mouse over it, then press **S 0 Enter**. The selected faces' UVs collapse to a single point.
5. Press **G** and move that point into the swatch you want, well inside it, not on its edge.
6. Repeat for other faces. A good rule: tops one shade lighter than the sides, undersides darker. That's what the generated models do.

Copper flecks are just a few faces pointed at the copper swatches (row 2, first two columns).

To see the colours in the 3D view, set the viewport shading (the top-right sphere icons) to
**Solid** with **Texture** colour, after giving the object a material with the palette image.
This is only a preview: the game ignores Blender materials.

## 6. Rubble

The rubble is what stays on the ground while the rock respawns: a few flat stones. Reshape the
`Rubble_*` pieces the same way. Keep them low (under about 15 cm) so they don't look like a
second rock.

## 7. Check before exporting

- Every piece is named `Body_…`, `Chunk_…` or `Rubble_…`.
- Each chunk's origin sits at its centre (**Object → Set Origin → Origin to Geometry**).
- The bottom of the rock is at Z = 0 (check in front view, **Numpad 1**).
- **Ctrl+A → All Transforms** on everything, so what you see is what exports.
- Normals face outward: in Edit Mode, select all and press **Shift+N** (Recalculate Outside). Inside-out faces render black or vanish in the game.

## 8. Export

1. **File → Export → glTF 2.0.**
2. Settings:
   - **Format:** glTF Binary (.glb)
   - **Include:** leave *Selected Objects* off (export everything)
   - **Transform:** *+Y Up* on
   - **Data → Mesh:** *Apply Modifiers*, *UVs* and *Normals* on
   - **Material:** set to *No export*. The game uses the palette material.
3. Save it as **`models/rock_mine.glb`**. Don't overwrite `rock.glb`: re-running `tools/blender/make_models.py` regenerates that file and would wipe your work.

## 9. See it in the game

1. Open the project in Godot. It imports the new `.glb` automatically.
2. Open `scenes/rock.tscn`. In the Inspector, under **Visuals → Model**, drag in `models/rock_mine.glb`.
3. Press **F5** and hit a rock. Chunks should pop off nearest-first, and the rubble should show while it respawns.

To keep both rocks, don't change `rock.tscn`. Right-click it, choose **New Inherited Scene**, set the model there, save it as `scenes/my_rock.tscn`, and place it in `main.tscn`. Give the placed node its own **Save Id** in the inspector.

## If something's off

| Symptom | Likely cause |
|---|---|
| A piece never pops off, or is always missing | Its name doesn't start with `Chunk_` / `Body_` / `Rubble_`. |
| A chunk spins around a strange point when it flies off | Its origin isn't at its centre. |
| Faces are the wrong colour or striped | Their UVs are on a swatch edge, or spread across several swatches. Collapse them again (**S 0**). |
| Faces are black or see-through | Flipped normals. Use **Shift+N** in Edit Mode. |
| The rock floats or sinks | The model's bottom isn't at Z = 0. |
| It's huge or tiny | The scale wasn't applied (**Ctrl+A → Scale**). |

## Next steps

- Try the tree. Same rules: trunk and canopy are `Body_*`, bark slabs are `Chunk_*`, the stump is `Rubble_*`.
- Read how the generator builds models in `tools/blender/make_models.py`. Every `make_object()` call is one named piece, and every `paint()` call picks swatches by face direction, the same thing you just did by hand.
