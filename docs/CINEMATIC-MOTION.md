# Public homepage cinematic motion

1 November 2026 — requested high-effect presentation, preserving Classic cream/olive, existing layout, imagery, links and bilingual content.

- Hero crossfades between existing welding, shed and tank images every 6.5 seconds with continuous camera zoom; decorative gold sparks.
- Staggered text entrance, metallic light sweep, perspective scroll reveals and pointer hover effects.
- English/Hindi pause/play control; respects system reduced motion. Autoplay stops when the tab is hidden or the hero leaves the viewport. Failed next images leave the current image visible.
- Presentation lives only in `index.html` and `assets/aaw-motion.*`. The Android WebView homepage receives this after website publication. Native splash, portal operations and signing are unchanged; no native rebuild is needed for this hosted change.

Validation: five motion lifecycle tests pass. Existing exact-decimal RA engine and release automation checks pass. Desktop cloud-browser preview visually inspected; English pause/play and Hindi label switching checked. Physical Android performance and small-viewport browser verification remain pending. Local native browser tests could not launch because the Playwright Chromium executable is unavailable; GitHub CI remains authoritative for the full suite/APK checks.

Branch only; production publication requires owner approval under the existing project workflow.
