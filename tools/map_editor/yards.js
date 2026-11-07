// Work yards (plans/town-designer.md, phase 6): each worker's yard is on their building's anchor,
// `yard: {props: [[model, [x, z], facing°, solid, y?]], stations: [[[x, z], facing°, motion, tier, y?]]}`
// in the building's own frame (+Z its front), so it goes where the building goes. The game builds it
// (scripts/work_yards.gd): the props from models/village/yard/, and the stations, the spots the worker
// stands at by day doing that motion, opened at that tier of the building.
// In town mode every yard is drawn; select its building to drag its props (square handles) and
// stations (round ones), turn them, add and remove them in the panel.
"use strict";

(() => {
	const E = Editor;
	const el = (...a) => E.el(...a);
	// (Villager.Work)
	const MOTIONS = ["CHOP", "HAMMER", "FISH", "ORATE", "TEND", "WIPE", "STOKE", "DUNK", "GRIND", "SAW", "KNEAD", "SWEEP", "SORT"];
	const WORDS = { CHOP: "chops", HAMMER: "hammers", FISH: "fishes", ORATE: "speaks", TEND: "tends", WIPE: "wipes", STOKE: "stokes", DUNK: "dunks", GRIND: "grinds", SAW: "saws", KNEAD: "kneads", SWEEP: "sweeps", SORT: "sorts" };

	/** The yard kit: the catalog's props from models/village/yard/ ([file name, label]). */
	const kit = () => Object.values(E.catalog.props).filter((p) => p.model.includes("/village/yard/"))
		.map((p) => [p.model.split("/").pop().replace(/\.glb$/, ""), p.label]);
	const kitId = (name) => Object.keys(E.catalog.props).find((k) => E.catalog.props[k].model.endsWith(`/yard/${name}.glb`)) || name;
	const hasWorker = (o) => E.buildingShape && E.buildingShape(o).kind === "building" && !o.type;
	const onMap = (o, l) => E.anchorToMap(o, l[0], l[1]);
	const local = (o, x, z) => E.toLocalFrame(o.at, o.yaw || 0, [x, z]).map(E.round);
	const turnBy = (deg, d) => Math.round((((deg + d) % 360) + 540) % 360 - 180);

	// --- drawing ------------------------------------------------------------------------------------

	let iconOf = (id) => {
		const img = new Image();
		img.src = `icons/${id}.png`;
		img.onload = () => E.draw();
		const cache = { [id]: img };
		iconOf = (k) => {
			if (!cache[k]) { cache[k] = new Image(); cache[k].src = `icons/${k}.png`; cache[k].onload = () => E.draw(); }
			return cache[k];
		};
		return img;
	};

	/** Every building's yard (town mode): faint, the selected building's bold and named. */
	E.drawYards = (ctx) => {
		for (const o of E.layout.anchors || []) {
			if (!o.yard || o.placed === false) continue;
			const sel = E.isSelected(o);
			if (!sel && E.view.s < 2.5) continue;
			ctx.globalAlpha = sel ? 1 : 0.55;
			for (const p of o.yard.props || []) {
				const [x, z] = onMap(o, p[1]);
				const [sx, sy] = E.toScreen(x, z);
				const img = iconOf(kitId(p[0]));
				const r = Math.max(7, Math.min(30, E.view.s * 1.1));
				if (img.complete && img.naturalWidth && E.view.s >= 3) ctx.drawImage(img, sx - r, sy - r, r * 2, r * 2);
				else { ctx.fillStyle = "#c9b48a"; ctx.fillRect(sx - 3, sy - 3, 6, 6); }
			}
			for (const [i, s] of (o.yard.stations || []).entries()) {
				const [x, z] = onMap(o, s[0]);
				const [sx, sy] = E.toScreen(x, z);
				const a = ((o.yaw || 0) + s[1]) * Math.PI / 180;
				ctx.beginPath();
				ctx.arc(sx, sy, 4.5, 0, Math.PI * 2);
				ctx.fillStyle = "#7fc6d9";
				ctx.fill();
				ctx.lineWidth = 1.2;
				ctx.strokeStyle = "#14160f";
				ctx.stroke();
				ctx.beginPath();
				ctx.moveTo(sx, sy);
				ctx.lineTo(sx + Math.sin(a) * 11, sy + Math.cos(a) * 11);
				ctx.lineWidth = 2;
				ctx.strokeStyle = "#7fc6d9";
				ctx.stroke();
				if (sel && E.view.s >= 3) {
					ctx.font = "10px system-ui, sans-serif";
					ctx.textAlign = "left";
					ctx.lineWidth = 3;
					ctx.strokeStyle = "rgba(20, 20, 15, 0.85)";
					const t = `${i + 1} ${WORDS[s[2]] || s[2]}${s[3] > 1 ? ` (tier ${s[3]})` : ""}`;
					ctx.strokeText(t, sx + 7, sy - 5);
					ctx.fillStyle = "#cfeaf2";
					ctx.fillText(t, sx + 7, sy - 5);
				}
			}
			ctx.globalAlpha = 1;
		}
	};

	// --- handles: drag a prop or a station -----------------------------------------------------------

	const base = E.kinds.anchors.handles;
	E.kinds.anchors.handles = (o) => {
		const hs = base(o);
		if (!E.town || !o.yard || o.placed === false) return hs;
		for (const p of o.yard.props || []) {
			const [x, z] = onMap(o, p[1]);
			hs.push({ x, z, yard: true, set: (mx, mz) => { p[1] = local(o, mx, mz); } });
		}
		for (const s of o.yard.stations || []) {
			const [x, z] = onMap(o, s[0]);
			hs.push({ x, z, yard: true, round: true, set: (mx, mz) => { s[0] = local(o, mx, mz); } });
		}
		return hs;
	};

	// --- the panel ------------------------------------------------------------------------------------

	const change = (fn) => () => { E.commit(); fn(); E.changed(); };
	E.yardPanel = (o, box) => {
		if (!E.town || !hasWorker(o)) return;
		if (!o.yard) {
			box.append(E.block("Work yard", el("div", { class: "row" }, el("span", { class: "muted" }, "None in the layout."),
				el("button", { onclick: change(() => { o.yard = { props: [], stations: [] }; }) }, "Give it a yard"))));
			return;
		}
		const y = o.yard;
		const wrap = el("div", { class: "items" });
		y.props.forEach((p, i) => {
			const solid = el("input", { type: "checkbox", title: "Solid: you and the villagers bump into it" });
			solid.checked = !!p[3];
			solid.onchange = change(() => { p[3] = solid.checked; });
			wrap.append(el("div", { class: "row" },
				el("img", { src: `icons/${kitId(p[0])}.png`, width: 22, height: 22 }),
				el("span", { style: "flex:1" }, (E.catalog.props[kitId(p[0])] || {}).label || p[0]),
				el("button", { title: "Turn 15° left", onclick: change(() => { p[2] = turnBy(p[2], -15); }) }, "⟲"),
				el("button", { title: "Turn 15° right", onclick: change(() => { p[2] = turnBy(p[2], 15); }) }, "⟳"),
				solid,
				el("button", { title: "Take it away", onclick: change(() => { y.props.splice(i, 1); }) }, "✕")));
		});
		const add = el("select", {}, ...kit().map(([k, l]) => el("option", { value: k }, l)));
		const [, , x1] = E.buildingShape(o).box;
		wrap.append(el("div", { class: "row" }, add, el("button", {
			onclick: change(() => { y.props.push([add.value, [E.round(x1 + 2.5), 0], 0, true]); }),
		}, "Add")));
		box.append(E.block("Work yard: its things (square handles)", wrap));
		const st = el("div", { class: "items" });
		y.stations.forEach((s, i) => {
			const m = el("select", { onchange: change(() => { s[2] = m.value; }) }, ...MOTIONS.map((k) => el("option", { value: k }, WORDS[k])));
			m.value = s[2];
			const t = el("select", { title: "Opened at this tier of the building", onchange: change(() => { s[3] = Number(t.value); }) }, ...[1, 2, 3, 4].map((k) => el("option", { value: k }, `tier ${k}`)));
			t.value = String(s[3]);
			st.append(el("div", { class: "row" }, el("span", {}, `${i + 1}`), m, t,
				el("button", { title: "Turn 15° left", onclick: change(() => { s[1] = turnBy(s[1], -15); }) }, "⟲"),
				el("button", { title: "Turn 15° right", onclick: change(() => { s[1] = turnBy(s[1], 15); }) }, "⟳"),
				el("button", { title: "Take it away", onclick: change(() => { y.stations.splice(i, 1); }) }, "✕")));
		});
		st.append(el("div", { class: "row" }, el("button", { onclick: change(() => { y.stations.push([[E.round(x1 + 2.5), 1.5], 180, "TEND", 1]); }) }, "Add a station")));
		box.append(E.block("Work yard: where they stand (round handles)", st));
		box.append(el("p", { class: "muted" }, "By day the worker goes from station to station doing what it says (the ones open at the building's tier). Drag a thing or a station by its handle; they're in the building's frame, so they move and turn with it."));
	};
})();
