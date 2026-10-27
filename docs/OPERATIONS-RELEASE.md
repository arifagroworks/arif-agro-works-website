# AAW operations release — 27 October 2026

Approved cream/olive Classic design is deployed by PR #2. APK 1.3 uses the AAW launcher/startup logo, cream native backgrounds and protected system-bar insets. The deployed CSS was fetched and its SHA-256 matched the tested source.

## Implemented operational workflows

- Daily/monthly salary rates with effective dates. Monthly salary is divided by 30 at full precision; total earned pay is rounded once. UI previews and server payment guards use each attendance date's rate. Existing paid salary periods and their attendance/advance/rate history are locked.
- Food daily attendance overrides date periods without double counting. Salary-deduction/company-paid types can vary by day. Grocery consumption dates spread exact integer paise across reports. Optional equal-value expense links prevent counting the same bill twice. Master can preview and finalize a settlement; affected entries become locked. Finalization cannot introduce a deduction into an already-paid salary period.
- Worker transfer retains old-site attendance/payments and links the new worker with the same person identity and effective rate. Old Food ends before transfer; cross-site Food conflicts are rejected.
- Per-incharge cash account with running balance, manual entries/edit/archive and CSV. Incharge-made expenses, real advances, salary payments and unlinked grocery create linked cash-out entries; manual FOOD deductions do not. Linked movements change only through their original record. Legacy unknown owners remain unassigned and Master-visible.
- Master report separates client collections, receivables, tax-inclusive invoices, expenses, earned labour, company Food share and cash surplus. Billed operating surplus is explicitly not statutory net profit.
- Immutable operational history and CSV exports. New operations screens have English/Hindi controls. Existing public bilingual controls remain available.
- Account administration rejects banned Master sessions even with old tokens. Account creation/reset/disable/enable records an audit request before mutation. Assignment changes are audited. Passwords are excluded from audit payloads.
- Advance/expense correction controls update the original row and preserve audit history. Salary payments remain immutable; archived workers remain available for final salary payment.

## Deployment and verification

Production migration: `20261027143748_aaw_ready_to_use_operations`, applied successfully through Supabase. Both admin Edge Functions redeployed with JWT verification enabled: manage-incharge v6 and manage-incharge-access v2. 22 public tables have RLS. Anonymous rate RPC and audit writes are denied; authenticated audit truncation is denied. Pre/post business row counts match; no business rows were deleted or reset, and no production demo records were created.

105 local isolated tests pass: browser interactions and payloads, monthly rounding/history, Food finalization/daily overrides/consumption, transfer, cash privacy, paid-period locks, Edge account authorization and original regression coverage. All test data is synthetic and local. GitHub CI independently runs these tests and compiles/inspects APK branding/version.

## Practical limits

A real Android device install/open and an authenticated live business transaction are not performed in this environment. APK is a debug build, not a signed Play Store release. The app requires internet and has no verified offline sync or automatic update. Older debug APKs may have a different signing key; current builds preserve the key through an Actions cache.

The financial report is an operational calculation with explicit definitions, not a statutory accounting system. Leaked-password protection remains a Supabase Auth dashboard setting; no supported connector control was available to enable it. See [Supabase password protection](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection). Authenticated definer RPC advisor notices are intentional for gated helpers; [advisor explanation](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable).

Broad existing legacy page labels are not all translated; the new operations workspace and public site provide bilingual controls. This release does not claim full translation of every historical diagnostic page.

Transfer scheduling guard applied as migration 20261027144256_aaw_guard_transfer_window; future-dated transfers are rejected to avoid early deactivation.
