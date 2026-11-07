// The market place (plans/town-designer.md, phase 7): the street's widened lens round the green, and
// everything on it. On the green's anchor:
//   market  {length, half_width}: its size (m; WorldMap.market_length() / market_widest(); without it
//           52 and 14). The terrain generator paves it: changing it regenerates the land.
//   spots   {name: [x, z, facing°]} in the green's frame: where the town designer moved what's on it.
//           Its benches, lamps, crates, pond and the villagers' spots there (Village/Green's children:
//           LayoutAnchors stands them) and the decorations VillageDecor builds (the noticeboard, the
//           stall, the benches, planters, well, fountain, weathervane and cart the projects add).
//           The baskets hang on the lamps and the bunting runs between them, so they follow the lamps.
// In town mode the lens is drawn; select the green to size it (square handles) and drag what's on it
// (round handles); turn or put back each one in the panel.
"use strict";

(() => {
	const E = Editor;
	const el = (...a) => E.el(...a);
	const LENGTH = 52, HALF = 14;
	// name -> [label, x, z, facing°] as main.tscn's Village/Green and village_decor.gd have them
	const SPOTS = {
		noticeboard: ["Noticeboard", -13, -4.5, 0],
		stall: ["Market stall", 12, 4, -108.5],
		BenchA: ["Bench (west)", -12.5, 7, 98.8],
		BenchB: ["Bench (east)", 3.5, 9, -107.5],
		Lamp1: ["Lamp (north-west)", -16.5, -3, 79.7],
		Lamp2: ["Lamp (north-east)", 16.5, -3, -79.7],
		Lamp3: ["Lamp (south-east)", 16.5, 3, -100.3],
		Lamp4: ["Lamp (south-west)", -16.5, 3, 100.3],
		Crates1: ["Crates", 11, -4, -70],
		VillagePond: ["Pond", -6, 6, 0],
		baker_cottage_Square: ["Rosa's spot", 8, 4, -116.6],
		prospector_cottage_Square: ["Edda's spot", -8, -9, 41.6],
		"benches/0": ["New bench (project)", 15, -3.5, -76.9],
		"benches/1": ["New bench 2 (project)", -8, -4.5, 60.6],
		"flower_boxes/0": ["Planter 1 (project)", -14, -3.2, 77.1],
		"flower_boxes/1": ["Planter 2 (project)", -14, 3.6, 104.4],
		"flower_boxes/2": ["Planter 3 (project)", 4, -13, -17.1],
		"flower_boxes/3": ["Planter 4 (project)", -2, 13, 171.3],
		"well/0": ["Well (project)", 3, -9.5, -17.5],
		"fountain/0": ["Fountain (project)", 7, -5, 0],
		"deco_weathervane/0": ["Weathervane (project)", -4, -11.5, 0],
		"deco_cart/0": ["Painted cart (project)", 19, -3, -84.2],
	};
	// a bench's sitter's spot goes with the bench (Village/Green/<trade>_Bench)
	const LINKED = { BenchA: "woodcutter_Bench", BenchB: "fisher_Bench" };
	const ICON = { BenchA: "bench", BenchB: "bench", Lamp1: "lamp_post", Lamp2: "lamp_post", Lamp3: "lamp_post", Lamp4: "lamp_post", Crates1: "crates" };

	const green = () => (E.layout.anchors || []).find((a) => a.id === "green" && a.placed !== false) || null;
	const size = (g) => [(g.market && g.market.length) || LENGTH, (g.market && g.market.half_width) || HALF];
	const halfAt = (g, along) => { const [l, h] = size(g); return Math.abs(along) >= l / 2 ? 0 : h * Math.sin(Math.PI * (along + l / 2) / l); };
	const spotOf = (g, name) => { const s = (g.spots || {})[name]; const d = SPOTS[name]; return s ? [s[0], s[1], s[2] ?? d[3]] : [d[1], d[2], d[3]]; };
	const setSpot = (g, name, v) => {
		g.spots = g.spots || {};
		g.spots[name] = [E.round(v[0]), E.round(v[1]), Math.round(v[2] * 10) / 10];
		if (LINKED[name]) g.spots[LINKED[name]] = g.spots[name].slice();
	};
	const resetSpot = (g, name) => {
		if (!g.spots) return;
		delete g.spots[name];
		if (LINKED[name]) delete g.spots[LINKED[name]];
		if (!Object.keys(g.spots).length) delete g.spots;
	};
	/** The lens's outline on the map. */
	const lens = (g) => {
		const [l] = size(g), pts = [];
		for (let k = 0; k <= 24; k++) { const x = -l / 2 + (l * k) / 24; pts.push(E.anchorToMap(g, x, -halfAt(g, x))); }
		for (let k = 24; k >= 0; k--) { const x = -l / 2 + (l * k) / 24; pts.push(E.anchorToMap(g, x, halfAt(g, x))); }
		return pts;
	};
	E.marketLens = () => { const g = green(); return g ? lens(g) : null; };

	const icons = {};
	const iconImg = (id) => {
		if (!icons[id]) { icons[id] = new Image(); icons[id].src = `icons/${id}.png`; icons[id].onload = () => E.draw(); }
		return icons[id].complete && icons[id].naturalWidth ? icons[id] : null;
	};

	E.drawMarket = (ctx) => {
		const g = green();
		if (!g) return;
		const sel = E.isSelected(g);
		E.path(lens(g), true);
		ctx.fillStyle = sel ? "rgba(217, 164, 65, 0.16)" : "rgba(217, 164, 65, 0.07)";
		ctx.fill();
		ctx.setLineDash([7, 4]);
		ctx.lineWidth = sel ? 2 : 1;
		ctx.strokeStyle = sel ? "#f2d16b" : "rgba(242, 209, 107, 0.55)";
		ctx.stroke();
		ctx.setLineDash([]);
		if (!sel && E.view.s < 3) return;
		for (const name in SPOTS) {
			const [lx, lz, yaw] = spotOf(g, name);
			const [x, z] = E.anchorToMap(g, lx, lz);
			const [sx, sy] = E.toScreen(x, z);
			const img = ICON[name] && E.view.s >= 4 ? iconImg(ICON[name]) : null;
			ctx.globalAlpha = sel ? 1 : 0.6;
			if (img) { const r = Math.min(28, E.view.s * 1.2); ctx.drawImage(img, sx - r, sy - r, r * 2, r * 2); }
			else {
				ctx.beginPath();
				ctx.arc(sx, sy, 4, 0, Math.PI * 2);
				ctx.fillStyle = name.includes("/") ? "#c98bb0" : name.endsWith("Square") ? "#7fc6d9" : "#f2d16b";
				ctx.fill();
			}
			const a = ((g.yaw || 0) + yaw) * Math.PI / 180;
			ctx.beginPath();
			ctx.moveTo(sx, sy);
			ctx.lineTo(sx + Math.sin(a) * 10, sy + Math.cos(a) * 10);
			ctx.lineWidth = 1.5;
			ctx.strokeStyle = "#f2d16b";
			ctx.stroke();
			if (sel && E.view.s >= 4) {
				ctx.font = "10px system-ui, sans-serif";
				ctx.textAlign = "left";
				ctx.lineWidth = 3;
				ctx.strokeStyle = "rgba(20, 20, 15, 0.85)";
				ctx.strokeText(SPOTS[name][0], sx + 7, sy + 3);
				ctx.fillStyle = "#f6edd3";
				ctx.fillText(SPOTS[name][0], sx + 7, sy + 3);
			}
			ctx.globalAlpha = 1;
		}
	};

	const base = E.kinds.anchors.handles;
	E.kinds.anchors.handles = (o) => {
		const hs = base(o);
		if (!E.town || o.id !== "green" || o.placed === false) return hs;
		const [l, h] = size(o);
		const local = (x, z) => E.toLocalFrame(o.at, o.yaw || 0, [x, z]);
		const [ex, ez] = E.anchorToMap(o, l / 2, 0), [wx, wz] = E.anchorToMap(o, 0, -h);
		hs.push({ x: ex, z: ez, set: (x, z) => { o.market = { length: E.round(Math.max(20, Math.min(120, Math.abs(local(x, z)[0]) * 2))), half_width: size(o)[1] }; } });
		hs.push({ x: wx, z: wz, set: (x, z) => { o.market = { length: size(o)[0], half_width: E.round(Math.max(5, Math.min(30, Math.abs(local(x, z)[1])))) }; } });
		for (const name in SPOTS) {
			const [lx, lz, yaw] = spotOf(o, name);
			const [x, z] = E.anchorToMap(o, lx, lz);
			hs.push({ x, z, round: true, set: (mx, mz) => { const p = local(mx, mz); setSpot(o, name, [p[0], p[1], yaw]); } });
		}
		return hs;
	};

	E.marketPanel = (g, box) => {
		if (!E.town || g.id !== "green") return;
		const [l, h] = size(g);
		const num = (value, min, max, onset) => {
			const i = el("input", { type: "number", step: "1", min: String(min), max: String(max), value: String(value) });
			i.onchange = () => { E.commit(); onset(Math.max(min, Math.min(max, Number(i.value)))); E.changed(); };
			return i;
		};
		box.append(E.field("Market (m)", el("span", { class: "row" },
			num(l, 20, 120, (v) => { g.market = { length: v, half_width: size(g)[1] }; }), "long,",
			num(h * 2, 10, 60, (v) => { g.market = { length: size(g)[0], half_width: v / 2 }; }), "across",
			g.market ? el("button", { title: "Back to 52 × 28 m", onclick: () => { E.commit(); delete g.market; E.changed(); } }, "Reset") : null)));
		const list = el("div", { class: "items" });
		for (const name in SPOTS) {
			const moved = !!(g.spots && g.spots[name]);
			const turn = (d) => () => { E.commit(); const s = spotOf(g, name); setSpot(g, name, [s[0], s[1], (((s[2] + d) % 360) + 540) % 360 - 180]); E.changed(); };
			list.append(el("div", { class: "row" },
				el("span", { style: "flex:1", class: moved ? "" : "muted" }, SPOTS[name][0]),
				el("button", { title: "Turn 15° left", onclick: turn(-15) }, "⟲"),
				el("button", { title: "Turn 15° right", onclick: turn(15) }, "⟳"),
				el("button", { title: "Put it back where it was", disabled: !moved, onclick: () => { E.commit(); resetSpot(g, name); E.changed(); } }, "↺")));
		}
		box.append(E.block("On the market place (round handles; grey: where it always was)", list));
		box.append(el("p", { class: "muted" }, "Drag the square handles to make the market longer or wider (the land is repaved on Save & bake). The projects' things (benches, planters, well...) only show in the game once they're paid for. The baskets and bunting follow the lamps; a bench's sitter follows the bench."));
	};
})();
