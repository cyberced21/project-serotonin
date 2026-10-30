// Patches (plans/map-editor.md): an area — a polygon or a circle, a circle with an inner radius
// being a ring — that the bake fills with gatherables of a kind and tier (the items' mix), `count`
// of them, `spacing` apart, on the grounds it allows. Reshaping a patch keeps its density.
"use strict";

(() => {
	const E = Editor;
	const KINDS = { wood: "Wood", rock: "Rock", crop: "Crop" };
	const TIER_NAMES = ["T0", "T1", "T2", "T3"];
	/** Gatherables a new patch gets per 1000 m² unless you say otherwise. */
	const DEFAULT_DENSITY = { wood: 6, rock: 3, crop: 25 };
	const DEFAULT_SPACING = { wood: 4.5, rock: 4, crop: 3.5 };

	const area = (o) => o.shape === "circle"
		? Math.PI * (o.radius * o.radius - (o.inner || 0) * (o.inner || 0))
		: E.polyArea(o.points || []);
	const density = (o) => (area(o) > 0 ? (o.count / area(o)) * 1000 : 0);

	/** The heaviest item's kind and colour. */
	const main = (o) => {
		let best = null, w = -1;
		for (const id in o.items || {}) if (o.items[id] > w) { best = id; w = o.items[id]; }
		return E.catalog.gatherables[best] || { kind: "wood", tier: 0, color: "#888" };
	};
	const tierOf = (o) => {
		let t = 0;
		for (const id in o.items || {}) t = Math.max(t, (E.catalog.gatherables[id] || {}).tier || 0);
		return t;
	};

	const centre = (o) => {
		if (o.shape === "circle") return o.center;
		let x = 0, z = 0;
		for (const p of o.points) { x += p[0]; z += p[1]; }
		return [x / o.points.length, z / o.points.length];
	};

	const hexA = (hex, a) => {
		const n = parseInt(hex.slice(1), 16);
		return `rgba(${(n >> 16) & 255}, ${(n >> 8) & 255}, ${n & 255}, ${a})`;
	};

	E.registerKind("patches", {
		label: "Patch",
		title: (o) => `${o.name || o.id}  ·  ${KINDS[main(o).kind] || ""} ${TIER_NAMES[tierOf(o)]} ×${o.count}`,
		color: (o) => main(o).color,
		draw(ctx, o, selected) {
			const col = main(o).color;
			if (o.shape === "circle") {
				const [sx, sy] = E.toScreen(o.center[0], o.center[1]);
				ctx.beginPath();
				ctx.arc(sx, sy, o.radius * E.view.s, 0, Math.PI * 2);
				if (o.inner > 0) ctx.arc(sx, sy, o.inner * E.view.s, 0, Math.PI * 2, true);
			} else {
				if (!o.points || o.points.length < 2) return;
				E.path(o.points, true);
			}
			ctx.fillStyle = hexA(col, selected ? 0.38 : 0.2);
			ctx.fill("evenodd");
			ctx.lineWidth = selected ? 2.5 : 1.5;
			ctx.strokeStyle = selected ? "#fff" : hexA(col, 0.95);
			ctx.setLineDash(o.ground && o.ground.length ? [] : [6, 3]);
			ctx.stroke();
			ctx.setLineDash([]);
			if (E.view.s > 1.6 || selected) {
				const [x, z] = centre(o);
				const [sx, sy] = E.toScreen(x, z);
				ctx.font = "11px system-ui, sans-serif";
				ctx.textAlign = "center";
				const t = `${TIER_NAMES[tierOf(o)]} ×${o.count}`;
				ctx.lineWidth = 3;
				ctx.strokeStyle = "rgba(15, 15, 10, 0.75)";
				ctx.strokeText(t, sx, sy + 4);
				ctx.fillStyle = "#fff";
				ctx.fillText(t, sx, sy + 4);
			}
		},
		hit(o, x, z, tol) {
			if (o.shape === "circle") {
				const d = E.dist(x, z, o.center[0], o.center[1]);
				return d <= o.radius + tol && d >= (o.inner || 0) - tol ? area(o) : false;
			}
			if (E.inPoly(x, z, o.points)) return area(o);
			for (let i = 0; i < o.points.length; i++) {
				const a = o.points[i], b = o.points[(i + 1) % o.points.length];
				if (E.segDist(x, z, a[0], a[1], b[0], b[1]) < tol) return area(o);
			}
			return false;
		},
		handles(o) {
			if (o.shape === "circle") {
				const hs = [
					{ x: o.center[0], z: o.center[1], round: true, set: (x, z) => { o.center = [x, z]; } },
					{ x: o.center[0] + o.radius, z: o.center[1], set: (x, z) => { o.radius = Math.max((o.inner || 0) + 1, E.dist(x, z, o.center[0], o.center[1])); } },
				];
				if (o.inner > 0) hs.push({ x: o.center[0] - o.inner, z: o.center[1], set: (x, z) => { o.inner = Math.min(o.radius - 1, E.dist(x, z, o.center[0], o.center[1])); } });
				return hs;
			}
			return o.points.map((p, i) => ({
				x: p[0], z: p[1],
				set: (x, z) => { o.points[i] = [x, z]; },
				remove: o.points.length > 3 ? () => o.points.splice(i, 1) : null,
			}));
		},
		move(o, dx, dz) {
			if (o.shape === "circle") o.center = [o.center[0] + dx, o.center[1] + dz];
			else o.points = o.points.map((p) => [p[0] + dx, p[1] + dz]);
		},
		insertAt(o, x, z, tol) {
			if (o.shape === "circle") return false;
			for (let i = 0; i < o.points.length; i++) {
				const a = o.points[i], b = o.points[(i + 1) % o.points.length];
				if (E.segDist(x, z, a[0], a[1], b[0], b[1]) < tol) { o.points.splice(i + 1, 0, [E.round(x), E.round(z)]); return true; }
			}
			return false;
		},
		// reshaping keeps the density: the count follows the area
		beginEdit(o) { o._density = density(o); },
		endEdit(o) {
			if (o._density !== undefined) o.count = Math.max(1, Math.round((area(o) * o._density) / 1000));
			delete o._density;
		},
		panel(o, box) { panel(o, box); },
	});

	// --- the properties panel ---------------------------------------------------------------------

	/** Sets a patch's items to its kind and tier's mix from the catalog. */
	const setTier = (o, kind, tier) => {
		const mix = ((E.catalog.tiers[kind] || {})[String(tier)]) || {};
		o.items = { ...mix };
	};

	const panel = (o, box) => {
		const el = E.el;
		box.append(E.field("Name", E.input(o, "name")));
		box.append(E.field("Id", E.input(o, "id", "text", { readonly: true })));
		// kind and tier: picking one resets the mix to that tier's
		const m = main(o);
		const kindSel = el("select", {}, ...Object.keys(KINDS).map((k) => el("option", { value: k }, KINDS[k])));
		kindSel.value = m.kind;
		const tierSel = el("select", {}, ...[0, 1, 2].map((t) => el("option", { value: t }, TIER_NAMES[t])));
		tierSel.value = tierOf(o);
		const apply = () => {
			E.commit();
			setTier(o, kindSel.value, Number(tierSel.value));
			if (!o.spacing) o.spacing = DEFAULT_SPACING[kindSel.value];
			E.changed();
		};
		kindSel.onchange = apply;
		tierSel.onchange = apply;
		box.append(E.field("Kind, tier", el("div", { class: "row" }, kindSel, tierSel)));

		// the mix
		const items = el("div", { class: "items" });
		const opts = Object.keys(E.catalog.gatherables).map((id) => {
			const g = E.catalog.gatherables[id];
			return [id, `${g.label} · T${g.tier}`];
		});
		for (const id of Object.keys(o.items || {})) {
			const s = el("select", {}, ...opts.map(([v, l]) => el("option", { value: v }, l)));
			s.value = id;
			s.onchange = () => {
				E.commit();
				const w = o.items[id];
				delete o.items[id];
				o.items[s.value] = (o.items[s.value] || 0) + w;
				E.changed();
			};
			const w = el("input", { type: "number", step: "0.1", min: "0", value: o.items[id], title: "How often, against the others" });
			w.onchange = () => { E.commit(); o.items[id] = Math.max(0, Number(w.value)); E.changed(true); };
			const del = el("button", { title: "Take it out of the mix", onclick: () => { E.commit(); delete o.items[id]; E.changed(); } }, "×");
			items.append(el("div", { class: "row" }, el("span", { class: "swatch", style: `background:${E.gatherableColor(id)}` }), s, w, del));
		}
		items.append(el("button", {
			onclick: () => {
				E.commit();
				const free = Object.keys(E.catalog.gatherables).find((id) => !(id in o.items));
				if (free) o.items[free] = 1;
				E.changed();
			},
		}, "+ add to the mix"));
		box.append(E.block("Mix (how often each, against the others)", items));

		// how many: the count, or the density
		const a = area(o);
		const dens = el("input", { type: "number", step: "0.1", min: "0", value: density(o).toFixed(1), title: "Gatherables per 1000 m²" });
		dens.onchange = () => { E.commit(); o.count = Math.max(1, Math.round((a * Number(dens.value)) / 1000)); E.changed(); };
		box.append(E.field("Count", E.input(o, "count", "number", { step: 1, min: 1, refresh: true })));
		box.append(E.field("Per 1000 m²", el("div", { class: "row" }, dens, el("span", { class: "muted" }, `${Math.round(a)} m²`))));
		box.append(E.field("Spacing (m)", E.input(o, "spacing", "number", { step: 0.5, min: 1 })));
		if (o.shape === "circle") {
			box.append(E.field("Radius (m)", E.input(o, "radius", "number", { step: 0.5, min: 1, refresh: true })));
			box.append(E.field("Inner (m)", E.input(o, "inner", "number", { step: 0.5, min: 0, refresh: true, default: 0 })));
		}
		// the grounds it may stand on
		const chips = el("div", { class: "chips" });
		for (const g of Object.keys(E.catalog.grounds)) {
			const c = el("input", { type: "checkbox" });
			c.checked = (o.ground || []).includes(g);
			c.onchange = () => {
				E.commit();
				o.ground = Object.keys(E.catalog.grounds).filter((n) => n === g ? c.checked : (o.ground || []).includes(n));
				E.changed(true);
			};
			chips.append(el("label", {}, c, g));
		}
		box.append(E.block("Only on", chips));
		box.append(el("p", { class: "muted" }, "None ticked: anywhere that isn't a path, road, quarry stone or crop square (dashed outline)."));
		const seed = E.input(o, "seed", "number", { step: 1 });
		box.append(E.field("Seed", el("div", { class: "row" }, seed,
			el("button", { title: "Shuffle where they stand", onclick: () => { E.commit(); o.seed = Math.floor(Math.random() * 1e9); E.changed(); } }, "Reroll"))));
	};

	E.patches = { area, density, setTier, DEFAULT_DENSITY, DEFAULT_SPACING, KINDS, TIER_NAMES };
})();
