# Changelog

## 0.9.7 — 2026-09-25

- **Anonymized compatibility report export**: new command "Export Compatibility Report…" ("Exporter un rapport de compatibilité…") available in the Help menu, Drive menu, external drive contextual menu, and the unsupported drive view.
- **Strict privacy & anonymization**: guarantees all serial numbers are masked with `<masqué>`, completely excludes volume names, user home paths (`/Users/...`), and Mac computer names.
- **Comprehensive hardware diagnostics**: exports Aman version, macOS version, architecture, drive model and BSD name, connection type, `Protocol Characteristics`, `Device Characteristics`, parent `IOUSBHostDevice` properties (VID, PID, vendor, product, speed, bcdUSB), storage driver (`UAS` / `BOT`), `SmartAvailability`, error code if any, and raw S.M.A.R.T. attributes without serial numbers when readable.
- **No automatic network transmission (Rule 0.1-1)**: saves locally via standard `NSSavePanel` and displays a completion alert with an action button that opens the GitHub New Issue page in the browser and highlights the file in Finder so the user chooses whether and when to share.
- **GitHub issue templates**: added `.github/ISSUE_TEMPLATE/usb-compatibility.yml` and `.md` with clear fields for enclosure model, bridge chip, drive type (NVMe/SATA/HDD), Mac model, and SAT driver status.
- **Hardware compatibility page**: created `docs/COMPATIBILITY.md` with an open hardware test table, linked from `README.md` and the "Learn More" modal sheet.
- **Unit test suite**: added `CompatibilityReportTests` asserting that serial numbers, volume names, and user paths never leak into the exported JSON, and confirming round-trip decoding.

## 0.9.6 — 2026-09-25

- **S.M.A.R.T. reading via SAT SMART Driver**: detects when the user has installed the open-source third-party SAT SMART Driver (by checking for ATA S.M.A.R.T. plugin capability in `IOCFPlugInTypes` on the drive's IOKit service), and reads full ATA S.M.A.R.T. health data, attributes, temperature, and history for compatible USB SATA enclosures without requiring any specialized tool.
- **Strict safety boundaries (Rules 0.1-1 and 0.1-3)**: Aman Disk never downloads, bundles, installs, or prompts to install kernel extensions, and never urges users to reduce system security.
- **Interface & labeling**: external USB drives with active SAT translation display the "USB" connection badge with the technical interface "USB (SATA via SAT)" and a discrete header mention "Lu via le SAT SMART Driver" / "Read via SAT SMART Driver".
- **S.M.A.R.T. activation on USB drives**: if a USB drive reports S.M.A.R.T. disabled, the same single-command activation logic and user preference applies as for internal SATA drives.
- **Help sheet — Third-party driver (advanced)**: updated the "Learn More" modal sheet with a neutral section detailing what the SAT SMART Driver does, its limitations (Apple Silicon Reduced Security requirement, SATA-only restriction, boot re-plugging requirement), and a button opening the project's official GitHub page in the browser.
- **Crash resilience**: disconnecting a USB drive during a read produces an explicit error code with a "Try Again" / "Réessayer" action, with zero crashes or panics.
- **Test suite**: added `SATDriverTests` verifying plugin UUID detection, uppercase/lowercase handling, drive classification, detail labeling, ATA health parity on USB drives, and disconnect error handling.

## 0.9.5 — 2026-09-24

- **USB drive details without S.M.A.R.T.**: displays maximum useful hardware information for any USB drive, even when S.M.A.R.T. health data is not accessible through macOS.
- **Bridge chip identification**: identifies bridge controller vendors (JMicron `0x152D`, ASMedia `0x174C`, Realtek `0x0BDA`) from a local offline resource database (`Resources/usb-bridges.json`), gracefully falling back to raw hexadecimal notation (e.g. `Puce inconnue (0x1234)` / `Unknown chip (0x1234)`).
- **USB link speed & protocol**: inspects IOKit `IOUSBHostDevice` hierarchy to display link speed (e.g. `USB 3.2 Gen 2 — 10 Gb/s`, `USB 3.0 — 5 Gb/s`, `USB 2.0 — 480 Mb/s`) and transport protocol (`UAS (USB Attached SCSI)` vs `BOT (Bulk-Only Transport)`).
- **Volumes & partitions**: lists all partitions and volumes mounted on USB drives with capacity, filesystem format, and available space.
- **Calm, neutral state card**: replaced the warning card with a neutral, non-alarming card explaining that macOS does not relay S.M.A.R.T. commands across most USB enclosures and that this does not indicate a drive issue.
- **"Learn More" explanation sheet**: added an interactive modal sheet explaining bridge chips, third-party kernel drivers (SAT SMART Driver), Thunderbolt/USB4 enclosures, and how to export diagnostics to help expand hardware compatibility.
- **Dock & Menu Bar behavior**: Dock icon strictly tracks the startup boot drive; USB drives in the menu bar panel show a neutral gray `" — "` status without displaying errors or misleading percentages.
- **Complete localization**: all new USB strings, labels, and help sheets are localized across all 18 supported languages.
- **Test suite**: added `USBBridgeTests` covering bridge chip lookups, unknown chip handling, malformed/missing JSON fallbacks, link speed and protocol formatting, and simulated hardware fixtures.

## 0.9.4 — 2026-09-24

- **Thunderbolt / USB4 NVMe enclosures**: full S.M.A.R.T. reading on external NVMe SSDs in Thunderbolt 3/4/5 and USB4 (PCIe mode) enclosures (e.g. OWC Envoy Pro FX, Acasis, Trebleet, Sabrent).
- **Interface labeling**: displays "Thunderbolt / USB4 (PCIe)" in disk details, inspector, and headers for external PCIe drives.
- **Monitoring & menu bar**: external Thunderbolt NVMe drives are included in continuous sampling (`sampleNow`), temperature history, live alerts, and the menu bar panel.
- **Graceful error handling**: when S.M.A.R.T. reading fails on an external drive, reports `SmartAvailability.error(code:)` with the error code and an interactive "Try Again" / "Réessayer" button, without crashing or freezing.
- **External drives architecture**: added data models (`DriveConnection`, `SmartAvailability`) classifying internal drives (`internalNVMe`, `internalAHCI`, `internalSATA`) and external drives (`thunderboltNVMe`, `usb`, `other`).
- **Sidebar groups**: partitioned the drive list into distinct "Internal drives" and "External drives" sections (external section automatically hidden when no external drive is connected), with discrete connection badges ("USB", "Thunderbolt").
- **Hot-plug detection & safety**: robust DiskArbitration monitoring with 1-second debouncing to coalesce multi-event hot-plug bursts when plugging in external enclosures; disconnecting a selected external drive safely reverts selection to the startup boot disk without crash or stale IOKit references.
- **Safety filtering (Rule 0.1-8)**: strictly filters out disk images (`Location == "File"`), virtual interfaces (`"Virtual Interface"`), RAM disks (`"RAM Disk"` or `ram*` BSD names), network disks, and synthesized APFS containers.
- **Demo mode**: added simulated external drive states including a healthy Thunderbolt NVMe SSD (`OWC Envoy Pro FX`), a healthy USB HDD (`Seagate Backup Plus`), an unsupported USB SSD enclosure (`Crucial X8 Portable SSD`), and a USB flash thumb drive (`SanDisk Ultra Flair`).
- **Unit test suite**: added `DriveConnectionTests` and `ThunderboltNVMeTests` covering simulated `Protocol Characteristics` permutations, Samsung 980 Pro / WD Black SN850X S.M.A.R.T. logs, parity with internal drives, error mapping, and strict exclusion of virtual/DMG/RAM devices.

## 0.9.3 — 2026-09-24

- **Internationalization (i18n)**: added support for 16 new languages: Korean (`ko`), Japanese (`ja`), Simplified Chinese (`zh-Hans`), Traditional Chinese (`zh-Hant`), German (`de`), Spanish (`es`), Brazilian Portuguese (`pt-BR`), Russian (`ru`), Arabic (`ar`), Italian (`it`), Dutch (`nl`), Polish (`pl`), Turkish (`tr`), Hindi (`hi`), Vietnamese (`vi`), Ukrainian (`uk`).
- **Right-to-Left (RTL) layout**: full RTL support for Arabic, mirroring sidebars and alignments, while preserving standard LTR orientation for time-series charts, gauge rings, model names, serial numbers and hexadecimal identifiers.
- **Temperature unit**: added user preference for Celsius (°C) and Fahrenheit (°F) with system default auto-detection.
- **Language settings**: added in-app language picker and guidance for changing the language per-app in macOS System Settings.
- **Plurals & formatting**: platform-adapted pluralization for complex languages (Russian, Arabic), formatted via Foundation.
- **Translation completeness**: automated test suite verifying 100% key coverage across all supported languages (`TranslationCompletenessTests`).
- **Contributor guide**: added `docs/TRANSLATING.md` explaining terminology rules and how to review or improve translations.

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
