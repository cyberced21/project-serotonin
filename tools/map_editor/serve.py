"""The map editor's server (plans/map-editor.md): serves the page and lets it read and write the
layout and run the bakes. Local only (127.0.0.1).

    python tools/map_editor/serve.py [--port 8765] [--godot <console exe>]

then open http://127.0.0.1:8765/

  GET  /api/layout   data/layout/hearthvale.json      POST /api/layout  saves it (one shape a line)
  GET  /api/catalog  data/layout/catalog.json
  GET  /api/baked    data/layout/baked.json            POST /api/bake    bakes the layout (tools/bake_layout.gd)
  GET  /api/terrain_applied  the terrain shapes and anchors the land was last generated from
  GET  /api/terrain_report   the last terrain run's report (its warnings: a road across a pad...)
  GET  /map.png, /world.json  the land (tools/export_map.gd)  POST /api/map  redraws them
  POST /api/terrain  regenerates the terrain from the layout's terrain shapes, then redraws and rebakes
"""
import argparse
import json
import os
import subprocess
import sys
import threading
import time
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
LAYOUT = os.path.join(ROOT, "data", "layout", "hearthvale.json")
CATALOG = os.path.join(ROOT, "data", "layout", "catalog.json")
BAKED = os.path.join(ROOT, "data", "layout", "baked.json")
TERRAIN_APPLIED = os.path.join(ROOT, "data", "layout", "terrain_applied.json")  # what the land was last made from
TERRAIN_REPORT = os.path.join(HERE, "terrain_report.json")  # the last terrain run's report (its warnings)
DEFAULT_GODOT = r"E:\Godot\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
# Bakes run the game headless: never in the player's real worlds.
SAVE_ROOT = "--save-root=user://tool_worlds"

godot = DEFAULT_GODOT
busy = threading.Lock()  # one Godot run at a time


def write_layout(data):
    """One shape a line, so the file diffs well in git (as tools/import_layout.gd writes it)."""
    parts = ['{\n\t"version": %d,' % data.get("version", 1)]
    keys = ["terrain", "patches", "lines", "points", "anchors"]
    for i, key in enumerate(keys):
        rows = ["\t\t" + json.dumps(item, separators=(",", ":"), sort_keys=True) for item in data.get(key, [])]
        body = ("\n" + ",\n".join(rows) + "\n\t") if rows else ""
        parts.append('\t"%s": [%s]%s' % (key, body, "," if i < len(keys) - 1 else ""))
    parts.append("}\n")
    tmp = LAYOUT + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(parts))
    os.replace(tmp, LAYOUT)


def run_godot(script, timeout=900):
    """Runs a headless Godot script (or [script, its own args...]) and sums up what it said."""
    script, extra = (script[0], list(script[1:])) if isinstance(script, list) else (script, [])
    cmd = [godot, "--headless", "--audio-driver", "Dummy", "--path", ROOT, "-s", script, "--", SAVE_ROOT, *extra]
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

    def _file(self, path):
        if not os.path.exists(path):
            return self._json({}, 200)
        with open(path, encoding="utf-8") as f:
            body = f.read().encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/api/layout":
            return self._file(LAYOUT)
        if path == "/api/catalog":
            return self._file(CATALOG)
        if path == "/api/baked":
            return self._file(BAKED)
        if path == "/api/terrain_applied":
            return self._file(TERRAIN_APPLIED)
        if path == "/api/terrain_report":
            return self._file(TERRAIN_REPORT) if os.path.exists(TERRAIN_REPORT) else self._json({"warnings": []})
        if path.startswith("/api/"):
            return self._json({"error": "no such thing"}, 404)
        if path.endswith(".py"):
            return self._json({"error": "no"}, 404)
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
        if path == "/api/layout":
            data = self._body()
            if not isinstance(data, dict) or "patches" not in data:
                return self._json({"error": "that isn't a layout"}, 400)
            write_layout(data)
            return self._json({"ok": True})
        scripts = {"/api/bake": ["res://tools/bake_layout.gd"],
                   "/api/map": ["res://tools/export_map.gd"],
                   "/api/terrain": [["res://tools/generate_test_terrain.gd", "--report=" + TERRAIN_REPORT],
                                    "res://tools/export_map.gd", "res://tools/bake_layout.gd"]}
        if path in scripts:
            if not busy.acquire(blocking=False):
                return self._json({"ok": False, "errors": ["Godot is already running a bake"]}, 409)
            try:
                results = [run_godot(s) for s in scripts[path]]
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
