# Owner-only setup remaining

The private release signing backup is delivered privately, outside this repository. Only its public certificate fingerprint is in `android-app/release-signing.json`. Release builds fail if the owner key/passwords are absent, and the release workflow rejects a different signing certificate. Private signing material is never uploaded as a workflow artifact or committed to the public repository.

## GitHub signing secrets

Open repository Settings → Secrets and variables → Actions. Create `AAW_RELEASE_KEYSTORE_BASE64`, `AAW_RELEASE_STORE_PASSWORD`, `AAW_RELEASE_KEY_ALIAS` and `AAW_RELEASE_KEY_PASSWORD` using their matching files in the private owner backup. The current GitHub connector cannot write repository secrets. No password/token should be pasted in chat.

Run **AAW Android Release**. Verification includes browser/database tests and Android emulator checks before signing. The signed APK/AAB and SHA256SUMS are available as `AAW-Signed-Release`. Choose Publish when running the workflow to create `android-vVERSION` with a stable `releases/latest/download/AAW-Release.apk` URL. Future native updates must use the same key and an increased versionCode. Website/portal changes load online and do not require rebuilding the native wrapper.

The first owner-signed release has a different certificate from earlier debug builds. Switching can require uninstall/reinstall; back up local drafts first. Cloud business records are not deleted by uninstalling an APK. Existing debug updates remain separate and use the workflow's debug-key cache.

## Supabase leaked-password protection

Open [Auth Email settings](https://supabase.com/dashboard/project/qfydekphbdpvvczhimjs/auth/providers?provider=Email), enable leaked-password protection and save. [Supabase documentation](https://supabase.com/docs/guides/auth/password-security) says this requires Pro or above. No paid plan upgrade has been performed or authorized here. The available Supabase connector has no Auth configuration update tool.

For an already-authorized owner Management API session, `docs/tools/enable-password-protection.py` changes only `password_hibp_enabled` and reads the value back. It does not print the token or other Auth settings. Use it only locally with an owner token; never commit tokens. Without an owner session/control, this setting remains uncompleted.

## Verification boundaries

Synthetic tests do not substitute for the user's own Master/Incharge login on their actual phone. No production test workers, payroll payments, client receipts or Food settlements were inserted. A real business save requires the user's intended records and authenticated session; those credentials were not requested or guessed.
