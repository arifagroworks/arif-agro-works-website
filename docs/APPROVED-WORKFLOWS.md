# Approved workflow improvements — 28 October 2026

This change implements the seven approved suggestions on the existing Classic design. It does not create accounts, submit business transactions, send external messages, delete business records, or perform a production restore.

| Feature | Entry point and behavior |
| --- | --- |
| Today pending work | Portal Dashboard: current active-roster attendance missing today; workers with unfinalized Food this month; Master client dues through today. Buttons open the relevant existing module. Older Food periods remain available in Food Management. |
| Incharge mobile navigation | Four bottom buttons: Home, Attendance, Add Entry, More. Attendance name search and saved “Not marked” filter hide rows only; Save All and Mark All Present still apply to the full roster, as explained beside the filter. |
| Worker profile | Worker Profile: active and archived workers, cutoff date, existing effective-date salary calculator, attendance/OT, advances, finalized Food deductions and payment history. Covers the selected site; transferred history stays at the original site. |
| Draft recovery | Billing Studio: same authenticated user, same browser/device, one unsaved bill or letter, seven-day expiry, explicit Restore/Discard. No cloud sync. Storage failure is shown. Fresh online payment ledger and existing RA checks remain required. |
| Receipts | Receipt Attachments: choose an existing expense/grocery entry, upload JPEG/PNG/WebP/PDF, maximum 5 MB, download or archive. Bucket is private; access follows site RLS. Original files remain when archived. |
| Site comparison | Master Site Comparison: all accessible active sites (currently six), date range, existing server financial RPC, CSV. Cash flows and earned costs are separate; tax-inclusive operating surplus is not statutory profit. |
| Website enquiries | Public Contact form → Master Enquiry Inbox. Manual follow-up status, date and internal notes, optimistic concurrent-edit check. No automatic email/WhatsApp message. |

## Backend and privacy

`approved_workflow_improvements` adds a private receipt bucket, RLS-protected receipt metadata and Master-only enquiries. Only the service-role Edge Function can call the submission RPC. Anonymous clients cannot directly insert/read enquiries. Public form needs explicit contact consent. A per-hour salted address hash quota (five) and global daily quota (200), validation, honeypot and idempotency constrain the public write-only endpoint. A public publishable API key is checked in the function body; it is intentionally public and is not user authentication. CORS is limited to the deployed GitHub Pages origin. No IP address is stored raw. This is not CAPTCHA or a guarantee against all spam.

The Edge Function `submit-enquiry` requires `verify_jwt=false` because the form is anonymous and it checks the public API key itself. It uses standard server-side `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY`; neither secret is in client source. It must be deployed before publishing the public form.

Receipt source/site, object identity, size and MIME metadata are checked server-side. Storage disallows overwrite; failed unlinked uploads can be removed by their uploader. Uploads are not antivirus-scanned. File chooser and downloads use the existing APK bridge; downloaded private files become local files under the user's control.

Site export now includes 19 mapped tables. Hard Delete maps 17 business tables, including receipt metadata, and retains both confirmations, exact typed phrase, waits, archive equality and stale-snapshot protection. Private receipt binaries are retained separately and are **not embedded** in JSON/Excel/PDF exports. Existing prepared deletion requests require a new preview because the snapshot mapping changed. Installing this migration runs no business-record delete.

## Verification and holds

Isolated PGlite tests cover role/site boundaries, uploaded-object/source matching, quota/idempotency, and verified purge including receipt metadata while retaining the binary. Mocked-browser tests cover the four mobile actions, attendance filters retaining hidden rows, comparison, public enquiry retry, and explicit sanitized draft recovery with invoice ledger still locked. Edge handler tests never call production.

Still held at owner's request: five-site incharge setup, actual physical-phone business transaction trial, independent complete database restore verification, and full AI/voice. Automated Android smoke is not the held physical-phone business trial. No additional suggested functions are included without approval.
