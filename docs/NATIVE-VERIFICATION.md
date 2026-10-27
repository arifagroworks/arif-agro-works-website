# APK native file and print verification

APK 1.4 (version code 5) adds an origin-restricted Android message bridge for AAW pages, native Save As for Blob/data exports, user-selected content URI imports, external phone/email/browser links, popup routing, and system PDF printing from a snapshot of the current frame. Unsaved input/select/textarea values are included in print snapshots. Printed snapshots have scripting disabled and third-party network resources blocked. Exports are capped at 12 MB and cached privately only while the system Save dialog is open.

The approved cream/olive theme and existing AAW logo remain intact. No production SQL, business records, passwords, or role permissions are changed by this native update.

Tests cover detached CSV anchors, original CSV bytes, unsaved print data, untrusted origins and URL/filename policy. An Android 15 emulator job exercises system save, file-picker cancellation, a real PDF saved through Print Spooler, keyboard and back navigation, using only hardcoded synthetic HTML. The debug-only smoke flag cannot supply arbitrary HTML and is ignored by non-debug APKs. Emulator PDF text is checked for the synthetic marker after download. The actual user's phone and authenticated live business transactions are separate from this synthetic verification.

Verification status is recorded in the pull request's CI jobs. A successful APK compilation alone is not evidence that native UI tests passed.
