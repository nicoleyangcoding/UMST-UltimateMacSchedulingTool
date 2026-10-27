# UMST — Ultimate Mac Scheduling Tool

A lightweight macOS menu bar app that puts your schedule and your most-used links one click away.

- **Desktop calendar.** A glass calendar widget that lives on your desktop, below your windows. It shows the next two weeks from every calendar you connect and stays visible when you use Show Desktop.
- **Quick add.** Click the calendar icon in the menu bar, type, press Return. Items land on today by default and clear themselves at midnight; pick another day with one click.
- **Quick Links.** A compact menu of the sites and apps you use most, grouped into Personal, School and Work, each opening in the right Chrome profile.
- **Show Desktop.** One click hides every app, a second click brings everything back exactly as it was.
- **Themes and animations.** Six themes (Glass, Midnight, Sunset, Forest, Lavender, Graphite) and smooth transitions that can be turned off in Settings.

## Requirements

- macOS 14 Sonoma or later
- Xcode Command Line Tools (`xcode-select --install`)
- Google Chrome (for Quick Links)

## Install

```sh
git clone https://github.com/nicoleyangcoding/UMST-UltimateMacSchedulingTool.git
cd UMST-UltimateMacSchedulingTool
./scripts/install.sh
```

This builds `UMST.app`, copies it to `~/Applications`, adds it as a login item and starts it. On first launch macOS asks for calendar access, and the first time you use Show Desktop it asks to let UMST control System Events.

## Connecting calendars

Open **Settings → Accounts** from the calendar's `•••` menu or the Quick Links menu.

| Source | How |
| --- | --- |
| Google / Gmail, iCloud, Exchange | Add the account in **System Settings → Internet Accounts** and turn on Calendars. UMST reads it through macOS Calendar, so meeting invites and events Mail finds show up automatically. Individual calendars can be hidden in Settings. |
| Canvas | Canvas → Calendar → **Calendar Feed**, paste the link under **Add Feed**. Or use a Canvas access token for the planner API. |
| Anything else | Any `https://` or `webcal://` iCalendar link (Google's secret iCal address, Outlook, school portals). |

Calendars refresh at login, at midnight, when the Mac wakes, whenever macOS Calendar changes, and on demand with the refresh button.

## Quick Links

Links are read from `~/Library/Application Support/UMST/links.json` (see `config/links.example.json`). Each item has a `name` and either a `url` plus Chrome `profile` (`Default`, `Profile 1`, …) or an `app` name from `/Applications`.

Use **Add Link…** in the menu to add a site without editing the file. Plain names are saved to `requests.json` as pending requests.

Desktop folders with one-click launchers for every link can be generated with:

```sh
python3 ~/Applications/UMST.app/Contents/Resources/make_folders.py
```

## Security

- Feed links and API tokens are stored in the macOS Keychain (this device only), never in plain files.
- All network requests are HTTPS-only, use an ephemeral session (no cookies or cache on disk) and are size-limited.
- Data files in `~/Library/Application Support/UMST` are readable only by your user account.
- The app is built with the hardened runtime and only the calendar and Apple Events entitlements.
- UMST has no analytics and talks to nothing except the calendars and sites you add.

See [SECURITY.md](SECURITY.md) for details and how to report a problem.

## Project layout

```
Sources/UMST/      App source (AppKit + SwiftUI)
Tools/             Icon and Desktop-launcher generators bundled into the app
Resources/         Info.plist and entitlements
config/            Example configuration
scripts/           build.sh and install.sh
```
