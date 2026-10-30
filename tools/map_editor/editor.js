// The map editor (plans/map-editor.md): the map, the view, selection, undo, the panels, saving
// and baking. What can be placed lives in its own file (patches.js, lines_points.js, terrain.js),
// each registering its kind of shape (how it draws, is hit, moves, and its properties) and its
// drawing tools.
"use strict";

const Editor = (() => {
	const E = {
		layout: null, catalog: null, world: null, baked: null,
		kinds: {},            // collection name -> spec
		tools: [],            // drawing tools, in toolbar order
		tool: null,
		sel: [],              // [{kind, obj}]
		view: { cx: 128, cz: 128, s: 1.2 },
		show: { map: true, overlays: true, labels: true, terrain: true, patches: true, lines: true, points: true, baked: true, warnings: true },
		dirty: false,
		bakedStale: false,
	};
	const undo = [];
	const redo = [];
	let canvas, ctx, mapImg;
	let W = 0, H = 0;
	let mouse = { x: 0, y: 0, wx: 0, wz: 0 };
	let drag = null;   // {type: 'pan'|'move'|'handle'|'box', ...}

	// --- geometry -------------------------------------------------------------------------------

	E.toScreen = (x, z) => [(x - E.view.cx) * E.view.s + W / 2, (z - E.view.cz) * E.view.s + H / 2];
	E.toWorld = (sx, sy) => [(sx - W / 2) / E.view.s + E.view.cx, (sy - H / 2) / E.view.s + E.view.cz];
	E.round = (v) => Math.round(v * 10) / 10;
	E.dist = (ax, az, bx, bz) => Math.hypot(ax - bx, az - bz);
	E.segDist = (px, pz, ax, az, bx, bz) => {
		const dx = bx - ax, dz = bz - az;
		const l = dx * dx + dz * dz;
		const t = l ? Math.max(0, Math.min(1, ((px - ax) * dx + (pz - az) * dz) / l)) : 0;
		return Math.hypot(px - (ax + t * dx), pz - (az + t * dz));
	};
	E.inPoly = (x, z, pts) => {
		let inside = false;
		for (let i = 0, j = pts.length - 1; i < pts.length; j = i++) {
			const [xi, zi] = pts[i], [xj, zj] = pts[j];
			if ((zi > z) !== (zj > z) && x < ((xj - xi) * (z - zi)) / (zj - zi) + xi) inside = !inside;
		}
		return inside;
	};
	E.polyArea = (pts) => {
		let a = 0;
		for (let i = 0, j = pts.length - 1; i < pts.length; j = i++) a += (pts[j][0] + pts[i][0]) * (pts[j][1] - pts[i][1]);
		return Math.abs(a / 2);
	};
	E.polyLength = (pts) => {
		let s = 0;
		for (let i = 1; i < pts.length; i++) s += E.dist(pts[i - 1][0], pts[i - 1][1], pts[i][0], pts[i][1]);
		return s;
	};
	/** Ground height at world (x, z), from the exported grid (m). */
	E.heightAt = (x, z) => {
		const w = E.world;
		if (!w || !w.heights) return 0;
		const step = w.height_step, n = Math.ceil(w.size / step);
		const gx = (x - w.origin[0]) / step, gz = (z - w.origin[1]) / step;
		const ix = Math.max(0, Math.min(n - 2, Math.floor(gx))), iz = Math.max(0, Math.min(n - 2, Math.floor(gz)));
		const fx = Math.max(0, Math.min(1, gx - ix)), fz = Math.max(0, Math.min(1, gz - iz));
		const h = (i, k) => w.heights[k * n + i];
		return (h(ix, iz) * (1 - fx) + h(ix + 1, iz) * fx) * (1 - fz) + (h(ix, iz + 1) * (1 - fx) + h(ix + 1, iz + 1) * fx) * fz;
	};
	/** Rise per metre at (x, z). */
	E.slopeAt = (x, z) => {
		const d = 2;
		return Math.hypot(E.heightAt(x + d, z) - E.heightAt(x - d, z), E.heightAt(x, z + d) - E.heightAt(x, z - d)) / (2 * d);
	};

	// --- registry ------------------------------------------------------------------------------

	/** spec: {label, title(o), color(o), draw(ctx, o, selected), hit(o, x, z, tol), handles(o), move(o, dx, dz), panel(o, el), group(o)} */
	E.registerKind = (name, spec) => { E.kinds[name] = spec; };
	/** spec: {id, label, key, title, options(el), down(x, z, ev), move(x, z, ev), up(x, z, ev), dblclick(x, z), finish(), cancel(), preview(ctx), hint()} */
	E.registerTool = (spec) => { E.tools.push(spec); };

	E.uniqueId = (prefix) => {
		const taken = new Set();
		for (const k in E.kinds) for (const o of E.layout[k] || []) taken.add(o.id);
		let i = 1;
		while (taken.has(`${prefix}_${i}`)) i++;
		return `${prefix}_${i}`;
	};

	// --- undo, change ---------------------------------------------------------------------------

	const snapshot = () => JSON.stringify(E.layout);
	/** Call before changing the layout. */
	E.commit = () => {
		undo.push(snapshot());
		if (undo.length > 200) undo.shift();
		redo.length = 0;
	};
	/** Call after changing the layout. */
	E.changed = (keepPanel) => {
		E.dirty = true;
		E.bakedStale = true;
		refreshList();
		if (!keepPanel) refreshProps();
		updateButtons();
		E.draw();
	};
	const restore = (json) => {
		const ids = E.sel.map((s) => [s.kind, s.obj.id]);
		E.layout = JSON.parse(json);
		E.sel = [];
		for (const [k, id] of ids) {
			const o = (E.layout[k] || []).find((x) => x.id === id);
			if (o) E.sel.push({ kind: k, obj: o });
		}
		E.changed();
	};
	E.undo = () => { if (undo.length) { redo.push(snapshot()); restore(undo.pop()); } };
	E.redo = () => { if (redo.length) { undo.push(snapshot()); restore(redo.pop()); } };

	// --- selection -------------------------------------------------------------------------------

	E.select = (kind, obj, add) => {
		if (!add) E.sel = [];
		if (obj && !E.sel.some((s) => s.obj === obj)) E.sel.push({ kind, obj });
		refreshList();
		refreshProps();
		E.draw();
	};
	E.isSelected = (obj) => E.sel.some((s) => s.obj === obj);
	E.deleteSelected = () => {
		if (!E.sel.length) return;
		E.commit();
		for (const { kind, obj } of E.sel) {
			const list = E.layout[kind];
			const i = list.indexOf(obj);
			if (i >= 0) list.splice(i, 1);
		}
		E.sel = [];
		E.changed();
	};
	E.duplicateSelected = () => {
		if (!E.sel.length) return;
		E.commit();
		const made = [];
		for (const { kind, obj } of E.sel) {
			const copy = JSON.parse(JSON.stringify(obj));
			copy.id = E.uniqueId(obj.id.replace(/_\d+$/, ""));
			delete copy.save_id;
			if (copy.name) copy.name += " (copy)";
			if (copy.seed !== undefined) copy.seed = Math.floor(Math.random() * 1e9);
			E.kinds[kind].move(copy, 8, 8);
			E.layout[kind].push(copy);
			made.push({ kind, obj: copy });
		}
		E.sel = made;
		E.changed();
	};
	E.centerOn = (x, z) => { E.view.cx = x; E.view.cz = z; E.draw(); };
	E.centerOnShape = (kind, obj) => {
		const hs = E.kinds[kind].handles(obj);
		if (!hs.length) return;
		let x = 0, z = 0;
		for (const h of hs) { x += h.x; z += h.z; }
		E.centerOn(x / hs.length, z / hs.length);
	};

	/** The topmost shape under world (x, z): points over lines over terrain over patches, smaller patches first. */
	const pick = (x, z) => {
		const tol = 7 / E.view.s;
		const order = ["points", "lines", "terrain", "patches"];
		for (const kind of order) {
			const spec = E.kinds[kind];
			if (!spec || !E.show[kind]) continue;
			let best = null, bestScore = Infinity;
			for (const o of E.layout[kind] || []) {
				const score = spec.hit(o, x, z, tol);
				if (score !== false && score !== null && score < bestScore) { best = o; bestScore = score; }
			}
			if (best) return { kind, obj: best };
		}
		return null;
	};
	const pickHandle = (x, z) => {
		const tol = 8 / E.view.s;
		for (const s of E.sel) {
			for (const h of E.kinds[s.kind].handles(s.obj)) {
				if (h.set && E.dist(x, z, h.x, h.z) < tol) return { sel: s, handle: h };
			}
		}
		return null;
	};

	// --- drawing ---------------------------------------------------------------------------------

	E.draw = () => {
		if (!ctx) return;
		ctx.setTransform(1, 0, 0, 1, 0, 0);
		ctx.fillStyle = "#14160f";
		ctx.fillRect(0, 0, W, H);
		const w = E.world;
		if (w && mapImg && E.show.map) {
			const [sx, sy] = E.toScreen(w.origin[0], w.origin[1]);
			ctx.imageSmoothingEnabled = E.view.s < 2;
			ctx.drawImage(mapImg, sx, sy, w.size * E.view.s, w.size * E.view.s);
		}
		if (w && E.show.overlays) drawOverlays();
		for (const kind of ["terrain", "patches", "lines", "points"]) {
			const spec = E.kinds[kind];
			if (!spec || !E.show[kind]) continue;
			for (const o of E.layout[kind] || []) spec.draw(ctx, o, E.isSelected(o));
		}
		if (E.show.baked && E.baked && E.baked.nodes) drawBaked();
		if (E.show.warnings && E.baked && E.baked.warnings) drawWarnings();
		if (w && E.show.labels) drawLabels();
		drawHandles();
		if (E.tool && E.tool.preview) E.tool.preview(ctx);
		if (drag && drag.type === "box") drawBox();
	};

	const drawOverlays = () => {
		ctx.lineWidth = 1;
		for (const t of E.world.things) {
			const [sx, sy] = E.toScreen(t[0], t[1]);
			ctx.beginPath();
			ctx.arc(sx, sy, Math.max(2, t[2] * E.view.s), 0, Math.PI * 2);
			ctx.fillStyle = t[3] === "building" ? "rgba(120, 72, 52, 0.75)" : t[3] === "fixture" ? "rgba(140, 100, 70, 0.6)" : "rgba(90, 80, 70, 0.45)";
			ctx.fill();
			ctx.strokeStyle = "rgba(30, 20, 15, 0.7)";
			ctx.stroke();
		}
	};

	const drawLabels = () => {
		ctx.font = "600 13px system-ui, sans-serif";
		ctx.textAlign = "center";
		for (const [x, z, name] of E.world.labels) {
			const [sx, sy] = E.toScreen(x, z);
			ctx.lineWidth = 3;
			ctx.strokeStyle = "rgba(20, 20, 15, 0.8)";
			ctx.strokeText(name, sx, sy);
			ctx.fillStyle = "#f3ead2";
			ctx.fillText(name, sx, sy);
		}
		if (E.view.s > 3) {  // building names, close up
			ctx.font = "11px system-ui, sans-serif";
			for (const t of E.world.things) {
				if (t[3] === "prop") continue;
				const [sx, sy] = E.toScreen(t[0], t[1]);
				ctx.fillStyle = "rgba(243, 234, 210, 0.85)";
				ctx.fillText(t[4], sx, sy - t[2] * E.view.s - 3);
			}
		}
	};

	E.gatherableColor = (id) => (E.catalog.gatherables[id] || {}).color || "#ff00ff";

	const drawBaked = () => {
		const r = Math.max(1.5, Math.min(4, E.view.s * 0.8));
		ctx.globalAlpha = E.bakedStale ? 0.45 : 0.95;
		for (const [x, z, id] of E.baked.nodes) {
			const [sx, sy] = E.toScreen(x, z);
			if (sx < -5 || sy < -5 || sx > W + 5 || sy > H + 5) continue;
			ctx.beginPath();
			ctx.arc(sx, sy, r, 0, Math.PI * 2);
			ctx.fillStyle = E.gatherableColor(id);
			ctx.fill();
			ctx.lineWidth = 1;
			ctx.strokeStyle = "rgba(0, 0, 0, 0.6)";
			ctx.stroke();
		}
		ctx.globalAlpha = 1;
	};

	const drawWarnings = () => {
		ctx.font = "bold 13px system-ui, sans-serif";
		ctx.textAlign = "center";
		for (const w of E.baked.warnings) {
			const [sx, sy] = E.toScreen(w.at[0], w.at[1]);
			ctx.beginPath();
			ctx.moveTo(sx, sy - 9); ctx.lineTo(sx + 8, sy + 6); ctx.lineTo(sx - 8, sy + 6); ctx.closePath();
			ctx.fillStyle = "#e0795a";
			ctx.fill();
			ctx.fillStyle = "#1d1f1c";
			ctx.fillText("!", sx, sy + 4);
		}
	};

	const drawHandles = () => {
		for (const s of E.sel) {
			for (const h of E.kinds[s.kind].handles(s.obj)) {
				if (!h.set) continue;
				const [sx, sy] = E.toScreen(h.x, h.z);
				ctx.beginPath();
				if (h.round) ctx.arc(sx, sy, 5, 0, Math.PI * 2);
				else ctx.rect(sx - 4, sy - 4, 8, 8);
				ctx.fillStyle = "#fff";
				ctx.fill();
				ctx.lineWidth = 1.5;
				ctx.strokeStyle = "#1d1f1c";
				ctx.stroke();
			}
		}
	};

	const drawBox = () => {
		const [ax, ay] = E.toScreen(drag.x0, drag.z0);
		ctx.strokeStyle = "#fff";
		ctx.setLineDash([4, 3]);
		ctx.lineWidth = 1;
		ctx.strokeRect(ax, ay, mouse.x - ax, mouse.y - ay);
		ctx.setLineDash([]);
	};

	/** Draws a polyline (world points) in screen space. */
	E.path = (pts, closed) => {
		ctx.beginPath();
		pts.forEach(([x, z], i) => {
			const [sx, sy] = E.toScreen(x, z);
			if (i === 0) ctx.moveTo(sx, sy); else ctx.lineTo(sx, sy);
		});
		if (closed) ctx.closePath();
	};
	E.ctx = () => ctx;

	// --- the panels ----------------------------------------------------------------------------

	const el = (tag, attrs = {}, ...kids) => {
		const n = document.createElement(tag);
		for (const k in attrs) {
			if (k.startsWith("on")) n.addEventListener(k.slice(2), attrs[k]);
			else if (k === "class") n.className = attrs[k];
			else if (k in n && typeof attrs[k] !== "string") n[k] = attrs[k];
			else n.setAttribute(k, attrs[k]);
		}
		for (const kid of kids) if (kid !== null && kid !== undefined) n.append(kid);
		return n;
	};
	E.el = el;

	/** A labelled row in the properties panel. */
	E.field = (label, input) => el("div", { class: "field" }, el("label", {}, label), input);
	/** A full-width block in the properties panel, its label above. */
	E.block = (label, input) => el("div", { class: "block" }, el("label", {}, label), input);
	/** An input bound to obj[key]: type text | number | check | select (options: [[value, label]]). */
	E.input = (obj, key, type = "text", opts = {}) => {
		const set = (v) => {
			if (obj[key] === v) return;
			E.commit();
			obj[key] = v;
			if (opts.after) opts.after(v);
			E.changed(true);
			if (opts.refresh) refreshProps();
		};
		if (type === "select") {
			const s = el("select", { onchange: () => set(opts.number ? Number(s.value) : s.value) });
			for (const [v, label] of opts.options) s.append(el("option", { value: v }, label));
			s.value = obj[key] ?? opts.default ?? "";
			return s;
		}
		if (type === "check") {
			const c = el("input", { type: "checkbox", onchange: () => set(c.checked) });
			c.checked = obj[key] ?? opts.default ?? false;
			return c;
		}
		const i = el("input", { type, step: opts.step || "any", onchange: () => set(type === "number" ? Number(i.value) : i.value) });
		if (opts.min !== undefined) i.min = opts.min;
		i.value = obj[key] ?? opts.default ?? "";
		if (opts.readonly) i.readOnly = true;
		return i;
	};

	const refreshProps = () => {
		const box = document.getElementById("props");
		box.textContent = "";
		if (!E.sel.length) {
			box.append(el("p", { class: "muted" }, "Click a shape to see it here."));
			return;
		}
		if (E.sel.length > 1) {
			box.append(el("h3", {}, `${E.sel.length} shapes`), el("p", { class: "muted" }, "Drag to move them together, Del to delete, Ctrl+D to duplicate."));
			return;
		}
		const { kind, obj } = E.sel[0];
		const spec = E.kinds[kind];
		box.append(el("h3", {}, spec.label));
		spec.panel(obj, box);
	};
	E.refreshProps = refreshProps;

	const refreshList = () => {
		const box = document.getElementById("list");
		const q = document.getElementById("filter").value.trim().toLowerCase();
		box.textContent = "";
		for (const kind of ["terrain", "patches", "lines", "points"]) {
			const spec = E.kinds[kind];
			if (!spec) continue;
			const items = (E.layout[kind] || []).filter((o) => !q || spec.title(o).toLowerCase().includes(q) || (o.id || "").includes(q));
			if (!items.length) continue;
			box.append(el("div", { class: "group" }, `${spec.label}s (${items.length})`));
			for (const o of items) {
				box.append(el("div", {
					class: "item" + (E.isSelected(o) ? " sel" : ""),
					title: o.id,
					onclick: (ev) => { E.select(kind, o, ev.shiftKey); E.centerOnShape(kind, o); },
				}, el("span", { class: "swatch", style: `background:${spec.color(o)}` }), spec.title(o)));
			}
		}
	};

	const refreshLayers = () => {
		const box = document.getElementById("layers");
		box.textContent = "";
		const names = { map: "Land", overlays: "Buildings", labels: "Names", terrain: "Terrain", patches: "Patches", lines: "Lines", points: "Points", baked: "Baked nodes", warnings: "Warnings" };
		for (const k in names) {
			const c = el("input", { type: "checkbox", onchange: () => { E.show[k] = c.checked; E.draw(); } });
			c.checked = E.show[k];
			box.append(el("label", {}, c, names[k]));
		}
	};

	const refreshWarnings = () => {
		const box = document.getElementById("warnings");
		box.textContent = "";
		const b = E.baked || {};
		document.getElementById("bakeinfo").textContent = b.baked ? `${b.baked.replace("T", " ")}, ${(b.nodes || []).length} nodes` : "none yet";
		const ws = b.warnings || [];
		if (!ws.length) { box.append(el("p", { class: "muted" }, b.baked ? "No warnings." : "")); return; }
		for (const w of ws) {
			box.append(el("div", {
				class: "w",
				onclick: () => {
					E.centerOn(w.at[0], w.at[1]);
					for (const k in E.kinds) {
						const o = (E.layout[k] || []).find((x) => x.id === w.ref);
						if (o) { E.select(k, o); break; }
					}
				},
			}, "! " + w.msg));
		}
	};

	const updateButtons = () => {
		document.getElementById("undo").disabled = !undo.length;
		document.getElementById("redo").disabled = !redo.length;
		document.getElementById("save").textContent = E.dirty ? "Save •" : "Save";
	};

	E.status = (text, cls = "") => {
		const s = document.getElementById("status");
		s.textContent = text;
		s.className = cls;
	};

	// --- tools -----------------------------------------------------------------------------------

	const SELECT = { id: "select", label: "Select", key: "1", title: "Select, move and reshape (1)" };

	E.setTool = (t) => {
		if (E.tool && E.tool.cancel) E.tool.cancel();
		E.tool = t === SELECT ? null : t;
		const opts = document.getElementById("toolopts");
		opts.textContent = "";
		if (E.tool && E.tool.options) E.tool.options(opts);
		for (const b of document.querySelectorAll("#tools button")) b.classList.toggle("on", b.dataset.id === (E.tool ? E.tool.id : "select"));
		updateHint();
		E.draw();
	};
	const updateHint = () => {
		const h = document.getElementById("hint");
		h.textContent = E.tool && E.tool.hint ? E.tool.hint() : "";
	};
	E.updateHint = updateHint;

	const buildToolbar = () => {
		const box = document.getElementById("tools");
		const all = [SELECT, ...E.tools];
		all.forEach((t, i) => {
			t.key = String(i + 1);
			box.append(el("button", { "data-id": t.id, title: `${t.title || t.label} (${t.key})`, onclick: () => E.setTool(t) }, t.label));
		});
	};

	// --- input ------------------------------------------------------------------------------------

	const onDown = (ev) => {
		canvas.focus();
		const [x, z] = E.toWorld(ev.offsetX, ev.offsetY);
		if (ev.button === 1 || ev.button === 2) {
			drag = { type: "pan", sx: ev.offsetX, sy: ev.offsetY, cx: E.view.cx, cz: E.view.cz };
			return;
		}
		if (E.tool) {
			if (E.tool.down) E.tool.down(x, z, ev);
			E.draw();
			return;
		}
		const h = pickHandle(x, z);
		if (h) {
			if (ev.altKey && h.handle.remove) {
				E.commit();
				h.handle.remove();
				E.changed();
				return;
			}
			E.commit();
			drag = { type: "handle", h, moved: false };
			if (E.kinds[h.sel.kind].beginEdit) E.kinds[h.sel.kind].beginEdit(h.sel.obj);
			return;
		}
		const hit = pick(x, z);
		if (hit) {
			if (!E.isSelected(hit.obj)) E.select(hit.kind, hit.obj, ev.shiftKey);
			else if (ev.shiftKey) { E.sel = E.sel.filter((s) => s.obj !== hit.obj); refreshList(); refreshProps(); E.draw(); return; }
			drag = { type: "move", x, z, moved: false };
			return;
		}
		if (ev.shiftKey) { drag = { type: "box", x0: x, z0: z }; return; }
		if (!ev.shiftKey && E.sel.length) E.select(null, null);
		drag = { type: "pan", sx: ev.offsetX, sy: ev.offsetY, cx: E.view.cx, cz: E.view.cz };
	};

	const onMove = (ev) => {
		mouse.x = ev.offsetX; mouse.y = ev.offsetY;
		const [x, z] = E.toWorld(ev.offsetX, ev.offsetY);
		mouse.wx = x; mouse.wz = z;
		document.getElementById("cursor").textContent =
			`x ${x.toFixed(1)}  z ${z.toFixed(1)}  height ${E.heightAt(x, z).toFixed(1)} m  slope ${Math.round(Math.atan(E.slopeAt(x, z)) * 180 / Math.PI)}°`;
		if (drag && drag.type === "pan") {
			E.view.cx = drag.cx - (ev.offsetX - drag.sx) / E.view.s;
			E.view.cz = drag.cz - (ev.offsetY - drag.sy) / E.view.s;
			E.draw();
			return;
		}
		if (drag && drag.type === "move") {
			if (!drag.moved) { E.commit(); drag.moved = true; for (const s of E.sel) if (E.kinds[s.kind].beginEdit) E.kinds[s.kind].beginEdit(s.obj); }
			const dx = x - drag.x, dz = z - drag.z;
			for (const s of E.sel) E.kinds[s.kind].move(s.obj, dx, dz);
			drag.x = x; drag.z = z;
			E.draw();
			return;
		}
		if (drag && drag.type === "handle") {
			drag.moved = true;
			drag.h.handle.set(x, z, ev);
			E.draw();
			return;
		}
		if (drag && drag.type === "box") { E.draw(); return; }
		if (E.tool && E.tool.move) { E.tool.move(x, z, ev); E.draw(); }
	};

	const onUp = (ev) => {
		const [x, z] = E.toWorld(ev.offsetX, ev.offsetY);
		if (drag && (drag.type === "move" || drag.type === "handle")) {
			if (drag.moved) {
				for (const s of E.sel) {
					for (const o of [s.obj]) if (E.kinds[s.kind].endEdit) E.kinds[s.kind].endEdit(o);
					roundShape(s.kind, s.obj);
				}
				E.changed();
			} else if (drag.type === "handle") undo.pop();
		} else if (drag && drag.type === "box") {
			const x0 = Math.min(drag.x0, x), x1 = Math.max(drag.x0, x), z0 = Math.min(drag.z0, z), z1 = Math.max(drag.z0, z);
			for (const kind in E.kinds) {
				if (!E.show[kind]) continue;
				for (const o of E.layout[kind] || []) {
					const hs = E.kinds[kind].handles(o);
					if (hs.length && hs.every((h) => h.x >= x0 && h.x <= x1 && h.z >= z0 && h.z <= z1) && !E.isSelected(o)) E.sel.push({ kind, obj: o });
				}
			}
			refreshList(); refreshProps();
		} else if (E.tool && E.tool.up) E.tool.up(x, z, ev);
		drag = null;
		E.draw();
	};

	const onDbl = (ev) => {
		const [x, z] = E.toWorld(ev.offsetX, ev.offsetY);
		if (E.tool) { if (E.tool.dblclick) E.tool.dblclick(x, z); E.draw(); return; }
		// a corner on the edge of the selected line or patch
		for (const s of E.sel) {
			const spec = E.kinds[s.kind];
			if (spec.insertAt) {
				E.commit();
				if (spec.insertAt(s.obj, x, z, 8 / E.view.s)) { E.changed(); return; }
				undo.pop();
			}
		}
	};

	const onWheel = (ev) => {
		ev.preventDefault();
		const [x, z] = E.toWorld(ev.offsetX, ev.offsetY);
		const f = Math.exp(-ev.deltaY * 0.0015);
		E.view.s = Math.max(0.3, Math.min(40, E.view.s * f));
		// keep the point under the cursor still
		E.view.cx = x - (ev.offsetX - W / 2) / E.view.s;
		E.view.cz = z - (ev.offsetY - H / 2) / E.view.s;
		E.draw();
	};

	const onKey = (ev) => {
		if (ev.target.tagName === "INPUT" || ev.target.tagName === "SELECT") {
			if (ev.key === "Escape") ev.target.blur();
			return;
		}
		const k = ev.key.toLowerCase();
		if ((ev.ctrlKey || ev.metaKey) && k === "z" && !ev.shiftKey) { ev.preventDefault(); E.undo(); return; }
		if ((ev.ctrlKey || ev.metaKey) && (k === "y" || (k === "z" && ev.shiftKey))) { ev.preventDefault(); E.redo(); return; }
		if ((ev.ctrlKey || ev.metaKey) && k === "s") { ev.preventDefault(); E.save(); return; }
		if ((ev.ctrlKey || ev.metaKey) && k === "b") { ev.preventDefault(); E.bake(); return; }
		if ((ev.ctrlKey || ev.metaKey) && k === "d") { ev.preventDefault(); E.duplicateSelected(); return; }
		if (ev.ctrlKey || ev.metaKey || ev.altKey) return;
		if (k === "escape") { if (E.tool) { if (E.tool.cancel) E.tool.cancel(); E.draw(); } else E.select(null, null); return; }
		if (k === "enter") { if (E.tool && E.tool.finish) { E.tool.finish(); E.draw(); } return; }
		if (k === "delete" || k === "backspace") { E.deleteSelected(); return; }
		const all = [SELECT, ...E.tools];
		const t = all.find((t) => t.key === ev.key);
		if (t) E.setTool(t);
	};

	/** Rounds a shape's coordinates to 0.1 m (keeps the file tidy). */
	const roundShape = (kind, o) => {
		const r = (a) => a.map((p) => [E.round(p[0]), E.round(p[1])]);
		if (o.points) o.points = r(o.points);
		if (o.center) o.center = [E.round(o.center[0]), E.round(o.center[1])];
		if (o.at) o.at = [E.round(o.at[0]), E.round(o.at[1])];
		for (const k of ["radius", "inner"]) if (typeof o[k] === "number") o[k] = E.round(o[k]);
	};
	E.roundShape = roundShape;

	const resize = () => {
		const r = canvas.parentElement.getBoundingClientRect();
		const dpr = window.devicePixelRatio || 1;
		W = r.width; H = r.height;
		canvas.width = W * dpr; canvas.height = H * dpr;
		ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
		E.draw();
	};

	// --- the server --------------------------------------------------------------------------------

	const get = async (url) => (await fetch(url, { cache: "no-store" })).json();

	/** The layout as saved: no editor-only fields (those starting with "_"). */
	const clean = () => JSON.parse(JSON.stringify(E.layout, (k, v) => (k.startsWith("_") ? undefined : v)));

	E.save = async () => {
		E.status("Saving…");
		const r = await fetch("/api/layout", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(clean()) });
		if (!r.ok) { E.status("Couldn't save: " + (await r.text()), "bad"); return false; }
		E.dirty = false;
		updateButtons();
		E.status("Saved.", "ok");
		return true;
	};

	E.runGodot = async (url, what) => {
		const btns = document.querySelectorAll("header button");
		btns.forEach((b) => (b.disabled = true));
		const t0 = Date.now();
		const tick = setInterval(() => E.status(`${what}… ${Math.round((Date.now() - t0) / 1000)} s`), 500);
		let r;
		try {
			r = await (await fetch(url, { method: "POST" })).json();
		} catch (e) {
			r = { ok: false, errors: [String(e)] };
		}
		clearInterval(tick);
		btns.forEach((b) => (b.disabled = false));
		updateButtons();
		return r;
	};

	E.bake = async () => {
		if (!(await E.save())) return;
		const r = await E.runGodot("/api/bake", "Baking (Godot is placing everything)");
		E.baked = await get("/api/baked");
		E.bakedStale = false;
		refreshWarnings();
		E.draw();
		if (r.ok) E.status(`Baked in ${r.seconds} s: ${(E.baked.nodes || []).length} gatherables, ${(E.baked.warnings || []).length} warnings.`, "ok");
		else E.status("Bake failed: " + (r.errors || []).join(" / "), "bad");
	};

	E.reloadWorld = async () => {
		E.world = await get("world.json");
		await new Promise((done) => {
			mapImg = new Image();
			mapImg.onload = done;
			mapImg.onerror = done;
			mapImg.src = "map.png?" + Date.now();
		});
	};

	E.start = async () => {
		canvas = document.getElementById("map");
		ctx = canvas.getContext("2d");
		canvas.tabIndex = 0;
		E.status("Loading…");
		[E.layout, E.catalog, E.baked] = await Promise.all([get("/api/layout"), get("/api/catalog"), get("/api/baked")]);
		for (const k of ["terrain", "patches", "lines", "points"]) E.layout[k] = E.layout[k] || [];
		await E.reloadWorld();
		buildToolbar();
		E.setTool(SELECT);
		refreshLayers();
		refreshList();
		refreshWarnings();
		updateButtons();
		window.addEventListener("resize", resize);
		canvas.addEventListener("mousedown", onDown);
		window.addEventListener("mousemove", (ev) => { if (ev.target === canvas || drag) onMove(ev.target === canvas ? ev : { offsetX: ev.clientX - canvas.getBoundingClientRect().left, offsetY: ev.clientY - canvas.getBoundingClientRect().top, shiftKey: ev.shiftKey, altKey: ev.altKey }); });
		window.addEventListener("mouseup", (ev) => { if (drag || ev.target === canvas) onUp(ev.target === canvas ? ev : { offsetX: ev.clientX - canvas.getBoundingClientRect().left, offsetY: ev.clientY - canvas.getBoundingClientRect().top, shiftKey: ev.shiftKey }); });
		canvas.addEventListener("dblclick", onDbl);
		canvas.addEventListener("wheel", onWheel, { passive: false });
		canvas.addEventListener("contextmenu", (ev) => ev.preventDefault());
		window.addEventListener("keydown", onKey);
		window.addEventListener("beforeunload", (ev) => { if (E.dirty) { ev.preventDefault(); ev.returnValue = ""; } });
		document.getElementById("undo").onclick = E.undo;
		document.getElementById("redo").onclick = E.redo;
		document.getElementById("save").onclick = E.save;
		document.getElementById("bake").onclick = E.bake;
		document.getElementById("filter").oninput = refreshList;
		resize();
		E.status(`${E.layout.patches.length} patches, ${E.layout.lines.length} lines, ${E.layout.points.length} points.`);
	};

	return E;
})();
