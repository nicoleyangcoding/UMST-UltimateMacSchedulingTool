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

def app_icon(name):
    res = f"/Applications/{name}.app/Contents/Resources"
    icns = [f for f in os.listdir(res) if f.endswith(".icns")] if os.path.isdir(res) else []
    return os.path.join(res, "electron.icns" if "electron.icns" in icns else icns[0]) if icns else CHROME_ICON

subprocess.run([os.path.join(HERE, "make_icons")], check=True)  # refresh tiles/*.icns

for group in json.load(open(os.path.join(DATA, "links.json"))):
    folder = os.path.join(DESKTOP, group["group"])
    os.makedirs(folder, exist_ok=True)
    for old in os.listdir(folder):  # launchers are regenerated from scratch
        if old.endswith(".app"):
            shutil.rmtree(os.path.join(folder, old))
    names = [i["name"] for i in group["items"]]
    for item in group["items"]:
        label = item["name"]
        if names.count(label) > 1:  # e.g. two Gmails -> "Gmail (alex)"
            label += f" ({item['account'].split('@')[0]})"
        app = os.path.join(folder, label + ".app")
        if "app" in item:
            cmd = f"open -a {q(item['app'])}"
            icon = app_icon(item["app"])
        else:
            cmd = f"open -na 'Google Chrome' --args --profile-directory={q(item['profile'])} {q(item['url'])}"
            tile = os.path.join(TILES, urlparse(item["url"]).hostname + ".icns")
            icon = tile if os.path.exists(tile) else CHROME_ICON
        script = f'do shell script "{cmd.replace(chr(92), chr(92)*2).replace(chr(34), chr(92)+chr(34))}"'
        subprocess.run(["osacompile", "-o", app, "-e", script], check=True, capture_output=True)
        shutil.copy(icon, os.path.join(app, "Contents/Resources/applet.icns"))
        subprocess.run(["codesign", "--force", "-s", "-", app], capture_output=True)
        subprocess.run(["touch", app])
    print("built", folder)

subprocess.run([os.path.join(HERE, "make_icons")], check=True, capture_output=True)  # folder icons need the folders to exist
