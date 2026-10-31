"""Runs the headless tests (tools/test_*.gd) and times them.

    python tools/run_tests.py                  every test, four at once (~3 min; each has its own save folder)
    python tools/run_tests.py day dog lamps    just these (with or without the test_ prefix)
    python tools/run_tests.py --jobs 1         one at a time
    python tools/run_tests.py --real-time      paced by the clock, as the game plays

By default the game runs on a fixed step (--fixed-fps 60: every frame is 1/60 s of game time,
however long it really takes), so a test runs as fast as the machine can go instead of waiting on
the clock (test_dog 192 s -> 66 s), and the same way every run. Audio is the Dummy driver.

Each test gets its own throwaway save root (user://test_run/<name>; test_worlds keeps the one it
asks for), so none touches your real worlds. Prints each test's result and wall time as it ends,
then a table slowest first, and exits 1 if any failed. The slowest start first (each test's last
time is kept in user data's test_run/timings.json). Full output of a failed test is kept in
user data's test_run/<name>.log next to its save folder.
"""
import argparse
import concurrent.futures
import glob
import json
import os
import re
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = os.environ.get("GODOT", r"E:\Godot\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe")
USER_DATA = os.path.join(os.environ.get("APPDATA", ""), "Godot", "app_userdata", "Project serotonin")
SAVE_ROOT = {"test_worlds": "user://test_worlds"}
TIMEOUT = 900
TIMINGS = os.path.join(USER_DATA, "test_run", "timings.json")
RESULT = re.compile(r"^(test_\w+): (.*)$|all passed|\d+ FAILED")


REAL_TIME = False


def run(name: str) -> tuple[str, float, bool, str]:
    root = SAVE_ROOT.get(name, f"user://test_run/{name}")
    pace = [] if REAL_TIME else ["--fixed-fps", "60", "--audio-driver", "Dummy"]
    cmd = [GODOT, "--headless", *pace, "--path", ROOT, "-s", f"res://tools/{name}.gd", "--", f"--save-root={root}"]
    start = time.monotonic()
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=TIMEOUT)
        out, code = p.stdout + p.stderr, p.returncode
    except subprocess.TimeoutExpired as e:
        out, code = (e.stdout or b"").decode("utf-8", "replace") if isinstance(e.stdout, bytes) else (e.stdout or ""), -1
        out += f"\n(timed out after {TIMEOUT} s)"
    took = time.monotonic() - start
    lines = [l for l in out.splitlines() if RESULT.search(l)]
    summary = lines[-1].strip() if lines else ("timed out" if code == -1 else f"no result line (exit {code})")
    ok = code == 0 and "FAIL" not in summary and "ERROR" not in summary
    fails = [l.strip() for l in out.splitlines() if l.strip().startswith("FAIL") or "SCRIPT ERROR" in l]
    if not ok:
        log = os.path.join(USER_DATA, "test_run", f"{name}.log")
        os.makedirs(os.path.dirname(log), exist_ok=True)
        with open(log, "w", encoding="utf-8") as f:
            f.write(out)
    return name, took, ok, summary + ("".join("\n      " + l for l in fails[:5]) if not ok else "")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("tests", nargs="*", help="test names (default: all)")
    ap.add_argument("--jobs", type=int, default=4, help="tests to run at once (default 4)")
    ap.add_argument("--real-time", action="store_true", help="pace the game by the clock (no --fixed-fps)")
    args = ap.parse_args()
    global REAL_TIME
    REAL_TIME = args.real_time
    every = sorted(os.path.basename(p)[:-3] for p in glob.glob(os.path.join(ROOT, "tools", "test_*.gd")))
    names = [t if t.startswith("test_") else "test_" + t for t in args.tests] or every
    unknown = [n for n in names if n not in every]
    if unknown:
        print("no such test: " + ", ".join(unknown))
        return 2
    last = {}  # each test's time last run: the slowest start first, so the long ones don't finish alone
    try:
        with open(TIMINGS, encoding="utf-8") as f:
            last = json.load(f)
    except (OSError, ValueError):
        pass
    names.sort(key=lambda n: -float(last.get(n, 0.0)))
    results = []
    start = time.monotonic()
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
        for name, took, ok, summary in pool.map(run, names) if args.jobs == 1 else \
                (f.result() for f in concurrent.futures.as_completed([pool.submit(run, n) for n in names])):
            print(f"{'ok  ' if ok else 'FAIL'} {name:<22} {took:6.1f} s  {summary}", flush=True)
            results.append((name, took, ok))
    total = time.monotonic() - start
    if not REAL_TIME:
        last.update({name: round(took, 1) for name, took, _ok in results})
        os.makedirs(os.path.dirname(TIMINGS), exist_ok=True)
        with open(TIMINGS, "w", encoding="utf-8") as f:
            json.dump(last, f, indent=1, sort_keys=True)
    print("\nslowest first:")
    for name, took, ok in sorted(results, key=lambda r: -r[1]):
        print(f"  {name:<22} {took:6.1f} s{'' if ok else '  FAILED'}")
    failed = [r for r in results if not r[2]]
    print(f"\n{len(results) - len(failed)} passed, {len(failed)} failed, {sum(r[1] for r in results):.0f} s of tests in {total:.0f} s")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
