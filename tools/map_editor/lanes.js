// Lanes that follow (plans/town-designer.md, phase 8). Walkways are the lines villagers walk along
// (VillagePaths); a door with none within DOOR_REACH gets joined straight to the nearest, which can
// cut across a garden or a house. So the designer draws a lane for each such door of a building it
// added (the story's buildings keep the links the game makes, tuned with their tiers' add-ons, which
// the editor can't see): `auto: true`,
// `door_of: <its building>`, from the door out past its step and on to the nearest walkway you drew
// (round a corner if the straight way is blocked: buildings, solid props, hedges, walls and fences;
// with no clear way it draws none, and the door's warning stays). They're redrawn after every change (a
// building moved, added or taken away, a walkway drawn); drag one and it's yours (no longer auto).
// A walkway with `follows: <road id>` takes that road's line whenever the road changes (the street's
// own walkway following the street, if you tick it).
"use strict";

(() => {
	const E = Editor;
	const DOOR_REACH = 4;  // (VillagePaths.DOOR_REACH)
	const STEP = 2.5;  // (m out from the door before the lane turns)
	const BERTH = 1.0;  // (m a lane keeps off a building's walls)
	const HEDGE_BERTH = 1.1;  // (m off a hedge, wall or fence's middle: they're a metre or so thick)

	const isWalk = (l) => !!(E.catalog.lines[l.type] || {}).walk;
	const nearestOn = (lines, x, z) => {
		let best = null, bd = Infinity;
		for (const l of lines) for (let i = 1; i < l.points.length; i++) {
			const [ax, az] = l.points[i - 1], [bx, bz] = l.points[i];
			const dx = bx - ax, dz = bz - az, len = dx * dx + dz * dz;
			const t = len ? Math.max(0, Math.min(1, ((x - ax) * dx + (z - az) * dz) / len)) : 0;
			const p = [ax + t * dx, az + t * dz], d = E.dist(x, z, p[0], p[1]);
			if (d < bd) { bd = d; best = p; }
		}
		return best ? { at: best, d: bd } : null;
	};
	const cross = (a, b, c, d) => {
		const o = (p, q, r) => Math.sign((q[0] - p[0]) * (r[1] - p[1]) - (q[1] - p[1]) * (r[0] - p[0]));
		return o(a, b, c) !== o(a, b, d) && o(c, d, a) !== o(c, d, b);
	};
	/** What a lane can't go through: the buildings (with a metre's berth: their eaves and steps stand
	 * out past the box) and the solid props, the yards' among them, as boxes; the hedges, walls and
	 * fences (and the plots' edges) as runs of segments. */
	const obstacles = () => {
		const standing = (E.layout.anchors || []).filter((a) => a.placed !== false && a.id !== "green" && E.buildingShape && ["building", "fixture"].includes(E.buildingShape(a).kind));
		const boxes = standing.map((a) => E.buildingCorners(a, BERTH));
		const square = ([x, z], r) => [[x - r, z - r], [x + r, z - r], [x + r, z + r], [x - r, z + r]];
		for (const p of E.layout.points || []) {
			const c = E.catalog.props[p.type];
			if (c && c.collide) boxes.push(square(p.at, 0.8));
		}
		for (const a of standing) for (const p of (a.yard && a.yard.props) || []) if (p[3]) boxes.push(square(E.anchorToMap(a, p[1][0], p[1][1]), 1.2));
		const runs = (E.layout.lines || []).filter((l) => !isWalk(l)).map((l) => l.points);
		for (const pl of E.layout.plots || []) if (pl.edge !== "none" && E.plotEdgeRuns) runs.push(...E.plotEdgeRuns(pl));
		return { boxes, runs };
	};
	/** How far apart segments ab and cd come (0 where they cross). */
	const segSeg = (a, b, c, d) => (cross(a, b, c, d) ? 0 : Math.min(E.segDist(...a, ...c, ...d), E.segDist(...b, ...c, ...d), E.segDist(...c, ...a, ...b), E.segDist(...d, ...a, ...b)));
	/** How many things the path `pts` runs through (or, for a hedge or wall, brushes past). */
	const blocked = (pts, ob) => {
		let n = 0;
		for (let i = 1; i < pts.length; i++) {
			for (const box of ob.boxes) {
				if (E.inPoly(...pts[i], box) || [0, 1, 2, 3].some((k) => cross(pts[i - 1], pts[i], box[k], box[(k + 1) % 4]))) n++;
			}
			for (const r of ob.runs) for (let k = 1; k < r.length; k++) if (segSeg(pts[i - 1], pts[i], r[k - 1], r[k]) < HEDGE_BERTH) n++;
		}
		return n;
	};
	const round = (pts) => pts.map(([x, z]) => [E.round(x), E.round(z)]);

	/** The lane building `o`'s door needs, or null (it's within reach of a walkway you drew). */
	const laneFor = (o, hand, ob) => {
		const sh = E.buildingShape(o);
		if (!sh.door) return null;
		const door = E.anchorToMap(o, sh.door[0], sh.door[1]);
		const near = nearestOn(hand, door[0], door[1]);
		if (!near || near.d <= DOOR_REACH) return null;
		const step = E.anchorToMap(o, sh.door[0], sh.door[1] + STEP);
		// to the nearest point of each walkway, straight or round a corner; the shortest that's clear
		// (or, if none is, the one through the fewest things: the bake's check then says where)
		const tries = [];
		for (const l of hand) {
			const to = nearestOn([l], step[0], step[1]).at;
			tries.push([door, step, to], [door, step, [to[0], step[1]], to], [door, step, [step[0], to[1]], to]);
		}
		const scored = tries.map((t) => [blocked(t.slice(1), ob), E.polyLength(t), t]).sort((a, b) => a[0] - b[0] || a[1] - b[1]);
		if (!scored.length || scored[0][0] > 0) return null;  // (no clear way: the door's warning says draw one)
		const ok = scored[0][2];
		return round(ok.filter((p, i) => i === 0 || E.dist(...p, ...ok[i - 1]) > 0.3));
	};

	/** Redraws the designer's lanes and the walkways that follow a road. Returns whether anything changed. */
	E.refreshLanes = () => {
		if (!E.layout || !E.catalog || !E.buildingShape || !E.villageArea || !E.villageArea()) return false;
		let changed = false;
		const lines = E.layout.lines;
		for (const l of lines) {  // (a walkway following a road: the road's line)
			if (!l.follows || !isWalk(l)) continue;
			const road = (E.layout.terrain || []).find((t) => t.id === l.follows);
			if (road && JSON.stringify(road.points) !== JSON.stringify(l.points)) { l.points = road.points.map((p) => p.slice()); changed = true; }
		}
		const hand = lines.filter((l) => isWalk(l) && !l.auto && l.points.length >= 2);
		if (!hand.length) return changed;
		const ob = obstacles();
		const want = new Map();
		for (const o of E.layout.anchors || []) {
			if (o.placed === false || !o.type || !E.inVillage("anchors", o)) continue;
			const pts = laneFor(o, hand, ob);
			if (pts) want.set(o.id, pts);
		}
		for (let i = lines.length - 1; i >= 0; i--) {  // (lanes no door needs any more)
			const l = lines[i];
			if (l.auto && !want.has(l.door_of)) { lines.splice(i, 1); changed = true; }
		}
		const v = E.villageArea();
		for (const [id, pts] of want) {
			const l = lines.find((x) => x.auto && x.door_of === id);
			if (l) {
				if (JSON.stringify(l.points) !== JSON.stringify(pts)) { l.points = pts; changed = true; }
			} else {
				lines.push({ id: E.uniqueId("lane_" + id), type: "walkway", points: pts, auto: true, door_of: id, area: v.id });
				changed = true;
			}
		}
		return changed;
	};

	// after every change: the lanes follow (part of the same undo step)
	const changedBefore = E.changed;
	let busy = false;
	E.changed = (keepPanel) => {
		if (!busy) {
			busy = true;
			try { E.refreshLanes(); } finally { busy = false; }
		}
		changedBefore(keepPanel);
	};

	// a lane you drag is yours from then on
	const lines = E.kinds.lines;
	const beginBefore = lines.beginEdit;
	lines.beginEdit = (o) => { if (o.auto) { delete o.auto; delete o.door_of; } if (o.follows) delete o.follows; if (beginBefore) beginBefore(o); };
	const panelBefore = lines.panel;
	lines.panel = (o, box) => {
		panelBefore(o, box);
		if (!isWalk(o)) return;
		if (o.auto) box.append(E.el("p", { class: "muted" }, `Drawn by the town designer to ${E.buildingShape((E.layout.anchors || []).find((a) => a.id === o.door_of) || { id: o.door_of }).name}'s door: it's redrawn when things move. Drag it and it's yours.`));
		const street = E.townStreet ? E.townStreet() : null;
		if (street && !o.auto) box.append(E.field("Follows the street", E.input(o, "follows", "check", {
			default: false, after: (v) => { if (v) o.follows = street.id; else delete o.follows; },
		})));
	};
	const drawBefore = lines.draw;
	lines.draw = (ctx, o, selected) => {
		if (!o.auto) return drawBefore(ctx, o, selected);
		E.path(o.points, false);
		ctx.lineWidth = Math.max(1.5, E.view.s * 0.8);
		ctx.strokeStyle = selected ? "#fff" : "rgba(242, 209, 107, 0.7)";
		ctx.setLineDash([2, 3]);
		ctx.stroke();
		ctx.setLineDash([]);
	};
})();
