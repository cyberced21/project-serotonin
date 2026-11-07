// Lanes that follow (plans/town-designer.md, phase 8). Walkways are the lines villagers walk along
// (VillagePaths); a door with none within DOOR_REACH gets joined straight to the nearest, which can
// cut across a garden or a house. So the designer draws a lane for each such door: `auto: true`,
// `door_of: <its building>`, from the door out past its step and on to the nearest walkway you drew
// (round a corner if the straight way crosses a building). They're redrawn after every change (a
// building moved, added or taken away, a walkway drawn); drag one and it's yours (no longer auto).
// A walkway with `follows: <road id>` takes that road's line whenever the road changes (the street's
// own walkway following the street, if you tick it).
"use strict";

(() => {
	const E = Editor;
	const DOOR_REACH = 4;  // (VillagePaths.DOOR_REACH)
	const STEP = 2.5;  // (m out from the door before the lane turns)

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
	const solids = () => (E.layout.anchors || []).filter((a) => a.placed !== false && a.id !== "green" && E.buildingShape && ["building", "fixture"].includes(E.buildingShape(a).kind))
		.map((a) => E.buildingCorners(a, -0.3));
	/** Whether the path `pts` runs through any building (a hand's breadth in from its walls). */
	const blocked = (pts, boxes) => {
		for (let i = 1; i < pts.length; i++) for (const box of boxes) {
			if (E.inPoly(...pts[i], box)) return true;
			for (let k = 0; k < 4; k++) if (cross(pts[i - 1], pts[i], box[k], box[(k + 1) % 4])) return true;
		}
		return false;
	};
	const round = (pts) => pts.map(([x, z]) => [E.round(x), E.round(z)]);

	/** The lane building `o`'s door needs, or null (it's within reach of a walkway you drew). */
	const laneFor = (o, hand, boxes) => {
		const sh = E.buildingShape(o);
		if (!sh.door) return null;
		const door = E.anchorToMap(o, sh.door[0], sh.door[1]);
		const near = nearestOn(hand, door[0], door[1]);
		if (!near || near.d <= DOOR_REACH) return null;
		const step = E.anchorToMap(o, sh.door[0], sh.door[1] + STEP);
		const to = nearestOn(hand, step[0], step[1]).at;
		const tries = [[door, step, to], [door, step, [to[0], step[1]], to], [door, step, [step[0], to[1]], to]];
		const ok = tries.find((t) => !blocked(t.slice(1), boxes)) || tries[0];
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
		const boxes = solids();
		const want = new Map();
		for (const o of E.layout.anchors || []) {
			if (o.placed === false || !E.inVillage("anchors", o)) continue;
			const pts = laneFor(o, hand, boxes);
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
