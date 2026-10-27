# Database changes awaiting explicit production approval

`access-hardening.sql` is a reviewable proposal, not an automatically applied migration. It was executed only against an in-memory PGlite test database reconstructed from schema metadata, using synthetic demo rows.

Run `npm ci` then `node --test --test-timeout=20000 tests/backend.test.cjs` to reproduce the isolated checks. `npm test` also runs browser regressions. No production connection is used by either suite.

The schema fixture has simplified grants, Auth claims and defaults, and does not contain production records or secrets. It preserves the relevant observed policy/function/constraint/trigger logic for these regressions. Tests reproduce the disabled Production access and cross-site Food defects before applying the proposal locally, then verify the fixes, salary overpayment guards, Food finalization/rounding and invoice calculations.

Before production application: inspect current definitions for drift, take an owner-approved backup, generate a proper migration through the Supabase CLI, review any intended behavior changes (including Food delete permission), apply to staging, and re-run advisors. Existing production rows have not been validated or rewritten by this task. Concurrency/load behavior, full Supabase Auth lifecycle and effective-rate payroll logic remain outside this fixture's certification.

The proposal intentionally does not blanket-revoke authorization helper functions required by RLS, does not create extra production projects/paid branches, and does not alter monthly salary, cash-ledger ownership or income-report schemas.
