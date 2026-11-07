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
})();
