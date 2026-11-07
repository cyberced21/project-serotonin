// Decorations (plans/town-designer.md, phase 5): the town's palette of props, each with its picture
// (icons/<id>.png, tools/blender/prop_icons.py), and three tools that put them down as points:
//   Stamp    click to place one (R turns it, or let it face the street or turn at random)
//   Scatter  drag a brush to sprinkle a mix (Shift-click pictures to add to the mix)
//   Row      draw a line; one every N m along it, facing along it, across it or at random
// A decoration put down within a few metres of a building belongs to it (it moves with it), unless
// "belong to the nearest house" is unticked. Close up in town mode, points show their pictures.
"use strict";

(() => {
	const E = Editor;
	const el = (...a) => E.el(...a);
	const GROUPS = [
		["Garden", ["flowers", "flower_group", "flowers_2", "bush_flowers", "bush_berries", "hedge_bit", "veg_bed", "cabbage", "pumpkin", "turnip", "garden_wheat", "orchard_tree"]],
		["Lamps and seats", ["lamp_post", "lamp_rustic", "bench", "village_bench", "signpost", "shrine", "standing_stone", "boulder"]],
		["Farm", ["cart", "hay_stack", "hay_round", "pen_fence", "barrel", "crates", "tub", "firewood", "woodpile", "flour_sack"]],
		["Yard", ["forge", "anvil_log", "quench_bucket", "whetstone", "metal_crate", "chopping_log", "workbench", "axe", "table_large", "stone_heap", "jetty_deck", "fish_rack", "gutting_table", "fish", "scroll"]],
	];
	const OWN_REACH = 6;  // (m from a building's edge: a decoration put down this close belongs to it)

	const known = (id) => !!(E.catalog.props[id] || E.catalog.fixtures[id]);
	const label = (id) => (E.catalog.props[id] || E.catalog.fixtures[id] || {}).label || id;
	/** Every palette group with what the catalog has, and "Other" for the props in none. */
	const groups = () => {
		const listed = new Set(GROUPS.flatMap(([, ids]) => ids));
		const other = [...Object.keys(E.catalog.props), ...Object.keys(E.catalog.fixtures)].filter((k) => !listed.has(k));
		return [...GROUPS.map(([g, ids]) => [g, ids.filter(known)]), ["Other", other]].filter(([, ids]) => ids.length);
	};

	// --- pictures --------------------------------------------------------------------------------------

	const icons = {};
	const icon = (id) => {
		if (!(id in icons)) {
			const img = new Image();
			img.onload = () => E.draw();
			img.src = `icons/${id}.png`;
			icons[id] = img;
		}
		return icons[id].complete && icons[id].naturalWidth ? icons[id] : null;
	};
	/** A point's picture on the map (town mode, close up). Returns whether it drew one. */
	E.drawPointIcon = (ctx, o, sx, sy, selected) => {
		if (!E.town || E.view.s < 4 || !known(o.type)) return false;
		const img = icon(o.type);
		if (!img) return false;
		const r = Math.max(10, Math.min(40, E.view.s * 1.4));
		if (selected) {
			ctx.beginPath();
			ctx.arc(sx, sy, r * 0.75, 0, Math.PI * 2);
			ctx.fillStyle = "rgba(255, 255, 255, 0.35)";
			ctx.fill();
			ctx.lineWidth = 2;
			ctx.strokeStyle = "#fff";
			ctx.stroke();
		}
		ctx.drawImage(img, sx - r, sy - r, r * 2, r * 2);
		const a = ((o.yaw || 0) * Math.PI) / 180;  // (which way it faces)
		ctx.beginPath();
		ctx.moveTo(sx + Math.sin(a) * r * 0.5, sy + Math.cos(a) * r * 0.5);
		ctx.lineTo(sx + Math.sin(a) * r * 0.85, sy + Math.cos(a) * r * 0.85);
		ctx.lineWidth = 2;
		ctx.strokeStyle = selected ? "#fff" : "rgba(242, 209, 107, 0.9)";
		ctx.stroke();
		return true;
	};

	// --- the palette, shared by the three tools --------------------------------------------------------

	const pal = { group: "Garden", pick: "flowers", mix: ["flowers", "flower_group", "flowers_2"], facing: "random", yaw: 0, own: true,
		radius: 3, spacing: 1.6, every: 4, rowFace: "across" };

	const palette = (box, multi) => {
		const gs = groups();
		if (!gs.some(([g]) => g === pal.group)) pal.group = gs[0][0];
		const g = el("select", { onchange: () => { pal.group = g.value; E.setTool(E.tool); } }, ...gs.map(([k]) => el("option", { value: k }, k)));
		g.value = pal.group;
		const strip = el("span", { class: "palette" });
		for (const id of gs.find(([k]) => k === pal.group)[1]) {
			const b = el("button", {
				class: (multi ? pal.mix.includes(id) : id === pal.pick) ? "on" : "",
				title: label(id) + (multi ? " (click: just this; Shift-click: add to or take out of the mix)" : ""),
				onclick: (ev) => {
					if (multi && ev.shiftKey) pal.mix = pal.mix.includes(id) ? pal.mix.filter((x) => x !== id) : [...pal.mix, id];
					else { pal.mix = [id]; pal.pick = id; }
					if (!pal.mix.length) pal.mix = [id];
					pal.pick = multi ? pal.mix[0] : id;
					E.setTool(E.tool);
				},
			}, el("img", { src: `icons/${id}.png`, alt: label(id) }));
			strip.append(b);
		}
		box.append(g, strip);
		if (multi) box.append(el("span", { class: "muted" }, `mix: ${pal.mix.map(label).join(", ")}`));
	};
	const ownBox = (box) => {
		const c = el("input", { type: "checkbox" });
		c.checked = pal.own;
		c.onchange = () => { pal.own = c.checked; };
		box.append(el("label", { class: "row", title: `Put down within ${OWN_REACH} m of a building, it belongs to it and moves with it` }, c, "belong to the nearest house"));
	};
	const facingBox = (box, opts) => {
		const s = el("select", { onchange: () => { pal.facing = s.value; } }, ...opts.map(([k, l]) => el("option", { value: k }, l)));
		s.value = opts.some(([k]) => k === pal.facing) ? pal.facing : opts[0][0];
		pal.facing = s.value;
		box.append(el("span", { class: "muted" }, "facing"), s);
	};
	const sep = (box) => box.append(el("span", { class: "sep" }));

	/** A new decoration point at (x, z): owned by the nearest building if close enough. */
	const put = (type, x, z, yaw) => {
		const o = { id: E.uniqueId(type), type, at: [E.round(x), E.round(z)], yaw: Math.round(((yaw % 360) + 540) % 360 - 180) };
		const v = E.villageArea ? E.villageArea() : null;
		if (v) o.area = v.id;
		if (pal.own && E.nearestBuilding) {
			const b = E.nearestBuilding(x, z, OWN_REACH);
			if (b) o.owner = b.id;
		}
		E.layout.points.push(o);
		return o;
	};
	const yawFor = (x, z) => (pal.facing === "random" ? Math.random() * 360 : pal.facing === "street" ? (E.faceStreet ? E.faceStreet(x, z) ?? pal.yaw : pal.yaw) : pal.yaw);
	const pickMix = () => pal.mix[Math.floor(Math.random() * pal.mix.length)];
	const ghost = (ctx, id, x, z, scale = 1) => {
		const img = icon(id);
		const [sx, sy] = E.toScreen(x, z);
		const r = Math.max(10, Math.min(40, E.view.s * 1.4)) * scale;
		ctx.globalAlpha = 0.7;
		if (img) ctx.drawImage(img, sx - r, sy - r, r * 2, r * 2);
		ctx.globalAlpha = 1;
	};

	// --- Stamp -----------------------------------------------------------------------------------------

	let hover = null;
	E.registerTool({
		id: "stamp",
		label: "Stamp",
		modes: ["town"],
		title: "Put decorations down one at a time, from the pictures",
		options(box) {
			palette(box, false);
			sep(box);
			facingBox(box, [["random", "any way"], ["street", "the street"], ["fixed", "as set (R turns)"]]);
			ownBox(box);
		},
		hint: () => `Click to put down ${label(pal.pick)}. R turns the next one 15°${pal.facing === "fixed" ? ` (now ${pal.yaw}°)` : ""}. Esc: back to Select.`,
		move(x, z) { hover = [x, z]; },
		down(x, z) {
			E.commit();
			const o = put(pal.pick, x, z, yawFor(x, z));
			E.select("points", o);
			E.changed();
		},
		keydown(ev) {
			if (ev.key.toLowerCase() === "r") { pal.facing = "fixed"; pal.yaw = (pal.yaw + (ev.shiftKey ? -15 : 15) + 360) % 360; E.setTool(E.tool); return true; }
			if (ev.key === "Escape") { E.setTool(null); return true; }
			return false;
		},
		preview(ctx) { if (hover) ghost(ctx, pal.pick, hover[0], hover[1]); },
	});

	// --- Scatter ---------------------------------------------------------------------------------------

	let painting = false;
	const sprinkle = (x, z) => {
		const near = (px, pz) => E.layout.points.some((p) => E.dist(px, pz, p.at[0], p.at[1]) < pal.spacing);
		for (let tries = 0; tries < 6; tries++) {
			const a = Math.random() * Math.PI * 2, d = Math.sqrt(Math.random()) * pal.radius;
			const px = x + Math.cos(a) * d, pz = z + Math.sin(a) * d;
			if (near(px, pz) || (E.buildingCorners && (E.layout.anchors || []).some((b) => b.placed !== false && b.id !== "green" && E.inPoly(px, pz, E.buildingCorners(b))))) continue;
			put(pickMix(), px, pz, pal.facing === "random" ? Math.random() * 360 : yawFor(px, pz));
		}
	};
	E.registerTool({
		id: "scatter",
		label: "Scatter",
		modes: ["town"],
		title: "Brush a loose mix of decorations (flowers along a hedge, hay round a barn)",
		options(box) {
			palette(box, true);
			sep(box);
			const num = (key, min, step, title) => {
				const i = el("input", { type: "number", min: String(min), step: String(step), value: pal[key], title });
				i.onchange = () => { pal[key] = Math.max(min, Number(i.value)); };
				return i;
			};
			box.append(el("span", { class: "muted" }, "brush (m)"), num("radius", 0.5, 0.5, "How wide the brush is"),
				el("span", { class: "muted" }, "apart (m)"), num("spacing", 0.5, 0.1, "How close two things may be"));
			facingBox(box, [["random", "any way"], ["street", "the street"]]);
			ownBox(box);
		},
		hint: () => `Drag to sprinkle ${pal.mix.map(label).join(", ")}: a ${pal.radius} m brush, ${pal.spacing} m apart. Shift-click pictures to change the mix.`,
		down(x, z) { E.commit(); painting = true; sprinkle(x, z); E.draw(); },
		move(x, z) { hover = [x, z]; if (painting) sprinkle(x, z); },
		up() { if (painting) { painting = false; E.changed(true); } },
		cancel() { painting = false; },
		preview(ctx) {
			if (!hover) return;
			const [sx, sy] = E.toScreen(hover[0], hover[1]);
			ctx.beginPath();
			ctx.arc(sx, sy, pal.radius * E.view.s, 0, Math.PI * 2);
			ctx.setLineDash([4, 4]);
			ctx.lineWidth = 1.5;
			ctx.strokeStyle = "#fff";
			ctx.stroke();
			ctx.setLineDash([]);
		},
	});

	// --- Row -------------------------------------------------------------------------------------------

	let corners = [];
	/** Spots every `every` m along `pts` (half a step in from the start): [[x, z, angle of the line]]. */
	const along = (pts, every) => {
		const out = [];
		let carry = every / 2;
		for (let i = 1; i < pts.length; i++) {
			const [ax, az] = pts[i - 1], [bx, bz] = pts[i];
			const len = E.dist(ax, az, bx, bz), dir = Math.atan2(bx - ax, bz - az) * 180 / Math.PI;
			let t = carry;
			while (t <= len) { out.push([ax + (bx - ax) * t / len, az + (bz - az) * t / len, dir]); t += every; }
			carry = t - len;
		}
		return out;
	};
	const rowYaw = (dir) => (pal.rowFace === "along" ? dir : pal.rowFace === "across" ? dir + 90 : pal.rowFace === "across2" ? dir - 90 : Math.random() * 360);
	const finishRow = () => {
		if (corners.length >= 2) {
			E.commit();
			const made = [];
			let k = 0;
			for (const [x, z, dir] of along(corners, pal.every)) made.push(put(pal.mix[k++ % pal.mix.length], x, z, rowYaw(dir)));
			E.sel = made.map((o) => ({ kind: "points", obj: o }));
			E.changed();
			E.status(`${made.length} in a row.`, "ok");
		}
		corners = [];
		E.updateHint();
	};
	E.registerTool({
		id: "row",
		label: "Row",
		modes: ["town"],
		title: "A row of decorations along a line (lamps down the street, planters by a wall)",
		options(box) {
			palette(box, true);
			sep(box);
			const i = el("input", { type: "number", min: "0.5", step: "0.5", value: pal.every, title: "One every this many metres" });
			i.onchange = () => { pal.every = Math.max(0.5, Number(i.value)); };
			const f = el("select", { onchange: () => { pal.rowFace = f.value; } },
				...[["across", "across it (one side)"], ["across2", "across it (the other)"], ["along", "along it"], ["random", "any way"]].map(([k, l]) => el("option", { value: k }, l)));
			f.value = pal.rowFace;
			box.append(el("span", { class: "muted" }, "every (m)"), i, el("span", { class: "muted" }, "facing"), f);
			ownBox(box);
		},
		hint: () => (corners.length
			? `${along(corners, pal.every).length} so far along ${Math.round(E.polyLength(corners))} m: click to go on, double-click / Enter to put them down, Esc to drop it`
			: `Click along where the row runs: ${pal.mix.map(label).join(", ")}, one every ${pal.every} m (taking turns if there are several).`),
		down(x, z) { corners.push([x, z]); E.updateHint(); },
		move(x, z) { hover = [x, z]; },
		dblclick() {
			const n = corners.length;
			if (n >= 2 && E.dist(...corners[n - 1], ...corners[n - 2]) < 6 / E.view.s) corners.pop();
			finishRow();
		},
		finish: finishRow,
		cancel() { corners = []; E.updateHint(); },
		keydown(ev) {
			if (ev.key === "Backspace" && corners.length) { corners.pop(); E.updateHint(); return true; }
			return false;
		},
		preview(ctx) {
			if (!corners.length) return;
			const pts = hover ? [...corners, hover] : corners;
			E.path(pts, false);
			ctx.setLineDash([6, 4]);
			ctx.lineWidth = 1.5;
			ctx.strokeStyle = "#fff";
			ctx.stroke();
			ctx.setLineDash([]);
			let k = 0;
			for (const [x, z] of along(pts, pal.every)) ghost(ctx, pal.mix[k++ % pal.mix.length], x, z, 0.8);
		},
	});
})();
