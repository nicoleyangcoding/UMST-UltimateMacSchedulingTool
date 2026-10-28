# Privacy Policy

_Last updated: October 28, 2026_

UMST is a free, open-source app that runs entirely on your Mac. This policy explains what it does with your information. The short version: **UMST doesn't collect anything. There is no UMST server, account, analytics or tracking.**

## What UMST accesses

| What | Why | Where it stays |
| --- | --- | --- |
| Calendars on your Mac (only if you allow it) | To show your events on the desktop calendar | On your Mac. UMST only reads events for the next 14 days. |
| Apple Reminders (only if you turn it on) | To show reminders that have a due date and let you check them off | On your Mac. Checking one off marks it done in Reminders. |
| Calendar links and access tokens you paste in (Canvas, Todoist, Blackboard, etc.) | To download those calendars | Your macOS Keychain, on this Mac only. Never synced or backed up by UMST. |
| Quick-add to-dos you type | To show them on the calendar until midnight | A file in `~/Library/Application Support/UMST` readable only by your user account. |

## Who UMST talks to

UMST connects **only** to the services you add yourself (for example your school's Canvas site or Todoist), directly from your Mac over HTTPS, to download your calendar. Those requests go straight to that service; they don't pass through anyone else. Each service's own privacy policy applies to what it receives.

UMST does not send your data to the developer or to any third party, and contains no ads, analytics, crash reporting or tracking.

The installer downloads the app from GitHub, whose [privacy statement](https://docs.github.com/site-policy/privacy-policies/github-general-privacy-statement) covers that download. The project website is hosted on GitHub Pages, uses no cookies or analytics, and loads no third-party fonts or scripts.

## Your control

- Remove any connected service in **Settings → Accounts**; its link or token is deleted from your Keychain.
- Turn off calendar or reminders access any time in **System Settings → Privacy & Security**.
- The uninstaller in the README removes the app and everything it stored.

## Your responsibility

Calendar links and access tokens are private keys to your data. Only connect accounts you own, and follow your school's or employer's rules about third-party apps and access tokens.

## Children

UMST collects no personal information from anyone, including children under 13.

## Changes

Changes to this policy are published in this file, and its history is visible on GitHub.

## Contact

Open an issue at <https://github.com/nicoleyangcoding/UMST-UltimateMacSchedulingTool/issues>, or report security problems privately as described in [SECURITY.md](SECURITY.md).
