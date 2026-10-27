# Safe regression tests

Run `npm ci`, `npx playwright install chromium --only-shell`, then `npm test` (Node 22+).
Tests serve repository files on loopback in fresh browser contexts. The Supabase SDK is replaced with a mock; every external request is intercepted, and mock database writes/RPCs throw. No production credentials or records are needed.

Coverage: Food session reuse and wrong-role rejection, Master/Incharge portal tabs and links, Billing authorization, mobile/tablet/desktop page overflow and print visibility, measurement/GST rounding, salary attendance/OT/advances/food/partial-payment arithmetic, and Android launcher resource wiring, Food allocation/overlap handling, and active-page JavaScript syntax.

`AAW_TEST_ROOT` can point to an exported old revision to reproduce regressions. `AAW_CHROMIUM_PATH` optionally selects an installed Chromium executable.

These checks do not certify Supabase RLS, database procedures, historical data integrity, real device APK installation, or pixel-perfect equivalence to an approved screenshot. They intentionally never connect to Supabase.
