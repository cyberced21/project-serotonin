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
})();
