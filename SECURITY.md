# Security

## What UMST stores and where

| Data | Location | Protection |
| --- | --- | --- |
| Calendar feed links, Canvas tokens | Your login Keychain, service `com.umst.app.sources` | Marked device-only and never synced; never written to disk in plain text |
| Feed names and hosts, quick-add items, event cache | `~/Library/Application Support/UMST/calendar` | Directory `0700`, files `0600` |
| Preferences (theme, animations) | `UserDefaults` (`com.umst.app`) | Not sensitive |

Removing a feed in Settings deletes its Keychain item.

## Network

- Only `https://` URLs are accepted (`webcal://` is upgraded to `https://`). URLs with embedded credentials are rejected.
- Requests use an ephemeral `URLSession` with no cookie store, cache or credential storage, a 20 second timeout and a 15 MB response limit.
- App Transport Security is left at its defaults.

## Permissions

- **Calendars**: read-only access to events for the next 14 days.
- **Reminders** (only if you turn it on): reads incomplete reminders with a due date; the only change UMST ever makes is marking a reminder done when you check it off.

UMST asks for no other permissions.

## Reporting

Please report vulnerabilities privately through GitHub's **Report a vulnerability** on the repository's Security tab rather than in a public issue.
