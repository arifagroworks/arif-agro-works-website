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

## Owner-only remaining steps

1. Add the four signing secrets from the private backup in GitHub repository Settings → Secrets and variables → Actions. This connector cannot write repository secrets. No passwords/tokens should be pasted in chat.
2. After that one-time setup, run **AAW Android Release** with Publish selected for the first public GitHub release. Future main-branch changes to `android-app/app/build.gradle` automatically verify/sign/publish a new version. Increase both versionName and versionCode. Existing versions are not overwritten; downgrades, mismatched package/signers and non-increasing update codes are rejected.
3. Install the owner-signed APK on the actual phone and verify existing Master/Incharge logins and intended business use. Back up unfinished local entries before switching from a differently signed debug app. Actual-device installation is not claimed by emulator tests; cloud records are not removed by APK uninstall.
4. Supabase leaked-password protection remains an owner Auth/plan setting; the connector cannot update Auth configuration. No paid upgrade was performed. See [owner setup](OWNER-RELEASE-SETUP.md).

No production business records were inserted, changed, deleted or reset during this closeout. The site export tool remains read-only; destructive bulk deletion stays locked by design.

## Explicitly postponed

The owner postponed full generative AI, voice and bill-photo reading on 28 October 2026. Do not activate provider billing, add an API key, or implement that next stage until the owner resumes it. Existing FAQ/guided tools stay available.
