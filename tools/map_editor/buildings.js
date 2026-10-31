// Buildings, fixtures and places (plans/map-editor-places.md): the layout's anchors, one per
// building, fixture and named place, each {id, node, at: [x, z], yaw (degrees), pad?}. Drawn as
// their footprint (tools/export_map.gd measures it in their own frame), turned; drag one to move it,
// drag its round handle to turn it (15° steps, Shift for any angle), or type in where. They're one of
// a kind: no adding, deleting or copying. Warnings as you go: buildings overlapping, a door far from
// any walkway, a road through one, one in water or on a steep slope, the mill's wheel off the creek.
"use strict";

(() => {
	const E = Editor;
	const el = (...a) => E.el(...a);
	const COLORS = { building: "#b0704f", fixture: "#9c7f5f", place: "#6f8f6a", green: "#7fa860" };
	const SNAP = 15;
	const DOOR_REACH = 4;  // (VillagePaths.DOOR_REACH: further, the door's joined straight to the nearest walkway)
	const WHEEL = [-4, 0];  // the mill's wheel, in the watermill's frame (Places/Watermill/MillWheel)

	const shape = (o) => (E.world && E.world.anchors && E.world.anchors[o.id]) || { box: [-2, -2, 2, 2], door: null, kind: "fixture", name: o.id };
	/** A point in anchor `o`'s own frame, on the map (a turn about +Y, as Godot does it). */
	const toMap = (o, lx, lz) => {
		const a = (o.yaw || 0) * Math.PI / 180, c = Math.cos(a), s = Math.sin(a);
		return [o.at[0] + lx * c + lz * s, o.at[1] - lx * s + lz * c];
	};
	const corners = (o, grow = 0) => {
		const [x0, z0, x1, z1] = shape(o).box;
		return [[x0 - grow, z0 - grow], [x1 + grow, z0 - grow], [x1 + grow, z1 + grow], [x0 - grow, z1 + grow]].map(([x, z]) => toMap(o, x, z));
	};
	const front = (o) => {
		const [, , , z1] = shape(o).box;
		return toMap(o, 0, z1 + 3);
	};
	const door = (o) => { const d = shape(o).door; return d ? toMap(o, d[0], d[1]) : null; };

	E.registerKind("anchors", {
		label: "Building",
		fixed: true,
		title: (o) => `${shape(o).name} · ${shape(o).kind}`,
		color: (o) => COLORS[shape(o).kind] || "#999",
		draw(ctx, o, selected) {
			const pts = corners(o);
			const sh = shape(o);
			E.path(pts, true);
			ctx.fillStyle = (COLORS[sh.kind] || "#999") + (sh.kind === "place" || sh.kind === "green" ? "40" : "c8");
			ctx.fill();
			ctx.lineWidth = selected ? 2.5 : 1.2;
			ctx.strokeStyle = selected ? "#fff" : "rgba(30, 20, 15, 0.8)";
			if (sh.kind === "place" || sh.kind === "green") ctx.setLineDash([5, 4]);
			ctx.stroke();
			ctx.setLineDash([]);
			// which way it faces: a notch on its front edge
			const [, z0, , z1] = sh.box;
			const tip = toMap(o, 0, z1), l = toMap(o, -1.2, z1 - 1.5), r = toMap(o, 1.2, z1 - 1.5);
			E.path([tip, l, r], true);
			ctx.fillStyle = selected ? "#fff" : "rgba(30, 20, 15, 0.75)";
			ctx.fill();
			const d = door(o);
			if (d) {
				const [sx, sy] = E.toScreen(d[0], d[1]);
				ctx.beginPath();
				ctx.arc(sx, sy, Math.max(2, E.view.s * 0.6), 0, Math.PI * 2);
				ctx.fillStyle = "#f2d16b";
				ctx.fill();
			}
			if (selected || E.view.s > 2.2 || ((sh.kind === "place" || sh.kind === "green") && E.view.s > 1.2)) {
				const [sx, sy] = E.toScreen(o.at[0], o.at[1]);
				ctx.font = "11px system-ui, sans-serif";
				ctx.textAlign = "center";
				ctx.lineWidth = 3;
				ctx.strokeStyle = "rgba(20, 20, 15, 0.8)";
				ctx.strokeText(sh.name, sx, sy + 4);
				ctx.fillStyle = "#f3ead2";
				ctx.fillText(sh.name, sx, sy + 4);
			}
			void z0;
		},
		hit(o, x, z, tol) {
			const pts = corners(o);
			if (E.inPoly(x, z, pts)) return 0.5;  // (inside: a hit, but anything thin on top of it wins)
			let best = Infinity;
			for (let i = 0; i < 4; i++) best = Math.min(best, E.segDist(x, z, ...pts[i], ...pts[(i + 1) % 4]));
			return best < tol ? best : false;
		},
		handles(o) {
			const [fx, fz] = front(o);
			return [
				{ x: o.at[0], z: o.at[1], set: (x, z) => { o.at = [E.round(x), E.round(z)]; after(); } },
				{
					x: fx, z: fz, round: true,
					set: (x, z, ev) => {
						let deg = Math.atan2(x - o.at[0], z - o.at[1]) * 180 / Math.PI;
						if (!(ev && ev.shiftKey)) deg = Math.round(deg / SNAP) * SNAP;
						o.yaw = Math.round(deg * 100) / 100;
						after();
					},
				},
			];
		},
		move(o, dx, dz) { o.at = [E.round(o.at[0] + dx), E.round(o.at[1] + dz)]; after(); },
		panel(o, box) {
			const sh = shape(o);
			const num = (value, step, onset) => {
				const i = el("input", { type: "number", step: String(step), value: String(value) });
				i.onchange = () => { E.commit(); onset(Number(i.value)); E.changed(true); after(); };
				return i;
			};
			box.append(E.field("Name", el("span", {}, sh.name)));
			box.append(E.field("Id", el("span", { class: "muted" }, `${o.id} (${o.node})`)));
			box.append(E.field("x", num(o.at[0], 0.5, (v) => { o.at = [v, o.at[1]]; })));
			box.append(E.field("z", num(o.at[1], 0.5, (v) => { o.at = [o.at[0], v]; })));
			box.append(E.field("Turn (°)", num(o.yaw || 0, SNAP, (v) => { o.yaw = ((v % 360) + 540) % 360 - 180; })));
			if (o.pad) box.append(E.field("Level ground", el("span", {}, `${o.pad} m round it`)));
			const mine = E.liveWarnings().filter((w) => w.ref === o.id);
			for (const w of mine) box.append(el("p", { class: "bad" }, "! " + w.msg));
			box.append(el("p", { class: "muted" },
				"Drag it to move it; drag the round handle to turn it (15° steps, Shift for any angle). " +
				"What belongs to it comes along (a place's sounds and animals, the kennel with your home). " +
				"Moving or turning one regenerates the land on Save & bake (its level ground, the lanes, the paths to it)."));
		},
	});

	/** After a building moves: its warnings and the panel follow. */
	const after = () => { if (E.refreshWarnings) E.refreshWarnings(); };

	// --- warnings, worked out as you go ----------------------------------------------------------

	const segsCross = (a, b, c, d) => {
		const o = (p, q, r) => Math.sign((q[0] - p[0]) * (r[1] - p[1]) - (q[1] - p[1]) * (r[0] - p[0]));
		return o(a, b, c) !== o(a, b, d) && o(c, d, a) !== o(c, d, b);
	};
	const polysTouch = (p, q) => {
		for (let i = 0; i < p.length; i++)
			for (let k = 0; k < q.length; k++)
				if (segsCross(p[i], p[(i + 1) % p.length], q[k], q[(k + 1) % q.length])) return true;
		return E.inPoly(p[0][0], p[0][1], q) || E.inPoly(q[0][0], q[0][1], p);
	};
	const solid = (o) => ["building", "fixture"].includes(shape(o).kind) || o.id === "watermill";
	const closest = (p, a, b) => {
		const dx = b[0] - a[0], dz = b[1] - a[1], l = dx * dx + dz * dz;
		const t = l ? Math.max(0, Math.min(1, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dz) / l)) : 0;
		return [a[0] + t * dx, a[1] + t * dz];
	};
	/** A map point in anchor `o`'s own frame. */
	const toLocal = (o, p) => {
		const a = (o.yaw || 0) * Math.PI / 180, c = Math.cos(a), s = Math.sin(a), dx = p[0] - o.at[0], dz = p[1] - o.at[1];
		return [dx * c - dz * s, dx * s + dz * c];
	};
	const polyDist = (x, z, pts) => {
		let best = Infinity;
		for (let i = 1; i < pts.length; i++) best = Math.min(best, E.segDist(x, z, ...pts[i - 1], ...pts[i]));
		return best;
	};

	E.liveWarnings = () => {
		const out = [];
		const list = E.layout ? E.layout.anchors || [] : [];
		if (!E.world) return out;
		const warn = (o, msg) => out.push({ msg: `${shape(o).name}: ${msg}`, at: o.at, ref: o.id });
		const walks = (E.layout.lines || []).filter((l) => (E.catalog.lines[l.type] || {}).walk);
		for (let i = 0; i < list.length; i++) {
			const a = list[i];
			if (!solid(a)) continue;
			const pa = corners(a, -0.3);  // (a hand's breadth in: touching walls are fine)
			for (let k = i + 1; k < list.length; k++) {
				const b = list[k];
				if (solid(b) && polysTouch(pa, corners(b, -0.3))) warn(a, `overlaps ${shape(b).name}`);
			}
			const d = door(a);
			if (d && walks.length) {
				let near = Infinity, at = null;
				for (const l of walks) for (let s = 1; s < l.points.length; s++) {
					const q = closest(d, l.points[s - 1], l.points[s]);
					const dd = E.dist(d[0], d[1], q[0], q[1]);
					if (dd < near) { near = dd; at = q; }
				}
				if (near > DOOR_REACH) warn(a, `its door is ${Math.round(near)} m from a walkway (villagers will cut straight across: draw a lane)`);
				else if (at && near > 1 && toLocal(a, at)[1] < shape(a).door[1] - 1)
					warn(a, "the walkway nearest its door comes from behind it (villagers would walk through it): draw the lane round to its front");
			}
			for (const r of E.world.roads || []) {
				let crossed = false;
				for (let s = 1; s < r.pts.length && !crossed; s++) {
					const p = r.pts[s - 1], q = r.pts[s];
					if (E.inPoly(p[0], p[1], pa) || [0, 1, 2, 3].some((e) => segsCross(p, q, pa[e], pa[(e + 1) % 4]))) crossed = true;
				}
				if (crossed) { warn(a, `${r.title || r.id} runs through it`); break; }
			}
			const hs = corners(a).map(([x, z]) => E.heightAt(x, z));
			if (E.heightAt(a.at[0], a.at[1]) < E.world.water_level - 0.05 && a.id !== "watermill") warn(a, "it's standing in water");
			else if (Math.max(...hs) - Math.min(...hs) > 3) warn(a, `it's on a slope (${(Math.max(...hs) - Math.min(...hs)).toFixed(1)} m from corner to corner): its level ground will cut into the hill`);
			if (a.id === "watermill" && E.world.creek) {
				const w = toMap(a, WHEEL[0], WHEEL[1]);
				const far = polyDist(w[0], w[1], E.world.creek);
				if (far > 3.3) warn(a, `its wheel is ${Math.round(far)} m from the creek: it won't turn in water there`);
			}
		}
		return out;
	};
})();
