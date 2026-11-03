// Areas and names (plans/map-maker.md, phase 5): the map's big places, one of each type, and the
// names written on the map.
//   areas   {id, type, at: [x, z], yaw (degrees), name?, radius? / radii? [x, z]}: the village and its
//           bowl, the clearing, the lake's basin, Frostpeak, Greystone Quarry, Goldmeadow, the
//           Pinewood. Each shapes the land round it (tools/generate_test_terrain.gd), is a biome
//           (its mood, music and card), and has its name on the map. WorldMap.AREAS has their sizes.
//   labels  {id, name, at}: a name on the map where nothing else is.
// The Areas tool places one of those not on the map yet; drag one to move it, its round handle to
// turn it, its square one to size it. Moving or sizing one regenerates the land on Save & bake.
"use strict";

(() => {
	const E = Editor;
	const el = (...a) => E.el(...a);
	// (WorldMap.AREAS: name, colour, how it's sized, and its sizes unless it says)
	const TYPES = {
		village: { label: "Hearthvale (the village)", color: "#d9a441", radius: 72, ring: 250, sized: false,
			about: "The village's flat (72 m) in a wide bowl rising to a rim (dashed, 250 m). Its buildings, green and lanes go with it." },
		clearing: { label: "The Clearing", color: "#a6c77a", radius: 28, sized: true,
			about: "A flat clearing in the hills, the hills easing up round it over ~55 m." },
		lake: { label: "Stillwater (the lake)", color: "#5d9fd0", radius: 34, sized: true,
			about: "The lake's flat basin, the hills easing up round it. Its water is a pond (Terrain tool) in it." },
		frostpeak: { label: "Frostpeak", color: "#c9ced6", radius: 76, sized: true, turns: true,
			about: "One broad mountain, its spurs running out from the summit (snow up high, rock on the crags). Turn it to turn its spurs." },
		quarry: { label: "Greystone Quarry", color: "#a49a8c", radius: 65, sized: false, turns: true,
			about: "A five-level pit cut into a raised shoulder, its haul road spiralling down from the notch (the mine's under its floor). Turn it to move where the haul road starts." },
		goldmeadow: { label: "Goldmeadow", color: "#e6cf6e", radius: 97, sized: true, turns: true,
			about: "A plain of gentle swells, crop squares and dirt tracks, up on the hills. Turn it to turn the fields' grid." },
		pinewood: { label: "The Pinewood", color: "#3e7a4c", radii: [172, 108], sized: true, turns: true,
			about: "A forest floor over an ellipse (its trees are patches), its three glades flattened along the trail." },
	};
	const QUARRY_ROAD_ANGLE = -0.4636;  // (WorldMap's: where the haul road's top is, from the middle)
	const yawOf = (o) => (o.yaw || 0) * Math.PI / 180;
	/** A point `lx, lz` in area `o`'s own frame, on the map (a turn about +Y, as Godot does it). */
	const toMap = (o, lx, lz) => {
		const a = yawOf(o), c = Math.cos(a), s = Math.sin(a);
		return [o.at[0] + lx * c + lz * s, o.at[1] - lx * s + lz * c];
	};
	const radius = (o) => o.radius ?? TYPES[o.type].radius;
	const radii = (o) => o.radii || TYPES[o.type].radii;
	/** Its outline, on the map. */
	const outline = (o, grow = 0) => {
		const pts = [];
		for (let k = 0; k < 48; k++) {
			const t = (k / 48) * Math.PI * 2;
			if (o.type === "pinewood") {
				const [rx, rz] = radii(o);
				pts.push(toMap(o, Math.cos(t) * (rx + grow), Math.sin(t) * (rz + grow)));
			} else pts.push(toMap(o, Math.cos(t) * (radius(o) + grow), Math.sin(t) * (radius(o) + grow)));
		}
		return pts;
	};
	const nameOf = (o) => o.name || TYPES[o.type].label.replace(/ \(.*\)$/, "");
	/** Where its turn handle is: the quarry's haul road top, the others' local +Z edge. */
	const turnAt = (o) => {
		if (o.type === "quarry") {
			const a = QUARRY_ROAD_ANGLE - yawOf(o);  // (the map angle of the haul road's top)
			return [o.at[0] + Math.cos(a) * 65, o.at[1] + Math.sin(a) * 65];
		}
		return toMap(o, 0, (o.type === "pinewood" ? radii(o)[1] : radius(o)) + 12);
	};

	E.registerKind("areas", {
		label: "Area",
		title: (o) => `${nameOf(o)}  ·  ${o.type}`,
		color: (o) => TYPES[o.type].color,
		draw(ctx, o, selected) {
			const t = TYPES[o.type];
			if (o.type === "village") {  // the bowl's rim, faintly
				const [sx, sy] = E.toScreen(o.at[0], o.at[1]);
				ctx.beginPath();
				ctx.arc(sx, sy, t.ring * E.view.s, 0, Math.PI * 2);
				ctx.setLineDash([3, 6]);
				ctx.lineWidth = 1;
				ctx.strokeStyle = t.color + "88";
				ctx.stroke();
				ctx.setLineDash([]);
			}
			E.path(outline(o), true);
			ctx.fillStyle = t.color + (selected ? "38" : "1e");
			ctx.fill();
			ctx.lineWidth = selected ? 2.5 : 1.5;
			ctx.setLineDash([8, 4]);
			ctx.strokeStyle = selected ? "#fff" : t.color;
			ctx.stroke();
			ctx.setLineDash([]);
			if (t.turns) {  // which way it faces
				const [x, z] = turnAt(o);
				const [ax, ay] = E.toScreen(o.at[0], o.at[1]), [bx, by] = E.toScreen(x, z);
				ctx.beginPath();
				ctx.moveTo(ax, ay);
				ctx.lineTo(bx, by);
				ctx.lineWidth = 1;
				ctx.strokeStyle = (selected ? "#ffffff" : t.color) + "99";
				ctx.stroke();
			}
			const [sx, sy] = E.toScreen(o.at[0], o.at[1]);
			ctx.font = "600 14px system-ui, sans-serif";
			ctx.textAlign = "center";
			ctx.lineWidth = 3;
			ctx.strokeStyle = "rgba(20, 20, 15, 0.85)";
			ctx.strokeText(nameOf(o), sx, sy);
			ctx.fillStyle = "#f6edd3";
			ctx.fillText(nameOf(o), sx, sy);
		},
		hit(o, x, z, tol) {
			const pts = outline(o);
			if (E.inPoly(x, z, pts)) return E.polyArea(pts) * 10;  // (inside: under anything smaller on it)
			let best = Infinity;
			for (let i = 0; i < pts.length; i++) best = Math.min(best, E.segDist(x, z, ...pts[i], ...pts[(i + 1) % pts.length]));
			return best < tol ? best : false;
		},
		handles(o) {
			const t = TYPES[o.type];
			const hs = [{ x: o.at[0], z: o.at[1], set: (x, z) => E.moveArea(o, [x, z], o.yaw || 0) }];
			if (t.turns) {
				const [tx, tz] = turnAt(o);
				hs.push({
					x: tx, z: tz, round: true,
					set: (x, z, ev) => {
						let deg;
						if (o.type === "quarry") deg = (QUARRY_ROAD_ANGLE - Math.atan2(z - o.at[1], x - o.at[0])) * 180 / Math.PI;
						else deg = Math.atan2(x - o.at[0], z - o.at[1]) * 180 / Math.PI;
						if (!(ev && ev.shiftKey)) deg = Math.round(deg / 15) * 15;
						E.moveArea(o, o.at, ((Math.round(deg * 100) / 100) % 360 + 540) % 360 - 180);
					},
				});
			}
			if (t.sized && o.type === "pinewood") {
				const [rx, rz] = radii(o);
				const [ax, az] = toMap(o, rx, 0), [bx, bz] = toMap(o, 0, -rz);
				const local = (x, z) => {  // (the point in its own frame)
					const a = yawOf(o), c = Math.cos(a), s = Math.sin(a), dx = x - o.at[0], dz = z - o.at[1];
					return [dx * c - dz * s, dx * s + dz * c];
				};
				hs.push({ x: ax, z: az, set: (x, z) => { o.radii = [E.round(Math.max(30, Math.abs(local(x, z)[0]))), radii(o)[1]]; } });
				hs.push({ x: bx, z: bz, set: (x, z) => { o.radii = [radii(o)[0], E.round(Math.max(30, Math.abs(local(x, z)[1])))]; } });
			} else if (t.sized) {
				const [rx, rz] = toMap(o, radius(o), 0);
				hs.push({ x: rx, z: rz, set: (x, z) => { o.radius = E.round(Math.max(10, E.dist(x, z, o.at[0], o.at[1]))); } });
			}
			return hs;
		},
		move(o, dx, dz) { E.moveArea(o, [o.at[0] + dx, o.at[1] + dz], o.yaw || 0); },
		removed(o) { if (E.areaRemoved) E.areaRemoved(o); },
		panel(o, box) {
			const t = TYPES[o.type];
			const num = (value, step, onset) => {
				const i = el("input", { type: "number", step: String(step), value: String(value) });
				i.onchange = () => { E.commit(); onset(Number(i.value)); E.changed(true); };
				return i;
			};
			box.append(E.field("Name", E.input(o, "name", "text", { default: nameOf(o) })));
			box.append(E.field("What", el("span", {}, t.label)));
			box.append(E.field("x", num(o.at[0], 1, (v) => E.moveArea(o, [v, o.at[1]], o.yaw || 0))));
			box.append(E.field("z", num(o.at[1], 1, (v) => E.moveArea(o, [o.at[0], v], o.yaw || 0))));
			if (t.turns) box.append(E.field("Turn (°)", num(o.yaw || 0, 15, (v) => E.moveArea(o, o.at, ((v % 360) + 540) % 360 - 180))));
			if (t.sized && o.type === "pinewood") {
				box.append(E.field("Across (m)", num(radii(o)[0], 1, (v) => { o.radii = [Math.max(30, v), radii(o)[1]]; })));
				box.append(E.field("Deep (m)", num(radii(o)[1], 1, (v) => { o.radii = [radii(o)[0], Math.max(30, v)]; })));
			} else if (t.sized) box.append(E.field("Radius (m)", num(radius(o), 1, (v) => { o.radius = Math.max(10, v); })));
			box.append(el("p", { class: "muted" }, t.about));
			box.append(el("p", { class: "muted" }, "Its name goes on the map (here and in the game) and on the card when you walk in. Drag it to move it" +
				(t.turns ? ", its round handle to turn it (15° steps, Shift for any)" : "") + (t.sized ? ", its square one to size it" : "") +
				". The land is regenerated round it on Save & bake. Del removes it."));
		},
	});

	/** Moves and turns area `o` (what comes with it follows, phase 6: E.areaCarries). */
	E.moveArea = (o, at, yaw) => {
		const before = { at: o.at.slice(), yaw: o.yaw || 0 };
		o.at = [E.round(at[0]), E.round(at[1])];
		o.yaw = yaw;
		if (!o.yaw) delete o.yaw;
		if (E.areaCarries) E.areaCarries(o, before);
	};

	// --- names on the map -----------------------------------------------------------------------------

	E.registerKind("labels", {
		label: "Name",
		title: (o) => `${o.name || "(no name)"}  ·  name`,
		color: () => "#f3ead2",
		draw(ctx, o, selected) {
			const [sx, sy] = E.toScreen(o.at[0], o.at[1]);
			ctx.font = "italic 600 13px Georgia, serif";
			ctx.textAlign = "center";
			ctx.lineWidth = 3;
			ctx.strokeStyle = "rgba(20, 20, 15, 0.85)";
			ctx.strokeText(o.name || "…", sx, sy);
			ctx.fillStyle = selected ? "#fff" : "#f3ead2";
			ctx.fillText(o.name || "…", sx, sy);
		},
		hit(o, x, z, tol) {
			const w = ((o.name || "…").length * 7 + 8) / E.view.s, h = 10 / E.view.s;
			return Math.abs(x - o.at[0]) < w / 2 + tol && z < o.at[1] + h / 2 && z > o.at[1] - h * 1.2 ? 0 : false;
		},
		handles(o) { return [{ x: o.at[0], z: o.at[1], set: (x, z) => { o.at = [E.round(x), E.round(z)]; } }]; },
		move(o, dx, dz) { o.at = [E.round(o.at[0] + dx), E.round(o.at[1] + dz)]; },
		panel(o, box) {
			box.append(E.field("Name", E.input(o, "name")));
			box.append(el("p", { class: "muted" }, "A name written on the map (the editor's and the game's), for somewhere no area or place names: a hill, a ford, a wood."));
		},
	});

	// --- the tool ---------------------------------------------------------------------------------------

	let placing = "village";
	let hover = null;
	E.registerTool({
		id: "areas",
		label: "Areas",
		title: "Place the map's areas (the village, the quarry, the Pinewood...) and names",
		options(box) {
			const rebuild = () => { E.setTool(E.tool); };
			const row = el("span", { class: "row" });
			const have = new Set((E.layout.areas || []).map((a) => a.type));
			for (const type in TYPES) {
				const b = el("button", {
					class: type === placing ? "on" : "", disabled: have.has(type),
					title: have.has(type) ? "Already on the map: drag it to move it" : TYPES[type].about,
					onclick: () => { placing = type; rebuild(); },
				}, TYPES[type].label.replace(/ \(.*\)$/, ""));
				row.append(b);
			}
			row.append(el("button", { class: placing === "label" ? "on" : "", title: "A name written on the map", onclick: () => { placing = "label"; rebuild(); } }, "A name…"));
			box.append(row);
			const places = E.unplacedPlaces ? E.unplacedPlaces() : [];
			if (places.length) {  // (the places a map hasn't put down yet)
				const prow = el("span", { class: "row" }, el("span", { class: "muted" }, "places:"));
				for (const [id, name] of places) {
					prow.append(el("button", { class: placing === "place:" + id ? "on" : "", title: "Put it down: then drag it, turn it", onclick: () => { placing = "place:" + id; rebuild(); } }, name));
				}
				box.append(prow);
			}
			if (placing.startsWith("place:") && !places.some(([id]) => "place:" + id === placing)) placing = "label";
			if (placing !== "label" && !placing.startsWith("place:") && have.has(placing)) placing = Object.keys(TYPES).find((t) => !have.has(t)) || "label";
		},
		hint() {
			if (placing === "label") return "Click where the name goes, then type it in on the right.";
			if (placing.startsWith("place:")) return "Click where it goes; then drag it, or its round handle to turn it.";
			return `Click where ${TYPES[placing].label.replace(/ \(.*\)$/, "")} goes (its middle).`;
		},
		move(x, z) { hover = [x, z]; },
		down(x, z) {
			E.commit();
			if (placing.startsWith("place:")) {
				const p = E.placePlace(placing.slice(6), x, z);
				if (p) { E.select("anchors", p); E.changed(); }
				E.setTool(E.tool);
				return;
			}
			if (placing === "label") {
				const o = { id: E.uniqueId("name"), name: "", at: [E.round(x), E.round(z)] };
				E.layout.labels.push(o);
				E.select("labels", o);
				E.changed();
				const first = document.querySelector("#props input[type=text]");
				if (first) first.focus();
				return;
			}
			const o = { id: placing, type: placing, at: [E.round(x), E.round(z)] };
			E.layout.areas.push(o);
			if (E.areaPlaced) E.areaPlaced(o);  // (its starter patches and what comes with it: phase 6)
			E.select("areas", o);
			E.changed();
			E.setTool(E.tool);  // (that one's placed: the palette moves on)
		},
		preview(ctx) {
			if (!hover || placing === "label" || placing.startsWith("place:")) return;
			const o = { type: placing, at: hover };
			E.path(outline(o), true);
			ctx.setLineDash([6, 5]);
			ctx.lineWidth = 1.5;
			ctx.strokeStyle = TYPES[placing].color;
			ctx.stroke();
			ctx.setLineDash([]);
		},
	});
	E.areaTypes = TYPES;
})();
