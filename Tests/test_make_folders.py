"""Checks the Desktop launcher builder against hostile links.json content, in a throwaway HOME."""
import json, os, shutil, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

home = tempfile.mkdtemp(prefix="umst-test-")
tools = os.path.join(home, "tools")
data = os.path.join(home, "Library/Application Support/UMST")
os.makedirs(tools)
os.makedirs(data)
os.makedirs(os.path.join(home, "Desktop"))
shutil.copy(os.path.join(ROOT, "Tools/make_folders.py"), tools)
stub = os.path.join(tools, "make_icons")
with open(stub, "w") as f:
    f.write("#!/bin/sh\nexit 0\n")
os.chmod(stub, 0o755)

links = [
    {"group": "../../escape", "items": [{"name": "../../../pwned", "url": "https://example.com"}]},
    {"group": "Work", "items": [
        {"name": "Fine", "url": "https://example.com/a"},
        {"name": "Local file", "url": "file:///etc/passwd"},
        {"name": "Script", "url": "javascript:alert(1)"},
        {"name": "Bad app", "app": "../../bin/sh"},
        {"name": "Quote's \"test\"", "url": "https://example.com/?q=a'b\"c"},
    ]},
]
json.dump(links, open(os.path.join(data, "links.json"), "w"))

env = dict(os.environ, HOME=home)
r = subprocess.run([sys.executable, os.path.join(tools, "make_folders.py")], env=env, capture_output=True, text=True)

failures = []
def check(cond, name):
    if not cond:
        failures.append(name)
        print("FAIL", name)

check(r.returncode == 0, f"builder exits cleanly ({r.stderr.strip()[-200:]})")
outside = [p for p in os.listdir(home) if p not in ("Desktop", "Library", "tools")]
check(not outside, f"nothing written outside Desktop: {outside}")
work = os.path.join(home, "Desktop/Work")
built = sorted(os.listdir(work)) if os.path.isdir(work) else []
check("Fine.app" in built, "normal link gets a launcher")
check(not any(n.startswith(("Local file", "Script", "Bad app")) for n in built), f"unsafe links skipped: {built}")
check(any(n.startswith("Quote") for n in built), "quotes in names handled")
check(all(os.path.dirname(os.path.realpath(os.path.join(home, "Desktop", d))) == os.path.realpath(os.path.join(home, "Desktop"))
          for d in os.listdir(os.path.join(home, "Desktop"))), "group folders stay on the Desktop")

shutil.rmtree(home)
print(f"make_folders: {'ok' if not failures else f'{len(failures)} failed'}")
sys.exit(1 if failures else 0)
