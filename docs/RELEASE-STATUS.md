# Current AAW release status — 28 October 2026

This is the current completion checkpoint. Older audit documents describe findings at their original date/stage and are not a current task list.

## Completed and deployed

- Approved Classic cream/olive design, existing AAW logo and matching public website/portal/Android branding.
- Public GST details, large full company wordmark, complete hero caption and six HD illustrative gallery images.
- Role-isolated Master/Incharge sessions and guarded site operations: attendance/OT, effective monthly/30 salary rates, advances/partial payments, Food allocation/finalization, worker transfers, per-incharge cash, billing and Master financial reports.
- Hindi/English controls across active tools; entered names, notes and invoice content are preserved.
- Android 1.4, versionCode 5: system import, exact CSV export, system PDF printing, keyboard/back handling and approved startup logo/insets.
- First permanent owner-signed APK and AAB delivered privately with checksums, matching permanent certificate and no private key inside the install package. The separate private owner signing backup has the four future-build secret files.
- Updated Master and Incharge PDF guides delivered privately.
- Public company FAQ/enquiry draft and Master guided read commands remain available. They are not a fully connected generative AI assistant.

## Verified release evidence

PR #6 merged at `feb2c1d9998d1e0fec2fb8c8935a46f1c3a19350`.
The pre-merge run [40564171580](https://github.com/arifagroworks/arif-agro-works-website/actions/runs/40564171580) passed 133 isolated regressions, four Android 15 system tests and saved-PDF text verification. The main-branch run [40564935742](https://github.com/arifagroworks/arif-agro-works-website/actions/runs/40564935742) and [Pages deployment](https://github.com/arifagroworks/arif-agro-works-website/actions/runs/40564915928) also passed. Seven deployed website/portal files matched the tested source byte-for-byte.

Release-closeout adds automated owner-build configuration checks and version/signer compatibility guards. Their current result is recorded by the closeout PR checks; the ten new isolated release tests passed locally.

## Owner release setup completed

The owner configured all four signing secrets. [Android Release run 40642513179](https://github.com/arifagroworks/arif-agro-works-website/actions/runs/40642513179) passed and [Android 1.4](https://github.com/arifagroworks/arif-agro-works-website/releases/tag/android-v1.4) is published. The owner confirmed installation and operation on 28 October. Future version bumps still use the permanent key and compatibility guards.

Remaining owner Auth setting: Supabase leaked-password protection remains an owner Auth/plan setting; the connector cannot update Auth configuration. No paid upgrade was performed. See [owner setup](OWNER-RELEASE-SETUP.md).

No production business records were inserted, changed, deleted or reset during this closeout. The site export tool remains read-only; destructive bulk deletion stays locked by design.

## Explicitly postponed

The owner postponed full generative AI and voice on 28 October 2026. The owner subsequently requested a specific RA bill upload → reviewed GST invoice feature; that scoped document-import work is now authorized separately. Do not activate provider billing, add an API key, or implement that next stage until the owner resumes it. Existing FAQ/guided tools stay available.

## Billing workspace improvement

Cream/olive responsive workspace: mobile Details / Items-or-Letter / Preview-and-Payments tabs, item cards, fixed Save/Preview bar; desktop editor and printable document side-by-side. Saved-document search/type filter covers the latest 200 loaded records. Legacy backup/restore remains under More tools.

Letterhead tools include undo/redo, fonts, sizes, headings, colour/highlight, lists, alignment, indentation, line spacing, safe paste, text tables and row/column controls. Formulas are not evaluated. An allowlist preserves safe formatting when saved/reopened and strips active HTML/unsafe CSS. Existing document storage/schema, payment guards and audit history stay in place. Unsaved-change warning does not claim offline autosave.

Isolated browser tests cover real input retention, mobile/desktop layout, letter table editing, sanitization, save failure, search, print/PDF and payment-balance guards. No customer example bills or signatures are committed as fixtures, and no production business records are changed by these tests.

## RA import upgrade

Master Billing Studio now includes browser-local RA PDF/photo/text import, reviewed work rows, exact paise arithmetic, IGST or separately rounded CGST/SGST, additional GST invoice particulars, and current-draft verification before saving/printing. Imported current-period quantities cannot deduct previous certified work twice. Source amount mismatches above ₹1 block preparation; smaller rounding differences require review. OCR readings remain subject to the owner's source check.

Read [RA invoice import](RA-INVOICE-IMPORT.md) for supported layouts, privacy, limits and the workflow. The uploaded real examples were used only in local reading verification; no example business invoice was saved and no customer source images/signatures were committed. The tax-head function migration is applied and verified on the existing backend; legacy calculations and business rows remain unchanged. Local full regression suite passed 160 tests, plus real image-OCR and synthetic PDF.js reading checks outside production.
