# Translating Aman Disk

Thank you for your interest in helping translate Aman Disk!

Aman Disk aims to provide an accurate, accessible, and native experience for macOS users around the world.

---

## ⚠️ Note on Translations (Review Needed)

> [!IMPORTANT]
> The reference languages of the project are **English** and **French**.
>
> All other languages (Korean, Japanese, Simplified Chinese, Traditional Chinese, German, Spanish, Brazilian Portuguese, Russian, Arabic, Italian, Turkish, Dutch, Polish, Hindi, Vietnamese, Ukrainian) were initially generated automatically.
>
> **They need review and refinement by native speakers.** If you notice unnatural phrasing, grammatical errors, or awkward terminology in your language, your contributions are very welcome!

---

## Technical Terminology & S.M.A.R.T. Attributes

Drive health and hardware monitoring involves specific technical jargon:

- **S.M.A.R.T. Attributes**: When translating attribute names (such as *Reallocated Sectors Count*, *Current Pending Sector*, *Media and Data Integrity Errors*), translate with care. If the translated term might be ambiguous or unfamiliar to system administrators, keep the technical English term in parentheses or in the technical explanation field.
- **Hardware Units**: Keep standard units and formatting standard (`°C`, `°F`, `GB`, `TB`, `MB/s`, `IOPS`, `0x...` hex values).
- **RTL (Right-to-Left)**: In Arabic (`ar`), numbers, model strings, hexadecimal values, and serial numbers remain LTR (Left-to-Right). Time charts always advance left-to-right (past to present).

---

## Where Translations Live

All localization in Aman Disk is managed in `Sources/DiskHealthCore/Localization/`:

1. **`StringKey.swift`**: Defines all typed string keys.
2. **`Translations_<LANG>.swift`**: Core UI strings for each language.
   - `Translations_EN.swift` (English reference)
   - `Translations_FR.swift` (French reference)
   - `Translations_AR.swift` (Arabic)
   - `Translations_KO_JA.swift` (Korean & Japanese)
   - `Translations_ZH.swift` (Simplified & Traditional Chinese)
   - `Translations_DE_IT_NL.swift` (German, Italian, Dutch)
   - `Translations_PT_ES.swift` (Brazilian Portuguese & Spanish)
   - `Translations_RU_UK_PL_TR.swift` (Russian, Ukrainian, Polish, Turkish)
   - `Translations_HI_VI.swift` (Hindi & Vietnamese)
3. **`ExtraTranslations_<LANG>.swift`**: Extra strings including S.M.A.R.T. explanations, ATA descriptions, and settings alerts.

---

## How to Test Your Changes

1. **Run the Automated Tests**:
   Before submitting, ensure all tests pass (including the translation completeness test):
   ```bash
   ./scripts/test.sh
   ```
   The `TranslationCompletenessTests` suite verifies that no keys are missing or empty in any supported language.

2. **Visual Check in Demo Mode**:
   Launch Aman Disk with demo drives to preview the UI in your language:
   ```bash
   DISKHEALTH_DEMO=1 swift run DiskHealthApp
   ```
   You can switch languages in Aman Disk **Settings** (⌘,) or via **System Settings › General › Language & Region › Applications**.
   Verify that text does not truncate, overflow, or break the layout.

---

## Submitting Your Contribution

1. Fork the repository on GitHub (`github.com/MidZai/aman_disk`).
2. Create a new branch for your changes:
   ```bash
   git checkout -b i18n/improve-<language-code>
   ```
3. Make your updates in the relevant `Translations_*.swift` or `ExtraTranslations_*.swift` files.
4. Run `./scripts/test.sh` to ensure tests are green.
5. Commit your changes with a descriptive message, e.g.:
   ```bash
   git commit -m "i18n: improve <language> translations for S.M.A.R.T. attributes"
   ```
6. Push to your fork and open a Pull Request.

Thank you for helping make Aman Disk better for everyone!
