"""The map editor's server (plans/map-editor.md): serves the page and lets it read and write the
layout and run the bakes. Local only (127.0.0.1).

    python tools/map_editor/serve.py [--port 8765] [--godot <console exe>]

then open http://127.0.0.1:8765/

  GET  /api/layout   the map's layout                POST /api/layout  saves it (one shape a line)
  GET  /api/catalog  data/layout/catalog.json
  GET  /api/baked    the map's baked.json            POST /api/bake    bakes the layout (tools/bake_layout.gd)
  GET  /api/terrain_applied  the terrain shapes and anchors the land was last generated from
  GET  /api/terrain_report   the last terrain run's report (its warnings: a road across a pad...)
  GET  /map.png, /world.json  the land (tools/export_map.gd)  POST /api/map  redraws them
  POST /api/terrain  regenerates the terrain from the layout's terrain shapes, then redraws and rebakes
Every one of those takes ?map=<id> (plans/map-maker.md: data/maps.json); without it, Hearthvale.
  GET  /api/maps       the maps, and which one the game plays
  POST /api/maps/new   {name, width, depth}: a blank map (its id made from the name)
  POST /api/maps/play  {id}: the game plays that map from now on
"""
import argparse
import json
import os
import re
import subprocess
import sys
import threading
import time
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
CATALOG = os.path.join(ROOT, "data", "layout", "catalog.json")
REGISTRY = os.path.join(ROOT, "data", "maps.json")
DEFAULT_MAP = "hearthvale"
TILE = 256  # the land's tiles (Terrain3D regions, m): a map is a whole number of them each way
MAX_SIZE = 2048
DEFAULT_GODOT = r"E:\Godot\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
# Bakes run the game headless: never in the player's real worlds.
SAVE_ROOT = "--save-root=user://tool_worlds"

godot = DEFAULT_GODOT
busy = threading.Lock()  # one Godot run at a time


def map_path(what, map_id=DEFAULT_MAP):
    """Map `map_id`'s file `what`, as scripts/maps.gd has it (Hearthvale's where they always were)."""
    if map_id == DEFAULT_MAP:
        return {"layout": os.path.join(ROOT, "data", "layout", "hearthvale.json"),
                "baked": os.path.join(ROOT, "data", "layout", "baked.json"),
                "applied": os.path.join(ROOT, "data", "layout", "terrain_applied.json"),  # what the land was last made from
                "terrain": os.path.join(ROOT, "terrain_data"),
                "editor": HERE}[what]
    d = os.path.join(ROOT, "data", "maps", map_id)
    return {"layout": os.path.join(d, "layout.json"), "baked": os.path.join(d, "baked.json"),
            "applied": os.path.join(d, "terrain_applied.json"), "terrain": os.path.join(d, "terrain"),
            "editor": os.path.join(HERE, "maps", map_id)}[what]


def report_path(map_id):
    """The map's last terrain run's report (its warnings)."""
    return os.path.join(map_path("editor", map_id), "terrain_report.json")


def read_registry():
    if os.path.exists(REGISTRY):
        with open(REGISTRY, encoding="utf-8") as f:
            return json.load(f)
    return {"active": DEFAULT_MAP, "maps": [{"id": DEFAULT_MAP, "name": "Hearthvale"}]}


def write_registry(reg):
    with open(REGISTRY, "w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(reg, indent="\t") + "\n")


def map_size(map_id):
    """A map's [width, depth] and [origin x, z] (m). Hearthvale's from before maps had one: 768 from -256."""
    try:
        with open(map_path("layout", map_id), encoding="utf-8") as f:
            w = json.load(f).get("world", {})
    except (OSError, ValueError):
        w = {}
    return w.get("size", [768, 768]), w.get("origin", [-256, -256])


def write_layout(data, path):
    """One shape a line, so the file diffs well in git (as tools/import_layout.gd writes it)."""
    parts = ['{\n\t"version": %d,' % data.get("version", 1)]
    if "world" in data:  # (the map's size and where it starts: plans/map-maker.md)
        parts.append('\t"world": %s,' % json.dumps(data["world"], separators=(",", ":"), sort_keys=True))
    keys = [k for k in ["areas", "labels"] if k in data] + ["terrain", "patches", "lines", "points", "anchors"]
    for i, key in enumerate(keys):
        rows = ["\t\t" + json.dumps(item, separators=(",", ":"), sort_keys=True) for item in data.get(key, [])]
        body = ("\n" + ",\n".join(rows) + "\n\t") if rows else ""
        parts.append('\t"%s": [%s]%s' % (key, body, "," if i < len(keys) - 1 else ""))
    parts.append("}\n")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(parts))
    os.replace(tmp, path)


def new_map(name, width, depth):
    """A blank map: no areas, shapes, nodes or roads yet, and every building and place there is (as
    Hearthvale has them) still to put down (`placed: false`: the game keeps them out till they are).
    Returns its id."""
    map_id = re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")[:32] or "map"
    reg = read_registry()
    taken = {m["id"] for m in reg["maps"]}
    base, n = map_id, 2
    while map_id in taken:
        map_id, n = "%s_%d" % (base, n), n + 1
    with open(map_path("layout"), encoding="utf-8") as f:
        anchors = [{**a, "at": [width / 2, depth / 2], "yaw": 0.0, "placed": False} for a in json.load(f).get("anchors", [])]
    layout = {"version": 1, "world": {"size": [width, depth], "origin": [0, 0]},
              "areas": [], "labels": [], "terrain": [], "patches": [], "lines": [], "points": [], "anchors": anchors}
    write_layout(layout, map_path("layout", map_id))
    reg["maps"].append({"id": map_id, "name": name})
    write_registry(reg)
    return map_id


def run_godot(script, map_id=DEFAULT_MAP, timeout=1800):
    """Runs a headless Godot script (or [script, its own args...]) on a map and sums up what it said."""
    script, extra = (script[0], list(script[1:])) if isinstance(script, list) else (script, [])
    cmd = [godot, "--headless", "--audio-driver", "Dummy", "--path", ROOT, "-s", script, "--", SAVE_ROOT,
           "--map=" + map_id, *extra]
    started = time.time()
    p = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=timeout)
    out = p.stdout + p.stderr
    errors = [l for l in out.splitlines() if "SCRIPT ERROR" in l or l.startswith("ERROR: Failed")]
    return {"ok": p.returncode == 0 and not errors, "seconds": round(time.time() - started, 1),
            "log": "\n".join(l for l in out.splitlines() if l.startswith(("layout:", "map:", "  !", "SCRIPT ERROR", "terrain", "Preview"))),
            "errors": errors}


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=HERE, **kw)

    def log_message(self, fmt, *args):
        if "/api/" in (args[0] if args else ""):
            sys.stderr.write("%s\n" % (fmt % args))

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def _json(self, obj, code=200):
        body = json.dumps(obj).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _file(self, path, kind="application/json"):
        if not os.path.exists(path):
            return self._json({}, 200) if kind == "application/json" else self._json({"error": "not made yet"}, 404)
        with open(path, "rb") as f:
            body = f.read()
        self.send_response(200)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _map(self):
        """The map this request is about (?map=<id>, one the registry has), else Hearthvale."""
        query = self.path.split("?", 1)[1] if "?" in self.path else ""
        for part in query.split("&"):
            if part.startswith("map=") and part[4:] in {m["id"] for m in read_registry()["maps"]}:
                return part[4:]
        return DEFAULT_MAP

    def _maps(self):
        reg = read_registry()
        out = []
        for m in reg["maps"]:
            size, origin = map_size(m["id"])
            out.append({**m, "size": size, "origin": origin, "made": os.path.isdir(map_path("terrain", m["id"]))})
        return {"active": reg.get("active", DEFAULT_MAP), "maps": out}

    def do_GET(self):
        path = self.path.split("?")[0]
        m = self._map()
        if path == "/api/maps":
            return self._json(self._maps())
        if path == "/api/layout":
            return self._file(map_path("layout", m))
        if path == "/api/catalog":
            return self._file(CATALOG)
        if path == "/api/baked":
            return self._file(map_path("baked", m))
        if path == "/api/terrain_applied":
            return self._file(map_path("applied", m))
        if path == "/api/terrain_report":
            rep = report_path(m)
            return self._file(rep) if os.path.exists(rep) else self._json({"warnings": []})
        if path.startswith("/api/"):
            return self._json({"error": "no such thing"}, 404)
        if path.endswith(".py"):
            return self._json({"error": "no"}, 404)
        if path in ("/map.png", "/world.json") and m != DEFAULT_MAP:  # (another map's pictures)
            return self._file(os.path.join(map_path("editor", m), path[1:]), "image/png" if path.endswith(".png") else "application/json")
        return super().do_GET()

    def _body(self):
        n = int(self.headers.get("Content-Length", "0"))
        return json.loads(self.rfile.read(n).decode("utf-8")) if n else {}

    def do_POST(self):
        # (the page is served from here: refuse anything posted from another site)
        origin = self.headers.get("Origin", "")
        if origin and not origin.startswith(("http://127.0.0.1", "http://localhost")):
            return self._json({"error": "forbidden"}, 403)
        path = self.path.split("?")[0]
        m = self._map()
        if path == "/api/maps/new":
            data = self._body()
            name = str(data.get("name", "")).strip()[:60]
            try:
                width, depth = int(data.get("width", 0)), int(data.get("depth", 0))
            except (TypeError, ValueError):
                width = depth = 0
            if not name:
                return self._json({"error": "give it a name"}, 400)
            if any(v < TILE or v > MAX_SIZE or v % TILE for v in (width, depth)):
                return self._json({"error": "width and depth: %d to %d m, in steps of %d" % (TILE, MAX_SIZE, TILE)}, 400)
            return self._json({"ok": True, "id": new_map(name, width, depth)})
        if path == "/api/maps/play":
            data = self._body()
            reg = read_registry()
            if data.get("id") not in {x["id"] for x in reg["maps"]}:
                return self._json({"error": "no such map"}, 400)
            reg["active"] = data["id"]
            write_registry(reg)
            return self._json({"ok": True})
        if path == "/api/layout":
            data = self._body()
            if not isinstance(data, dict) or "patches" not in data:
                return self._json({"error": "that isn't a layout"}, 400)
            write_layout(data, map_path("layout", m))
            return self._json({"ok": True})
        scripts = {"/api/bake": ["res://tools/bake_layout.gd"],
                   "/api/map": ["res://tools/export_map.gd"],
                   "/api/terrain": [["res://tools/generate_test_terrain.gd", "--report=" + report_path(m)],
                                    "res://tools/export_map.gd", "res://tools/bake_layout.gd"]}
        if path in scripts:
            if not busy.acquire(blocking=False):
                return self._json({"ok": False, "errors": ["Godot is already running a bake"]}, 409)
            try:
                os.makedirs(map_path("editor", m), exist_ok=True)
                results = [run_godot(s, m) for s in scripts[path]]
            finally:
                busy.release()
            return self._json({"ok": all(r["ok"] for r in results), "seconds": sum(r["seconds"] for r in results),
                               "log": "\n".join(r["log"] for r in results),
                               "errors": [e for r in results for e in r["errors"]]})
        return self._json({"error": "no such thing"}, 404)


def main():
    global godot
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--godot", default=os.environ.get("GODOT", DEFAULT_GODOT))
    args = ap.parse_args()
    godot = args.godot
    if not os.path.exists(godot):
        print("Godot not found at %s: pass --godot <console exe>. (Editing still works; baking won't.)" % godot)
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print("Map editor: http://127.0.0.1:%d/" % args.port)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
