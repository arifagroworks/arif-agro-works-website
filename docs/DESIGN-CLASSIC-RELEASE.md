# Classic Corporate design — approved

The approved design is A: warm cream (#f5f0df), olive (#5c6536), dark olive (#30391f), the existing green AAW welding logo and industrial imagery. This release applies that shared theme to the public website, main Master/Incharge portal and all active linked operational pages. Android system splash, custom splash, status/navigation bars and WebView background use the same cream; Android 12+ startup and launcher retain the AAW logo. APK version is 1.3 (code 4).

The public page keeps its English/Hindi controls, service/contact links and role-specific login links. Hindi font subsets are served with the site under their OFL license. The portal adds a role-filtered sidebar, responsive mobile navigation and a dashboard based on visible worker/site data. Quick actions open the existing secured operational modules. Incharge username login accepts the same synthetic email format used by account creation; existing email login continues to work.

Document print templates and payroll/food arithmetic are preserved. This visual release does not apply database/proposals/ready-to-use-operations.sql. That proposal remains separate pending isolated feature tests and complete UI integration; syntax loading alone is insufficient evidence for production deployment. Historical business records are not changed by this release.

Validation: 72 isolated automated checks pass, including 15 database permission/calculation tests and responsive browser checks for both portal roles. Visual inspection covers 360px and desktop public/portal views. Native APK is compiled and its packaged logo, splash resource, app identity and version checked in GitHub Actions. Real-device installation and an authenticated live business transaction have not been performed in this environment.

The Actions cache preserves the debug signing key for future 1.3+ workflow builds. Older APKs built with a different debug key may require uninstalling before installation; owner-managed release signing remains separate.
