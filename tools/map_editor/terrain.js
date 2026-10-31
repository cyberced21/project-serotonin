// Terrain shapes (plans/map-editor.md, phase 5): what the terrain generator does to the land on
// top of its own hills, before anything stands on it.
//   flat   the land eased to `height` m inside (a polygon or a circle), over `soft` m round it
//   raise  raised by `height` m (negative: lowered): a dome in a circle, a plateau in a polygon
//   pond   dug to `depth` m below the water, a circle or an outline (deepest `shelf` m in from its
//          shore); the bake adds its water (and `fish`: a list of species). The clearing's pond and
//          the lake (ids pond, lake) are ponds here too: deepen, move or reshape them.
//   river  a line: a channel `width` m wide and `depth` m deep under the water, through a vale
//          eased down over `vale` m each side; the bake adds its water (plans/terrain-editing.md)
//   road / path   a line the generator lays a gravel road or a dirt path along
// Baking with terrain changed regenerates the land (about a minute), redraws the map, then bakes.
"use strict";

(() => {
	const E = Editor;
	const TYPES = {
		flat: { label: "Flat", color: "#d8c890" },
		raise: { label: "Hill / hollow", color: "#c08a5a" },
		pond: { label: "Pond", color: "#4f8fc0" },
		river: { label: "River", color: "#3f7fb5" },
		road: { label: "Road", color: "#e2ded2" },
		path: { label: "Path", color: "#b0875e" },
	};
	const HALF = { road: 2.5, path: 1.6 };  // (WorldMap.ROAD_HALF_WIDTH, PATH_HALF_WIDTH)
	const half = (o) => (o.type === "river" ? (o.width ?? 4) / 2 : HALF[o.type]);
	const isLine = (o) => o.type === "road" || o.type === "path" || o.type === "river";
	// A river runs smoothed through its points, as the game smooths it (WorldMap.spline: Catmull-Rom).
	const spline = (ctrl) => {
		if (ctrl.length < 3) return ctrl;
		const out = [], m = ctrl.length;
		for (let s = 0; s < m - 1; s++) {
			const p0 = ctrl[Math.max(s - 1, 0)], p1 = ctrl[s], p2 = ctrl[s + 1], p3 = ctrl[Math.min(s + 2, m - 1)];
			const steps = Math.max(1, Math.ceil(E.dist(p1[0], p1[1], p2[0], p2[1]) / 2));
			for (let k = 0; k < steps; k++) {
				const t = k / steps, t2 = t * t, t3 = t2 * t;
				out.push([0, 1].map((j) => 0.5 * (2 * p1[j] + (p2[j] - p0[j]) * t + (2 * p0[j] - 5 * p1[j] + 4 * p2[j] - p3[j]) * t2
					+ (3 * p1[j] - p0[j] - 3 * p2[j] + p3[j]) * t3)));
			}
		}
		out.push(ctrl[m - 1]);
		return out;
	};
	const isCircle = (o) => o.shape === "circle";

	const describe = (o) => {
		if (o.type === "flat") return `flat at ${o.height} m`;
		if (o.type === "raise") return o.height >= 0 ? `hill +${o.height} m` : `hollow ${o.height} m`;
		if (o.type === "pond") return `pond ${o.depth} m deep`;
		if (o.type === "river") return `river ${o.width ?? 4} m wide, ${o.depth ?? 0.8} m deep`;
		return `${o.type}, ${Math.round(E.polyLength(o.points))} m`;
	};

	E.registerKind("terrain", {
		label: "Terrain shape",
		title: (o) => `${o.name || o.id}  ·  ${describe(o)}`,
		color: (o) => TYPES[o.type].color,
		draw(ctx, o, selected) {
			const col = TYPES[o.type].color;
			if (isLine(o)) {
				const river = o.type === "river";
				ctx.lineCap = "round";
				ctx.lineJoin = "round";
				if (river) {  // its vale, faintly: where the land is eased down to it
					E.path(spline(o.points), false);
					ctx.lineWidth = (half(o) + (o.vale ?? 30)) * 2 * E.view.s;
					ctx.strokeStyle = "rgba(63, 127, 181, 0.08)";
					ctx.stroke();
				}
				E.path(river ? spline(o.points) : o.points, false);
				ctx.lineWidth = Math.max(3, half(o) * 2 * E.view.s) + (selected ? 4 : 2);
				ctx.strokeStyle = selected ? "#fff" : "rgba(20, 20, 15, 0.7)";
				ctx.stroke();
				ctx.lineWidth = Math.max(2, half(o) * 2 * E.view.s);
				ctx.strokeStyle = col;
				ctx.stroke();
				if (river && selected) {
					const [sx, sy] = E.toScreen(o.points[0][0], o.points[0][1]);
					ctx.font = "11px system-ui, sans-serif";
					ctx.fillStyle = "#fff";
					ctx.fillText(describe(o), sx + 8, sy - 8);
				}
				return;
			}
			if (isCircle(o)) {
				const [sx, sy] = E.toScreen(o.center[0], o.center[1]);
				ctx.beginPath();
				ctx.arc(sx, sy, o.radius * E.view.s, 0, Math.PI * 2);
			} else E.path(o.points, true);
			ctx.fillStyle = o.type === "pond" ? "rgba(70, 130, 190, 0.55)" : o.type === "raise"
				? (o.height >= 0 ? "rgba(200, 140, 90, 0.22)" : "rgba(60, 70, 120, 0.25)") : "rgba(230, 215, 150, 0.22)";
			ctx.fill();
			ctx.lineWidth = selected ? 2.5 : 1.5;
			ctx.setLineDash([2, 3]);
			ctx.strokeStyle = selected ? "#fff" : col;
			ctx.stroke();
			// the soft edge
			if (o.type !== "pond" && (o.soft ?? 10) > 0) {
				ctx.setLineDash([1, 5]);
				ctx.lineWidth = 1;
				if (isCircle(o)) {
					const [sx, sy] = E.toScreen(o.center[0], o.center[1]);
					ctx.beginPath();
					ctx.arc(sx, sy, (o.radius + (o.soft ?? 10)) * E.view.s, 0, Math.PI * 2);
					ctx.stroke();
				}
			}
			ctx.setLineDash([]);
			const [x, z] = isCircle(o) ? o.center : o.points.reduce((a, p) => [a[0] + p[0] / o.points.length, a[1] + p[1] / o.points.length], [0, 0]);
			const [sx, sy] = E.toScreen(x, z);
			ctx.font = "11px system-ui, sans-serif";
			ctx.textAlign = "center";
			ctx.lineWidth = 3;
			ctx.strokeStyle = "rgba(15, 15, 10, 0.75)";
			ctx.strokeText(describe(o), sx, sy + 4);
			ctx.fillStyle = "#fff";
			ctx.fillText(describe(o), sx, sy + 4);
		},
		hit(o, x, z, tol) {
			if (isLine(o)) {
				let best = Infinity;
				for (let i = 1; i < o.points.length; i++) {
					const a = o.points[i - 1], b = o.points[i];
					best = Math.min(best, E.segDist(x, z, a[0], a[1], b[0], b[1]));
				}
				return best < tol + half(o) ? best : false;
			}
			if (isCircle(o)) return E.dist(x, z, o.center[0], o.center[1]) <= o.radius + tol ? Math.PI * o.radius * o.radius : false;
			return E.inPoly(x, z, o.points) ? E.polyArea(o.points) : false;
		},
		handles(o) {
			if (isCircle(o)) {
				return [
					{ x: o.center[0], z: o.center[1], round: true, set: (x, z) => { o.center = [x, z]; } },
					{ x: o.center[0] + o.radius, z: o.center[1], set: (x, z) => { o.radius = Math.max(1, E.dist(x, z, o.center[0], o.center[1])); } },
				];
			}
			const min = isLine(o) ? 2 : 3;
			return o.points.map((p, i) => ({
				x: p[0], z: p[1],
				set: (x, z) => { o.points[i] = [x, z]; },
				remove: o.points.length > min ? () => o.points.splice(i, 1) : null,
			}));
		},
		move(o, dx, dz) {
			if (isCircle(o)) o.center = [o.center[0] + dx, o.center[1] + dz];
			else o.points = o.points.map((p) => [p[0] + dx, p[1] + dz]);
		},
		insertAt(o, x, z, tol) {
			if (isCircle(o)) return false;
			const n = o.points.length, closed = !isLine(o);
			for (let i = 0; i < (closed ? n : n - 1); i++) {
				const a = o.points[i], b = o.points[(i + 1) % n];
				if (E.segDist(x, z, a[0], a[1], b[0], b[1]) < tol) { o.points.splice(i + 1, 0, [E.round(x), E.round(z)]); return true; }
			}
			return false;
		},
		panel(o, box) {
			box.append(E.field("Name", E.input(o, "name")));
			box.append(E.field("Id", E.input(o, "id", "text", { readonly: true })));
			box.append(E.field("What", E.el("span", {}, TYPES[o.type].label)));
			if (o.type === "flat") {
				const here = isCircle(o) ? E.heightAt(o.center[0], o.center[1]) : null;
				box.append(E.field("Height (m)", E.input(o, "height", "number", { step: 0.5, refresh: true })));
				if (here !== null) box.append(E.el("p", { class: "muted" }, `The land there is about ${here.toFixed(1)} m now.`));
			}
			if (o.type === "raise") {
				box.append(E.field("Up / down (m)", E.input(o, "height", "number", { step: 0.5, refresh: true })));
				// a dome's steepest is about 1.5 x height / reach; the generator eases anything over ~24°
				// (on top of whatever slope the land already has), so the land stays walkable
				const reach = isCircle(o) ? o.radius + (o.soft ?? 0) : (o.soft ?? 10);
				const deg = Math.round(Math.atan((Math.abs(o.height) * 1.5) / Math.max(reach, 1)) * 180 / Math.PI);
				box.append(E.el("p", { class: deg > 20 ? "" : "muted", style: deg > 20 ? "color: var(--warn)" : "" },
					`Its sides: about ${deg}°.` + (deg > 20 ? " Steeper than ~24° (with the land's own slope) gets eased down: make it wider or lower." : "")));
			}
			if (o.type === "pond") {
				box.append(E.field("Depth (m)", E.input(o, "depth", "number", { step: 0.05, min: 0.2, refresh: true })));
				if (!isCircle(o)) box.append(E.field("Shelf (m)", E.input(o, "shelf", "number", { step: 0.5, min: 1, default: 6 })));
				// fish: a list of species (data/fish/), true for perch and trout, false for none
				const names = Array.isArray(o.fish) ? o.fish.join(", ") : o.fish === false ? "" : "perch, perch, trout";
				const fish = E.el("input", { type: "text", value: names, title: "Species from data/fish/ (perch, trout, pike, char, grayling, salmon), a school each; empty: none" });
				fish.onchange = () => {
					const list = fish.value.split(",").map((t) => t.trim().toLowerCase()).filter(Boolean);
					E.commit();
					o.fish = list.length ? list : false;
					E.changed(true);
				};
				box.append(E.field("Fish", fish));
				box.append(E.el("p", { class: "muted" }, "Up to about 1.4 m: you wade, you don't swim. Its water is at -0.15 m; dug into higher ground it sits in a hollow (a flat round it looks kinder)."
					+ (isCircle(o) ? "" : " The shelf: how far in from the shore it's at its deepest.")));
			}
			if (o.type === "flat" || o.type === "raise") box.append(E.field("Soft edge (m)", E.input(o, "soft", "number", { step: 1, min: 0, default: 10 })));
			if (isCircle(o)) box.append(E.field("Radius (m)", E.input(o, "radius", "number", { step: 0.5, min: 1 })));
			if (o.type === "river") {
				box.append(E.field("Width (m)", E.input(o, "width", "number", { step: 0.5, min: 1, default: 4, refresh: true })));
				box.append(E.field("Depth (m)", E.input(o, "depth", "number", { step: 0.05, min: 0.2, default: 0.8, refresh: true })));
				box.append(E.field("Vale (m)", E.input(o, "vale", "number", { step: 5, min: 0, default: 30, refresh: true })));
				box.append(E.field("Fish", E.input(o, "fish", "check", { default: true })));
				box.append(E.el("p", { class: "muted" }, "Its water sits at the ponds' level (-0.15 m): where it runs through higher ground the land is eased down to it over the vale, each side. Up to about 1.4 m deep: you wade it. Roads that cross it get a bridge."));
			} else if (isLine(o)) box.append(E.el("p", { class: "muted" }, "The generator lays it along this line, easing its slope; a road should start on another road or path."));
			box.append(E.el("p", { class: "muted" }, "Terrain changes regenerate the land on the next bake (about a minute)."));
		},
	});

	// --- the brush ------------------------------------------------------------------------------------

	const brush = { type: "flat", shape: "polygon", height: 0, depth: 0.9, width: 4, riverDepth: 0.8 };
	let corners = [];
	let pressAt = null;
	let hover = null;

	const add = (o) => {
		E.roundShape("terrain", o);
		E.commit();
		E.layout.terrain.push(o);
		E.select("terrain", o);
		E.changed();
	};
	const make = (extra) => {
		const o = { id: E.uniqueId(brush.type), type: brush.type, ...extra };
		if (brush.type === "flat") { o.height = brush.height; o.soft = 10; }
		if (brush.type === "raise") { o.height = brush.height || 5; o.soft = isCircle(o) ? 0 : 10; }
		if (brush.type === "pond") { o.depth = brush.depth; o.fish = true; if (!isCircle(o)) o.shelf = 6; }
		if (brush.type === "river") { o.width = brush.width; o.depth = brush.riverDepth; o.fish = true; }
		return o;
	};
	const shapeFor = () => (isLine(brush) ? "line" : brush.shape);
	const finish = () => {
		const s = shapeFor();
		if (s === "line" && corners.length >= 2) add(make({ name: TYPES[brush.type].label, points: corners }));
		else if (s === "polygon" && corners.length >= 3) add(make({ name: TYPES[brush.type].label, shape: "polygon", points: corners }));
		corners = [];
		E.updateHint();
	};

	E.registerTool({
		id: "terrain",
		label: "Terrain",
		title: "Shape the land: flats, hills, ponds, rivers, roads",
		options(box) {
			const el = E.el;
			const types = el("span", { class: "row" });
			const rebuild = () => { E.setTool(E.tool); };
			for (const t in TYPES) types.append(el("button", { class: t === brush.type ? "on" : "", onclick: () => { brush.type = t; corners = []; rebuild(); } }, TYPES[t].label));
			box.append(types);
			if (brush.type === "flat" || brush.type === "raise") {
				const shapes = el("span", { class: "row" });
				for (const [s, label] of [["polygon", "Polygon"], ["circle", "Circle"]]) {
					shapes.append(el("button", { class: s === brush.shape ? "on" : "", onclick: () => { brush.shape = s; corners = []; rebuild(); } }, label));
				}
				const hgt = el("input", { type: "number", step: "0.5", value: brush.type === "raise" ? (brush.height || 5) : brush.height,
					title: brush.type === "flat" ? "The height it's eased to (m)" : "How far up (negative: down), m" });
				hgt.onchange = () => { brush.height = Number(hgt.value); };
				box.append(shapes, el("span", { class: "muted" }, brush.type === "flat" ? "height (m)" : "up / down (m)"), hgt);
			}
			if (brush.type === "pond") {
				const shapes = el("span", { class: "row" });
				for (const [s, label] of [["polygon", "Outline"], ["circle", "Circle"]]) {
					shapes.append(el("button", { class: s === brush.shape ? "on" : "", onclick: () => { brush.shape = s; corners = []; rebuild(); } }, label));
				}
				box.append(shapes);
				const d = el("input", { type: "number", step: "0.05", min: "0.2", value: brush.depth });
				d.onchange = () => { brush.depth = Number(d.value); };
				box.append(el("span", { class: "muted" }, "depth (m)"), d);
			}
			if (brush.type === "river") {
				const wd = el("input", { type: "number", step: "0.5", min: "1", value: brush.width });
				wd.onchange = () => { brush.width = Number(wd.value); };
				const d = el("input", { type: "number", step: "0.05", min: "0.2", value: brush.riverDepth });
				d.onchange = () => { brush.riverDepth = Number(d.value); };
				box.append(el("span", { class: "muted" }, "width (m)"), wd, el("span", { class: "muted" }, "depth (m)"), d);
			}
		},
		hint() {
			const s = shapeFor();
			if (s === "circle") return "Drag from the middle out to the edge.";
			if (corners.length) return `${corners.length} points: click to add, double-click / Enter to finish, Backspace to take one back, Esc to drop it`;
			if (brush.type === "river") return "Click along where it runs, from its source down to where it ends (in a pond or the lake, say).";
			return s === "line" ? "Click along where it runs (start it on a road or path)." : "Click the corners.";
		},
		down(x, z) {
			if (shapeFor() === "circle") { pressAt = [x, z]; return; }
			if (shapeFor() === "polygon" && corners.length >= 3 && E.dist(x, z, corners[0][0], corners[0][1]) < 8 / E.view.s) { finish(); return; }
			corners.push([x, z]);
			E.updateHint();
		},
		move(x, z) { hover = [x, z]; },
		up(x, z) {
			if (!pressAt) return;
			const r = E.dist(pressAt[0], pressAt[1], x, z);
			if (r >= 1) add(make({ name: TYPES[brush.type].label, shape: "circle", center: pressAt, radius: r }));
			pressAt = null;
		},
		dblclick() {
			const n = corners.length;
			if (n < 2 || E.dist(corners[n - 1][0], corners[n - 1][1], corners[n - 2][0], corners[n - 2][1]) > 6 / E.view.s) return;
			corners.pop();
			finish();
		},
		finish,
		cancel() { corners = []; pressAt = null; E.updateHint(); },
		keydown(ev) {
			if (ev.key === "Backspace" && corners.length) { corners.pop(); E.updateHint(); return true; }
			return false;
		},
		preview(ctx) {
			ctx.strokeStyle = TYPES[brush.type].color;
			ctx.lineWidth = 2;
			ctx.setLineDash([5, 4]);
			if (corners.length) {
				E.path(hover ? [...corners, hover] : corners, false);
				ctx.stroke();
			} else if (pressAt && hover) {
				const [sx, sy] = E.toScreen(pressAt[0], pressAt[1]);
				ctx.beginPath();
				ctx.arc(sx, sy, E.dist(pressAt[0], pressAt[1], hover[0], hover[1]) * E.view.s, 0, Math.PI * 2);
				ctx.stroke();
			}
			ctx.setLineDash([]);
		},
	});
})();
