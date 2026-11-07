// Town mode (plans/town-designer.md): the map editor's part for the village itself. The Town button
// (or ?town=1) zooms to the map's village area, shows its tools (those registered with `modes`
// holding "town") and lists only the village's things, grouped: its buildings, the ones you added,
// plots, the street, lanes, hedges and walls, decorations. Everything else on the map stays drawn,
// shaded, and can't be picked by clicking empty ground (the village area isn't selected in town).
"use strict";

(() => {
	const E = Editor;
	const REACH = 110;  // (m from the village's middle: what counts as the village's without an `area` tag)

	/** The map's village area, or null. */
	E.villageArea = () => (E.layout.areas || []).find((a) => a.type === "village") || null;

	/** Whether `o` (of collection `kind`) is the village's: tagged with its area, owned by one of its
	 * buildings, or (untagged) standing within REACH of its middle. */
	E.inVillage = (kind, o) => {
		const v = E.villageArea();
		if (!v) return false;
		if (o.area) return o.area === v.id;
		if (o.owner) return true;
		if (kind === "plots") return true;
		if (kind === "anchors") return false;  // (the places: their own)
		if (kind === "terrain") return !!o.village;
		const near = (p) => E.dist(p[0], p[1], v.at[0], v.at[1]) < REACH;
		if (o.at) return near(o.at);
		if (o.points) return o.points.some(near);
		if (o.center) return near(o.center);
		return false;
	};

	const isWalk = (o) => !!(E.catalog.lines[o.type] || {}).walk;
	const section = (o) => (E.points ? E.points.section(o.type) : null);

	/** The list's groups in town mode: [[heading, [[kind, obj]...]]]. */
	E.townGroups = () => {
		const mine = (kind) => (E.layout[kind] || []).filter((o) => E.inVillage(kind, o)).map((o) => [kind, o]);
		const anchors = mine("anchors"), lines = mine("lines"), points = mine("points");
		return [
			["Buildings", anchors.filter(([, o]) => !o.type)],
			["Added buildings", anchors.filter(([, o]) => o.type)],
			["Plots", mine("plots")],
			["Street", mine("terrain")],
			["Lanes", lines.filter(([, o]) => isWalk(o))],
			["Hedges and walls", lines.filter(([, o]) => !isWalk(o))],
			["Decorations", points.filter(([, o]) => section(o) !== "gatherables")],
			["Trees and rocks", points.filter(([, o]) => section(o) === "gatherables")],
		];
	};

	/** The view on the village, all of it in sight. */
	E.townView = () => {
		const v = E.villageArea();
		if (!v) return;
		const r = document.getElementById("stage").getBoundingClientRect();
		E.view.cx = v.at[0];
		E.view.cz = v.at[1];
		E.view.s = Math.max(1, Math.min(r.width, r.height) / (REACH * 2.1));
	};

	/** Shades the map outside the village (drawn over the shapes, under the handles). */
	E.townShade = (ctx) => {
		const v = E.villageArea();
		if (!v) return;
		const [sx, sy] = E.toScreen(v.at[0], v.at[1]);
		const r = REACH * E.view.s;
		const c = ctx.canvas, dpr = window.devicePixelRatio || 1;
		ctx.beginPath();
		ctx.rect(-10, -10, c.width / dpr + 20, c.height / dpr + 20);
		ctx.arc(sx, sy, r, 0, Math.PI * 2, true);
		ctx.fillStyle = "rgba(20, 22, 17, 0.45)";
		ctx.fill("evenodd");
		ctx.beginPath();
		ctx.arc(sx, sy, r, 0, Math.PI * 2);
		ctx.setLineDash([6, 6]);
		ctx.lineWidth = 1;
		ctx.strokeStyle = "rgba(243, 234, 210, 0.35)";
		ctx.stroke();
		ctx.setLineDash([]);
		if (E.drawYards) E.drawYards(ctx);
	};

	// --- the street ---------------------------------------------------------------------------------

	/** The village's street: its road line (the village's own road), or null. */
	E.townStreet = () => {
		const v = E.villageArea();
		return (E.layout.terrain || []).find((t) => t.type === "road" && v && t.area === v.id) || null;
	};
	/** The nearest point on the street to (x, z), or null. */
	E.nearestOnStreet = (x, z) => {
		const st = E.townStreet();
		if (!st) return null;
		let best = null, bd = Infinity;
		for (let i = 1; i < st.points.length; i++) {
			const [ax, az] = st.points[i - 1], [bx, bz] = st.points[i];
			const dx = bx - ax, dz = bz - az, l = dx * dx + dz * dz;
			const t = l ? Math.max(0, Math.min(1, ((x - ax) * dx + (z - az) * dz) / l)) : 0;
			const p = [ax + t * dx, az + t * dz], d = E.dist(x, z, p[0], p[1]);
			if (d < bd) { bd = d; best = p; }
		}
		return best;
	};
	/** The turn (degrees, 15° steps) that faces (x, z)'s front (+Z) toward the street, or null. */
	E.faceStreet = (x, z) => {
		const p = E.nearestOnStreet(x, z);
		if (!p || E.dist(x, z, p[0], p[1]) < 0.5) return null;
		return Math.round(Math.atan2(p[0] - x, p[1] - z) * 180 / Math.PI / 15) * 15;
	};

	// --- the Building tool: add buildings from the catalog's list -------------------------------------

	const brush = { type: "cottage", yaw: 0, face: true };
	let hover = null;
	const yawAt = (x, z) => (brush.face ? E.faceStreet(x, z) ?? brush.yaw : brush.yaw);
	const ghost = (x, z) => ({ id: "_ghost", type: brush.type, at: [x, z], yaw: yawAt(x, z) });

	E.registerTool({
		id: "building",
		label: "Building",
		modes: ["town"],
		title: "Add a building from the list (a cottage, a barn, a shed...)",
		options(box) {
			const el = E.el;
			const row = el("span", { class: "row" });
			for (const k in E.catalog.buildings || {}) {
				const t = E.catalog.buildings[k];
				const [x0, z0, x1, z1] = t.box;
				const sw = el("span", { class: "foot", style: `width:${Math.max(4, (x1 - x0) * 1.6)}px;height:${Math.max(4, (z1 - z0) * 1.6)}px` });
				row.append(el("button", { class: k === brush.type ? "on" : "", title: `${t.label}: ${Math.round(x1 - x0)} × ${Math.round(z1 - z0)} m`,
					onclick: () => { brush.type = k; E.setTool(E.tool); } }, sw, t.label));
			}
			const face = el("input", { type: "checkbox" });
			face.checked = brush.face;
			face.onchange = () => { brush.face = face.checked; };
			box.append(row, el("label", { class: "row" }, face, "face the street"));
		},
		hint: () => `Click to put a ${(E.catalog.buildings[brush.type] || {}).label || brush.type} down${brush.face ? " (facing the street)" : ""}. R turns it 15° (untick "face the street" first). Esc: back to Select.`,
		move(x, z) { hover = [x, z]; },
		down(x, z) {
			const t = E.catalog.buildings[brush.type];
			const v = E.villageArea();
			const o = { id: E.uniqueId(brush.type), type: brush.type, at: [E.round(x), E.round(z)], yaw: yawAt(x, z), pad: t.pad };
			if (v) o.area = v.id;
			E.commit();
			E.layout.anchors.push(o);
			E.select("anchors", o);
			E.changed();
		},
		keydown(ev) {
			if (ev.key.toLowerCase() === "r") { brush.face = false; brush.yaw = (brush.yaw + (ev.shiftKey ? -15 : 15) + 540) % 360 - 180; E.setTool(E.tool); return true; }
			if (ev.key === "Escape") { E.setTool(null); return true; }
			return false;
		},
		preview(ctx) {
			if (!hover || !E.buildingCorners) return;
			const g = ghost(hover[0], hover[1]);
			E.path(E.buildingCorners(g), true);
			ctx.fillStyle = "rgba(196, 149, 95, 0.35)";
			ctx.fill();
			ctx.setLineDash([5, 4]);
			ctx.lineWidth = 1.5;
			ctx.strokeStyle = "#fff";
			ctx.stroke();
			ctx.setLineDash([]);
			const d = E.buildingDoor(g);
			if (d) {
				const [sx, sy] = E.toScreen(d[0], d[1]);
				ctx.beginPath();
				ctx.arc(sx, sy, 3, 0, Math.PI * 2);
				ctx.fillStyle = "#f2d16b";
				ctx.fill();
			}
		},
	});

	// --- what a building owns (phase 3) ---------------------------------------------------------------

	const OWNABLE = ["points", "lines", "plots"];
	/** Everything owned by anchor `id`: [[collection, obj]...]. (The editor carries them when it moves.) */
	E.ownedBy = (id) => {
		const out = [];
		for (const k of OWNABLE) for (const x of E.layout[k] || []) if (x.owner === id) out.push([k, x]);
		return out;
	};
	const buildingName = (a) => (E.buildingShape ? E.buildingShape(a).name : a.id);
	/** The village's buildings that can own things: [[id, name]], nearest to (x, z) first if given. */
	E.ownerChoices = (x, z) => {
		const list = (E.layout.anchors || []).filter((a) => a.placed !== false && E.inVillage("anchors", a) && a.id !== "green");
		if (x !== undefined) list.sort((a, b) => E.dist(x, z, ...a.at) - E.dist(x, z, ...b.at));
		return list.map((a) => [a.id, buildingName(a)]);
	};
	/** The building nearest (x, z) within `reach` m of its edge, or null. */
	E.nearestBuilding = (x, z, reach = 12) => {
		let best = null, bd = reach;
		for (const a of E.layout.anchors || []) {
			if (a.placed === false || a.id === "green" || !E.inVillage("anchors", a) || !E.buildingCorners) continue;
			const pts = E.buildingCorners(a);
			let d = E.inPoly(x, z, pts) ? 0 : Infinity;
			for (let i = 0; i < 4; i++) d = Math.min(d, E.segDist(x, z, ...pts[i], ...pts[(i + 1) % 4]));
			if (d < bd) { bd = d; best = a; }
		}
		return best;
	};
	/** A "Belongs to" row for a point, line or plot's panel (town mode only). */
	E.ownerField = (o) => {
		if (!E.town) return null;
		const p = o.at || (o.points && o.points[0]) || [0, 0];
		return E.field("Belongs to", E.input(o, "owner", "select", {
			options: [["", "nobody (stays put)"], ...E.ownerChoices(p[0], p[1])],
			default: "", after: (v) => { if (!v) delete o.owner; },
		}));
	};

	/** The middle of anchor `a`'s front edge, and its frame there: [x, z] across and out, on the map. */
	const frontFrame = (a) => {
		const sh = E.buildingShape(a);
		const across = sh.door ? sh.door[0] : 0;
		return (l) => E.anchorToMap(a, across + l[0], sh.box[3] + l[1]);
	};
	/** Dresses building `a`'s front with preset `key` (its props owned by it). */
	E.dressFront = (a, key) => {
		const pre = E.catalog.presets[key];
		if (!pre) return;
		const at = frontFrame(a);
		E.commit();
		for (const [type, l, yaw] of pre.props) {
			const p = at(l);
			const v = E.villageArea();
			const o = { id: E.uniqueId(type), type, at: [E.round(p[0]), E.round(p[1])], yaw: Math.round(((a.yaw || 0) + yaw + 540) % 360 - 180), owner: a.id };
			if (v) o.area = v.id;
			E.layout.points.push(o);
		}
		E.changed(true);
		E.status(`${pre.label}: ${pre.props.length} things in front of ${buildingName(a)}.`, "ok");
	};
	/** Takes away the points building `a` owns (its garden's things; not its plots). */
	E.clearGarden = (a) => {
		const mine = E.ownedBy(a.id).filter(([k]) => k === "points");
		if (!mine.length) return;
		E.commit();
		for (const [, x] of mine) E.layout.points.splice(E.layout.points.indexOf(x), 1);
		E.changed();
	};

	/** The town's part of a building's panel: its garden. */
	E.townPanel = (a, box) => {
		if (!E.town || a.placed === false || a.id === "green" || !E.inVillage("anchors", a)) return;
		const el = E.el;
		const own = E.ownedBy(a.id);
		const row = el("div", { class: "row" });
		for (const k in E.catalog.presets || {}) row.append(el("button", { title: "Put these in front of it (they move with it)", onclick: () => E.dressFront(a, k) }, E.catalog.presets[k].label));
		box.append(E.block("Dress its front", row));
		const pts = own.filter(([k]) => k === "points").length, plots = own.filter(([k]) => k === "plots").length, lines = own.filter(([k]) => k === "lines").length;
		box.append(E.field("Its own", el("span", { class: "row" }, `${pts} things, ${plots} plots${lines ? `, ${lines} lines` : ""}`,
			pts ? el("button", { onclick: () => E.clearGarden(a) }, "Clear its things") : null)));
		if (E.yardPanel) E.yardPanel(a, box);
	};
})();
