// Lines and points (plans/map-editor.md). A line is a run of hedge, wall or fence along its
// points; the bake cuts it where it would cross a road or water or climb a steep bank (unless
// `clip` is off), and leaves a `gate`-wide gap every `gate_every` m. A point is one thing from the
// catalog: a gatherable, a prop or a fixture, turned `yaw` degrees.
"use strict";

(() => {
	const E = Editor;

	const lineColor = (o) => (E.catalog.lines[o.type] || {}).color || "#c0c0c0";

	E.registerKind("lines", {
		label: "Line",
		title: (o) => `${o.id}  ·  ${(E.catalog.lines[o.type] || {}).label || o.type}, ${Math.round(E.polyLength(o.points))} m`,
		color: lineColor,
		draw(ctx, o, selected) {
			if (!o.points || o.points.length < 2) return;
			E.path(o.points, false);
			ctx.lineCap = "round";
			ctx.lineJoin = "round";
			ctx.lineWidth = Math.max(2.5, E.view.s * 1.1) + (selected ? 3 : 0);
			ctx.strokeStyle = selected ? "#fff" : "rgba(20, 20, 15, 0.6)";
			ctx.stroke();
			ctx.lineWidth = Math.max(1.5, E.view.s * 1.1);
			ctx.strokeStyle = lineColor(o);
			if (o.gate_every > 0) ctx.setLineDash([o.gate_every * E.view.s, (o.gate || 4) * E.view.s]);
			ctx.stroke();
			ctx.setLineDash([]);
		},
		hit(o, x, z, tol) {
			let best = Infinity;
			for (let i = 1; i < o.points.length; i++) {
				const a = o.points[i - 1], b = o.points[i];
				best = Math.min(best, E.segDist(x, z, a[0], a[1], b[0], b[1]));
			}
			return best < tol ? best : false;
		},
		handles(o) {
			return o.points.map((p, i) => ({
				x: p[0], z: p[1],
				set: (x, z) => { o.points[i] = [x, z]; },
				remove: o.points.length > 2 ? () => o.points.splice(i, 1) : null,
			}));
		},
		move(o, dx, dz) { o.points = o.points.map((p) => [p[0] + dx, p[1] + dz]); },
		insertAt(o, x, z, tol) {
			for (let i = 1; i < o.points.length; i++) {
				const a = o.points[i - 1], b = o.points[i];
				if (E.segDist(x, z, a[0], a[1], b[0], b[1]) < tol) { o.points.splice(i, 0, [E.round(x), E.round(z)]); return true; }
			}
			return false;
		},
		panel(o, box) {
			const types = Object.keys(E.catalog.lines).map((k) => [k, E.catalog.lines[k].label]);
			box.append(E.field("Id", E.input(o, "id", "text", { readonly: true })));
			box.append(E.field("What", E.input(o, "type", "select", { options: types, refresh: true })));
			box.append(E.field("Length", E.el("span", {}, `${Math.round(E.polyLength(o.points))} m, ${o.points.length} corners`)));
			box.append(E.field("Gate every (m)", E.input(o, "gate_every", "number", { step: 1, min: 0, default: 0 })));
			box.append(E.field("Gate (m)", E.input(o, "gate", "number", { step: 0.5, min: 1, default: 4 })));
			box.append(E.field("Cut at roads", E.input(o, "clip", "check", { default: true })));
			box.append(E.el("p", { class: "muted" }, "Gate every 0: no gates (leave gaps by splitting the line instead). Cut at roads: where it crosses a road, water or a steep bank the bake leaves it out."));
		},
	});

	// --- points ------------------------------------------------------------------------------------

	/** Which catalog section a point's type is in. */
	const section = (type) => (E.catalog.gatherables[type] ? "gatherables" : E.catalog.props[type] ? "props" : E.catalog.fixtures[type] ? "fixtures" : null);
	const entry = (type) => (E.catalog[section(type)] || {})[type] || {};
	const pointColor = (o) => {
		const s = section(o.type);
		return s === "gatherables" ? E.gatherableColor(o.type) : s === "props" ? "#c9b48a" : s === "fixtures" ? "#b5835a" : "#ff00ff";
	};

	E.registerKind("points", {
		label: "Point",
		title: (o) => `${o.id}  ·  ${entry(o.type).label || o.type}`,
		color: pointColor,
		draw(ctx, o, selected) {
			const [sx, sy] = E.toScreen(o.at[0], o.at[1]);
			const s = section(o.type);
			const r = s === "fixtures" ? Math.max(5, (entry(o.type).radius || 4) * E.view.s) : 5;
			ctx.beginPath();
			if (s === "gatherables") ctx.arc(sx, sy, r, 0, Math.PI * 2);
			else if (s === "props") { ctx.moveTo(sx, sy - r - 1); ctx.lineTo(sx + r + 1, sy); ctx.lineTo(sx, sy + r + 1); ctx.lineTo(sx - r - 1, sy); ctx.closePath(); }
			else ctx.rect(sx - r, sy - r, r * 2, r * 2);
			ctx.fillStyle = pointColor(o);
			ctx.fill();
			ctx.lineWidth = selected ? 3 : 1.5;
			ctx.strokeStyle = selected ? "#fff" : "#14160f";
			ctx.stroke();
			// which way it faces (yaw 0 = +z, the way the game turns it)
			const a = ((o.yaw || 0) * Math.PI) / 180;
			ctx.beginPath();
			ctx.moveTo(sx, sy);
			ctx.lineTo(sx + Math.sin(a) * (r + 6), sy + Math.cos(a) * (r + 6));
			ctx.lineWidth = 1.5;
			ctx.strokeStyle = selected ? "#fff" : "rgba(20, 20, 15, 0.8)";
			ctx.stroke();
		},
		hit(o, x, z, tol) {
			const s = section(o.type);
			const r = s === "fixtures" ? Math.max(tol, entry(o.type).radius || 4) : tol;
			const d = E.dist(x, z, o.at[0], o.at[1]);
			return d < r ? d : false;
		},
		handles(o) {
			return [{ x: o.at[0], z: o.at[1], round: true, set: (x, z) => { o.at = [x, z]; } }];
		},
		move(o, dx, dz) { o.at = [o.at[0] + dx, o.at[1] + dz]; },
		panel(o, box) {
			const el = E.el;
			box.append(E.field("Id", E.input(o, "id", "text", { readonly: true })));
			const s = el("select", {});
			for (const [sec, title] of [["gatherables", "Gatherables"], ["props", "Props"], ["fixtures", "Fixtures"]]) {
				const g = el("optgroup", { label: title });
				for (const k in E.catalog[sec]) g.append(el("option", { value: k }, E.catalog[sec][k].label));
				s.append(g);
			}
			s.value = o.type;
			s.onchange = () => { E.commit(); o.type = s.value; E.changed(); };
			box.append(E.field("What", s));
			const yaw = E.input(o, "yaw", "number", { step: 15, default: 0 });
			const turn = (d) => () => { E.commit(); o.yaw = (((o.yaw || 0) + d) % 360 + 360) % 360; E.changed(); };
			box.append(E.field("Facing (°)", el("div", { class: "row" }, yaw, el("button", { onclick: turn(-45) }, "⟲ 45"), el("button", { onclick: turn(45) }, "⟳ 45"))));
			if (section(o.type) === "gatherables") {
				box.append(E.field("Save id", E.input(o, "save_id", "text", { readonly: true, default: "pt_" + o.id })));
			}
			box.append(E.field("Ground", el("span", {}, `${E.heightAt(o.at[0], o.at[1]).toFixed(1)} m up, ${Math.round(Math.atan(E.slopeAt(o.at[0], o.at[1])) * 180 / Math.PI)}° slope`)));
		},
	});

	E.points = { section, entry };
})();
