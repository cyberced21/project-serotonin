// What comes with an area (plans/map-maker.md, phase 6). A shape, line, point or building tagged
// `area: <its id>` belongs to that area: moving or turning the area carries it along, removing the
// area can take it too. Placing an area brings a copy of what Hearthvale's has (its starter
// patches, ponds and points: the quarry's rock patches, the Pinewood's trees, the clearing's
// pond and trees, Goldmeadow's fields, the gold rocks on Frostpeak), moved and turned to where it's
// put; the village brings its buildings, green and fixtures (a new map has them all, not placed:
// Maps, `placed: false`), its walkways, plots and street. The places (the watermill, the orchard,
// the shepherd's hill, the haven) are put down one by one from the Areas tool.
"use strict";

(() => {
	const E = Editor;
	const COLLECTIONS = ["patches", "terrain", "lines", "points", "plots", "labels", "anchors"];
	const PLACES = { watermill: "The watermill", orchard: "The orchard", shepherds_hill: "Shepherd's hill", haven: "The haven" };

	// a frame: where something stands and its turn (as anchors turn: about +Y)
	const frame = (at, deg) => { const a = (deg || 0) * Math.PI / 180; return { x: at[0], z: at[1], c: Math.cos(a), s: Math.sin(a), deg: deg || 0 }; };
	const toLocal = (f, p) => { const dx = p[0] - f.x, dz = p[1] - f.z; return [dx * f.c - dz * f.s, dx * f.s + dz * f.c]; };
	const toMap = (f, l) => [f.x + l[0] * f.c + l[1] * f.s, f.z - l[0] * f.s + l[1] * f.c];
	const turn = (deg) => ((deg % 360) + 540) % 360 - 180;

	/** Moves `o` from frame `a` to frame `b`: its points, middle, place and turn. */
	const shift = (o, a, b) => {
		const m = (p) => { const q = toMap(b, toLocal(a, p)); return [E.round(q[0]), E.round(q[1])]; };
		for (const k of ["points", "pools"]) if (Array.isArray(o[k])) o[k] = o[k].map(m);
		for (const k of ["center", "at", "drawn_at"]) if (Array.isArray(o[k])) o[k] = m(o[k]);
		const d = b.deg - a.deg;
		if (d && ("yaw" in o || (o.at && !o.points))) o.yaw = Math.round(turn((o.yaw || 0) + d) * 100) / 100;
	};

	/** Moves shape `x` as if it were stuck to something that went from {at, yaw} `before` to `after`
	 * (plans/town-designer.md: what a building owns goes where it goes). */
	E.carryShift = (x, before, after) => shift(x, frame(before.at, before.yaw), frame(after.at, after.yaw));
	E.toLocalFrame = (at, yaw, p) => toLocal(frame(at, yaw), p);
	E.toMapFrame = (at, yaw, l) => toMap(frame(at, yaw), l);

	/** Everything in the layout that belongs to area `o`. */
	const carried = (o) => {
		const out = [];
		for (const k of COLLECTIONS) for (const x of E.layout[k] || []) if (x.area === o.id) out.push([k, x]);
		return out;
	};

	E.areaCarries = (o, before) => {
		const a = frame(before.at, before.yaw), b = frame(o.at, o.yaw);
		for (const [, x] of carried(o)) shift(x, a, b);
	};

	/** Hearthvale's layout as it was when the editor opened: where the templates come from. */
	let home = null;
	E.loadHome = async () => {
		home = await (await fetch("/api/layout?map=hearthvale", { cache: "no-store" })).json();
	};

	E.areaPlaced = (o) => {
		if (!home) return;
		const src = (home.areas || []).find((a) => a.type === o.type);
		if (!src) return;
		const a = frame(src.at, src.yaw), b = frame(o.at, o.yaw);
		let brought = 0;
		for (const k of COLLECTIONS) {
			if (k === "anchors") continue;
			for (const t of home[k] || []) {
				if (t.area !== src.id) continue;
				const copy = JSON.parse(JSON.stringify(t));
				const taken = (E.layout[k] || []).some((x) => x.id === copy.id);
				if (taken) copy.id = E.uniqueId(copy.id.replace(/_\d+$/, ""));
				copy.area = o.id;
				shift(copy, a, b);
				E.layout[k].push(copy);
				brought++;
			}
		}
		// its buildings: the map has them (not placed yet), stood where Hearthvale has them, moved here
		for (const x of E.layout.anchors) {
			if (x.area !== src.id) continue;
			const t = (home.anchors || []).find((h) => h.id === x.id);
			if (!t) continue;
			x.at = t.at.slice();
			x.yaw = t.yaw || 0;
			shift(x, a, b);
			delete x.placed;
			x.area = o.id;
			brought++;
		}
		if (brought) E.status(`${brought} things came with it.`, "ok");
	};

	/** Removing area `o`: what came with it can go too (its buildings are kept, not placed). */
	E.areaRemoved = (o) => {
		const list = carried(o);
		if (!list.length || !confirm(`Remove what belongs to it too (${list.length} things: its patches, ponds, points${o.type === "village" ? ", walkways; its buildings are kept, not placed" : ""})?`)) return;
		for (const [k, x] of list) {
			if (k === "anchors") { x.placed = false; continue; }
			const i = E.layout[k].indexOf(x);
			if (i >= 0) E.layout[k].splice(i, 1);
		}
	};

	/** The places not put down yet, for the Areas tool: [[id, name]]. */
	E.unplacedPlaces = () => (E.layout.anchors || []).filter((x) => x.placed === false && PLACES[x.id]).map((x) => [x.id, PLACES[x.id]]);
	/** Puts place `id` down at (x, z). */
	E.placePlace = (id, x, z) => {
		const p = E.layout.anchors.find((a) => a.id === id);
		if (!p) return null;
		p.at = [E.round(x), E.round(z)];
		p.yaw = 0;
		delete p.placed;
		return p;
	};
})();
