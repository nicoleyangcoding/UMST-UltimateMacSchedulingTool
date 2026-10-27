#!/usr/bin/env python3
"""Builds ~/Desktop/<Group>/<Link>.app launchers from links.json. Re-run after editing links.json."""
import json, os, shutil, subprocess
from urllib.parse import urlparse

HERE = os.path.dirname(os.path.abspath(__file__))  # bundled tools live next to this script
DATA = os.path.expanduser("~/Library/Application Support/UMST")
DESKTOP = os.path.expanduser("~/Desktop")
TILES = os.path.join(DATA, "tiles")
CHROME_ICON = "/Applications/Google Chrome.app/Contents/Resources/app.icns"

def q(s):  # quote for a shell string inside an AppleScript string
    return "'" + s.replace("'", "'\\''") + "'"

def safe_name(s):
    """File-name-safe label: no path separators, no leading dots, bounded length."""
    s = s.replace("/", "-").replace(":", "-").strip().lstrip(".")
    return s[:60] or "Link"

def web_url(u):
    p = urlparse(u or "")
    return p.scheme in ("http", "https") and bool(p.hostname)

def app_icon(name):
    res = f"/Applications/{name}.app/Contents/Resources"
    icns = [f for f in os.listdir(res) if f.endswith(".icns")] if os.path.isdir(res) else []
    return os.path.join(res, "electron.icns" if "electron.icns" in icns else icns[0]) if icns else CHROME_ICON

subprocess.run([os.path.join(HERE, "make_icons")], check=True)  # refresh tiles/*.icns

for group in json.load(open(os.path.join(DATA, "links.json"))):
    folder = os.path.join(DESKTOP, safe_name(group["group"]))
    os.makedirs(folder, exist_ok=True)
    for old in os.listdir(folder):  # launchers are regenerated from scratch
        if old.endswith(".app"):
            shutil.rmtree(os.path.join(folder, old))
    names = [i["name"] for i in group["items"]]
    for item in group["items"]:
        label = safe_name(item["name"])
        if names.count(label) > 1:  # e.g. two Gmails -> "Gmail (alex)"
            label += f" ({safe_name(item.get('account', '').split('@')[0])})"
        app = os.path.join(folder, label + ".app")
        if "app" in item:
            if "/" in item["app"] or ".." in item["app"]:
                continue
            cmd = f"open -a {q(item['app'])}"
            icon = app_icon(item["app"])
        elif not web_url(item.get("url")):
            continue
        elif item.get("profile") and os.path.exists("/Applications/Google Chrome.app"):
            cmd = f"open -na 'Google Chrome' --args --profile-directory={q(item['profile'])} {q(item['url'])}"
        else:
            cmd = f"open {q(item['url'])}"  # default browser
        if "url" in item:
            tile = os.path.join(TILES, urlparse(item["url"]).hostname + ".icns")
            icon = tile if os.path.exists(tile) else CHROME_ICON
        script = f'do shell script "{cmd.replace(chr(92), chr(92)*2).replace(chr(34), chr(92)+chr(34))}"'
        subprocess.run(["osacompile", "-o", app, "-e", script], check=True, capture_output=True)
        if os.path.exists(icon):
            shutil.copy(icon, os.path.join(app, "Contents/Resources/applet.icns"))
        subprocess.run(["codesign", "--force", "-s", "-", app], capture_output=True)
        subprocess.run(["touch", app])
    print("built", folder)

subprocess.run([os.path.join(HERE, "make_icons")], check=True, capture_output=True)  # folder icons need the folders to exist
