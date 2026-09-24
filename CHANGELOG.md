# Changelog

## 0.9.2

- Drive page and reports: “Internal SSD” instead of “SSD internal” in English.
- Diagnostic export: hidden values are written as `<masked>`.
- The `diskprobe` command-line tool is now in English.
- About window: “© 2026 MidZai · MIT License”.
- The DMG includes **How to Install.txt**, with the steps to open the app the first time on macOS 14 and on macOS 15 or later.

## 0.9.1 — 2026-09-24

- **Turning on S.M.A.R.T.**: on a SATA drive where S.M.A.R.T. is turned off, Aman turns it on once (setting “Turn on S.M.A.R.T. automatically if it's off”, on by default), then reads the drive again. The event is added to the drive's log. If it fails, the error code is shown with a “Try Again” button; there is never an automatic retry. With the setting off, a “Turn On S.M.A.R.T.…” button asks for confirmation first.
- **Help menu**: “Check for New Versions…” opens the releases page on GitHub. The app itself never checks the network.
- GitHub issue templates.

## 0.9.0 — 2026-09-23

First public release.

- **NVMe and ATA/AHCI health**: S.M.A.R.T. data from NVMe SSDs, Apple PCIe AHCI SSDs and SATA drives; “Healthy”, “Needs attention” or “Likely failing” status, health ring, and remaining life when the drive reports it.
- **Attributes explained**, converted to their unit, or shown as raw hexadecimal on request.
- **Temperature history**: one reading every 30 s, 24 h at full resolution, then 30 days of averages; charts over 1 h, 24 h, 7 days and 30 days.
- **Performance test**, sequential and random; the test file is always deleted.
- **Continuous monitoring** and **menu bar**: status and temperature of each internal drive; the app can stay there when its window is closed.
- **Live Dock icon** that follows the health of the startup drive.
- **Alerts**: status change, prolonged overheating, remaining life below 50%, 25% or 10%.
- **Reports** in PDF, text or JSON, with the serial number masked by default; **diagnostic export** for unrecognized drives.
- **Settings**: language (English, French), menu bar, open at login, Dock, alerts, history.
- Universal binary (Apple Silicon and Intel), macOS 14 or later; no network connection.
