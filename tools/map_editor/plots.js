// Plots (plans/town-designer.md, phase 4): a house's back garden, {id, owner?, points, edge, gate:
// [edge index, width], fill, seed}. The bake (tools/bake_layout.gd, scripts/town_plots.gd) edges it
// with a hedge, fence or wall, the gate a gap in the middle of one edge, fills it with its garden's
// things and keeps scattered trees and rocks out. Owned by a building, it moves and turns with it.
// The Plot tool (town mode): click its corners; it belongs to the nearest building, its gate on the
// edge nearest that building's middle.
"use strict";

(() => {
	const E = Editor;
	const el = (...a) => E.el(...a);
	const EDGES = [["hedge", "Hedge"], ["fence", "Fence"], ["wall", "Stone wall"], ["low_wall", "Tumbledown wall"], ["none", "Nothing (open)"]];

	const edgeColor = (o) => (o.edge === "none" ? "#cfc6a8" : (E.catalog.lines[o.edge || "hedge"] || {}).color || "#4f7d3a");
	const garden = (o) => (E.catalog.gardens || {})[o.fill] || null;

	/** The runs of its edge with the gate left out (as town_plots.gd's edge_runs). */
	const edgeRuns = (o) => {
		const pts = o.points, n = pts.length;
		if (n < 3) return [];
		if (!Array.isArray(o.gate)) return [[...pts, pts[0]]];
		const i = ((o.gate[0] % n) + n) % n, a = pts[i], b = pts[(i + 1) % n];
		const len = E.dist(a[0], a[1], b[0], b[1]), half = Math.min(o.gate[1], len) / 2;
		const mid = [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2], d = len ? [(b[0] - a[0]) / len, (b[1] - a[1]) / len] : [0, 0];
		const run = [[mid[0] + d[0] * half, mid[1] + d[1] * half]];
		for (let k = 1; k <= n; k++) run.push(pts[(i + k) % n]);
		run.push([mid[0] - d[0] * half, mid[1] - d[1] * half]);
		return [run];
	};
	/** The edge (index) whose middle is nearest (x, z). */
	const nearestEdge = (pts, x, z) => {
		let best = 0, bd = Infinity;
		for (let i = 0; i < pts.length; i++) {
			const a = pts[i], b = pts[(i + 1) % pts.length];
			const d = E.dist(x, z, (a[0] + b[0]) / 2, (a[1] + b[1]) / 2);
			if (d < bd) { bd = d; best = i; }
		}
		return best;
	};
	const middle = (pts) => [pts.reduce((s, p) => s + p[0], 0) / pts.length, pts.reduce((s, p) => s + p[1], 0) / pts.length];

	E.registerKind("plots", {
		label: "Plot",
		title: (o) => `${o.name || o.id}  ·  ${(garden(o) || { label: "plot" }).label}, ${Math.round(E.polyArea(o.points))} m²`,
		color: (o) => (garden(o) || {}).color || edgeColor(o),
		draw(ctx, o, selected) {
			if (!o.points || o.points.length < 3) return;
			E.path(o.points, true);
			const g = garden(o);
			ctx.fillStyle = (g ? g.color : "#8a8a6a") + (selected ? "55" : "33");
			ctx.fill();
			if (g && E.view.s > 1.5) {  // its rows, roughly (the bake places the things)
				ctx.save();
				E.path(o.points, true);
				ctx.clip();
				ctx.strokeStyle = g.color + "88";
				ctx.lineWidth = 1;
				const [cx, cz] = middle(o.points);
				const step = (g.spacing || 3) * E.view.s, [sx, sy] = E.toScreen(cx, cz), r = 80 * E.view.s;
				ctx.beginPath();
				for (let y = -r; y < r; y += step) { ctx.moveTo(sx - r, sy + y); ctx.lineTo(sx + r, sy + y); }
				ctx.stroke();
				ctx.restore();
			}
			ctx.lineCap = "round";
			ctx.lineJoin = "round";
			for (const run of edgeRuns(o)) {
				E.path(run, false);
				ctx.lineWidth = Math.max(2.5, E.view.s * 1.0) + (selected ? 3 : 0);
				ctx.strokeStyle = selected ? "#fff" : "rgba(20, 20, 15, 0.6)";
				ctx.stroke();
				ctx.lineWidth = Math.max(1.5, E.view.s * 0.9);
				ctx.strokeStyle = edgeColor(o);
				if (o.edge === "none") ctx.setLineDash([4, 4]);
				ctx.stroke();
				ctx.setLineDash([]);
			}
			if (o.owner && selected) {  // a thread to its house
				const a = (E.layout.anchors || []).find((x) => x.id === o.owner);
				if (a) {
					const [mx, mz] = middle(o.points);
					E.path([[mx, mz], a.at], false);
					ctx.setLineDash([3, 4]);
					ctx.lineWidth = 1;
					ctx.strokeStyle = "#fff";
					ctx.stroke();
					ctx.setLineDash([]);
				}
			}
		},
		hit(o, x, z, tol) {
			if (!o.points || o.points.length < 3) return false;
			let best = Infinity;
			for (let i = 0; i < o.points.length; i++) best = Math.min(best, E.segDist(x, z, ...o.points[i], ...o.points[(i + 1) % o.points.length]));
			if (best < tol) return best;
			return E.inPoly(x, z, o.points) ? 1 + E.polyArea(o.points) / 1000 : false;  // (inside: under the things on it)
		},
		handles(o) {
			return o.points.map((p, i) => ({
				x: p[0], z: p[1],
				set: (x, z) => { o.points[i] = [x, z]; },
				remove: o.points.length > 3 ? () => { o.points.splice(i, 1); if (Array.isArray(o.gate) && o.gate[0] >= o.points.length) o.gate[0] = 0; } : null,
			}));
		},
		move(o, dx, dz) { o.points = o.points.map((p) => [p[0] + dx, p[1] + dz]); },
		insertAt(o, x, z, tol) {
			for (let i = 0; i < o.points.length; i++) {
				const a = o.points[i], b = o.points[(i + 1) % o.points.length];
				if (E.segDist(x, z, a[0], a[1], b[0], b[1]) < tol) {
					o.points.splice(i + 1, 0, [E.round(x), E.round(z)]);
					if (Array.isArray(o.gate) && o.gate[0] > i) o.gate[0] += 1;
					return true;
				}
			}
			return false;
		},
		panel(o, box) {
			box.append(E.field("Name", E.input(o, "name", "text", { default: "" })));
			if (E.ownerField) box.append(E.ownerField(o));
			box.append(E.field("Edged with", E.input(o, "edge", "select", { options: EDGES, default: "hedge" })));
			const gate = Array.isArray(o.gate);
			const hasGate = el("input", { type: "checkbox" });
			hasGate.checked = gate;
			hasGate.onchange = () => { E.commit(); if (hasGate.checked) o.gate = [0, 2.5]; else delete o.gate; E.changed(); };
			const turnGate = (d) => () => { E.commit(); o.gate = [((o.gate[0] + d) % o.points.length + o.points.length) % o.points.length, o.gate[1]]; E.changed(); };
			const width = el("input", { type: "number", step: "0.5", min: "1", value: gate ? o.gate[1] : 2.5 });
			width.onchange = () => { E.commit(); o.gate = [o.gate[0], Math.max(1, Number(width.value))]; E.changed(true); };
			box.append(E.field("Gate", el("span", { class: "row" }, hasGate,
				gate ? el("button", { title: "Move the gate to the edge before", onclick: turnGate(-1) }, "◀") : null,
				gate ? el("button", { title: "Move the gate to the next edge", onclick: turnGate(1) }, "▶") : null,
				gate ? width : null, gate ? "m" : null)));
			const fills = [["none", "Nothing (grass)"], ...Object.keys(E.catalog.gardens || {}).map((k) => [k, E.catalog.gardens[k].label])];
			box.append(E.field("Filled with", E.input(o, "fill", "select", { options: fills, default: "none", refresh: true })));
			if (garden(o)) box.append(E.field("Layout", el("span", { class: "row" }, el("span", { class: "muted" }, `seed ${o.seed}`),
				el("button", { title: "Lay its things out afresh", onclick: () => { E.commit(); o.seed = Math.floor(Math.random() * 1e6); E.changed(); } }, "Shuffle"))));
			box.append(E.field("Size", el("span", {}, `${Math.round(E.polyArea(o.points))} m², ${o.points.length} corners`)));
			box.append(el("p", { class: "muted" }, "A garden plot: its edge is built round it with the gate left open, its garden's things are placed inside on Save & bake, and no scattered tree or rock grows in it. Drag a corner to reshape it, double-click an edge to add one, Alt-click to take one away."));
		},
	});

	// --- the Plot tool ---------------------------------------------------------------------------------

	const brush = { edge: "hedge", fill: "veg" };
	let corners = [];
	let hover = null;

	const finish = () => {
		if (corners.length >= 3 && E.polyArea(corners) >= 6) {
			const [cx, cz] = middle(corners);
			const owner = E.nearestBuilding ? E.nearestBuilding(cx, cz, 25) : null;
			const o = { id: E.uniqueId("plot"), points: corners.map((p) => [E.round(p[0]), E.round(p[1])]), edge: brush.edge, fill: brush.fill, seed: Math.floor(Math.random() * 1e6) };
			const toward = owner ? owner.at : [cx, cz];
			o.gate = [nearestEdge(o.points, toward[0], toward[1]), 2.5];
			if (owner) o.owner = owner.id;
			const v = E.villageArea ? E.villageArea() : null;
			if (v) o.area = v.id;
			E.commit();
			E.layout.plots.push(o);
			E.select("plots", o);
			E.changed();
			if (owner) E.status(`A plot for ${E.buildingShape(owner).name}: it moves with it.`, "ok");
		}
		corners = [];
		E.updateHint();
	};

	E.registerTool({
		id: "plot",
		label: "Plot",
		modes: ["town"],
		title: "Draw a garden plot behind a house: hedged, gated, planted",
		options(box) {
			const e = el("select", {}, ...EDGES.map(([k, l]) => el("option", { value: k }, l)));
			e.value = brush.edge;
			e.onchange = () => { brush.edge = e.value; };
			const f = el("select", {}, el("option", { value: "none" }, "Nothing (grass)"), ...Object.keys(E.catalog.gardens || {}).map((k) => el("option", { value: k }, E.catalog.gardens[k].label)));
			f.value = brush.fill;
			f.onchange = () => { brush.fill = f.value; };
			box.append(el("span", { class: "muted" }, "edged with"), e, el("span", { class: "muted" }, "filled with"), f);
		},
		hint: () => (corners.length
			? `${corners.length} corners, ${Math.round(E.polyArea(corners))} m²: click to add, double-click / Enter to finish, Backspace to take one back, Esc to drop it`
			: "Click round the plot's corners (it belongs to the nearest house; its gate faces it)."),
		down(x, z) { corners.push([x, z]); E.updateHint(); },
		move(x, z) { hover = [x, z]; },
		dblclick() {
			const n = corners.length;
			if (n >= 2 && E.dist(...corners[n - 1], ...corners[n - 2]) < 6 / E.view.s) corners.pop();
			finish();
		},
		finish,
		cancel() { corners = []; E.updateHint(); },
		keydown(ev) {
			if (ev.key === "Backspace" && corners.length) { corners.pop(); E.updateHint(); return true; }
			return false;
		},
		preview(ctx) {
			if (!corners.length) return;
			const pts = hover ? [...corners, hover] : corners;
			E.path(pts, pts.length > 2);
			ctx.fillStyle = "rgba(123, 154, 69, 0.2)";
			if (pts.length > 2) ctx.fill();
			ctx.setLineDash([6, 4]);
			ctx.lineWidth = 1.5;
			ctx.strokeStyle = "#fff";
			ctx.stroke();
			ctx.setLineDash([]);
		},
	});
	E.plotEdgeRuns = edgeRuns;
})();
