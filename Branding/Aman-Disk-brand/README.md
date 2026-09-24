# Aman Disk — brand kit

## Colors
- Ink (icon background): #0B2230
- Water (gauge): #2E9FD6
- Text gray on light: #55646E · on dark: #9AA8B2
- Alerts (live icon): orange #E8A33D · red #E5534B

Logo typeface: Jost (SemiBold for “aman”, Regular for “disk”), OFL license.
In the logo SVGs the text is converted to outlines: no font to install.

## Folders
- app-icon/: AppIcon.appiconset (drag into Assets.xcassets in Xcode), AppIcon.icns, SVG and 1024 px PNG on Apple's grid
- icon-composer-layers/: 3 separate layers (1024 px) for Icon Composer; set #0B2230 as the background color
- menu-bar/: black “template” icon for the menu bar (macOS inverts it by itself in dark mode)
- logo/: full logo, light-background and dark-background versions (SVG + PNG @2x)
- web/: favicon, website icons, square avatar for GitHub and Ko-fi

The gauge is fixed at 80% in all of these files.

## Health states (health-states/)
One icon per 5% step, from 100% down to 5% (files aman-100 … aman-005).
- 60 to 100%: blue #2E9FD6 (good)
- 30 to 55%: orange #E8A33D (caution)
- 5 to 25%: red #E5534B (critical)

For a value in between, round down to the nearest 5% step.
Menu bar versions (black template) exist for every step.
