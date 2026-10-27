# Two AAW assistants: proposed behavior and rollout

## Implemented first stage

`assets/aaw-help.js` supplies a Hindi/English public company FAQ and local project enquiry draft. It reads no portal session, makes no private database queries, stores no conversation, and sends no messages. Customers can review their exact draft and choose to continue in WhatsApp. The UI explicitly identifies itself as a FAQ.

`portal/aaw-command-desk.js` supplies a Master-only guided command desk. Each command checks the active server-returned Master session. It can read the selected site's client financial report and worker list, or open salary, attendance, Food, cash, production and billing tools for exact inputs. Financial values come from the existing guarded RPC, not a language model. Free-text payments, access changes and other writes are deliberately not implemented in this stage. The UI says that no external AI is connected.

Tests exercise 320/390/1440px, Hindi switching, escaped customer/worker text, exact enquiry draft review, stale-draft invalidation, private-data isolation, active Master rechecks and denial for Incharges. No external inference service, paid account, API key or production business record has been created by this stage.

## Real AI stage: configuration and implementation still required

The following describes the next stage. It must not be advertised as already live.

## Public website chatbot

A cream/olive Hindi/English chat panel answers grounded questions about AAW services, GSTIN, location and contact. It can gather customer-provided project type, dimensions, location and contact into an enquiry after showing the submission details, and offer a WhatsApp link. It never queries worker salary, attendance, cash, client balances or private staff data. Prices, delivery promises and contract terms must come from approved company information; otherwise it asks the customer for details or routes the enquiry to staff.

Public requests need rate limits and an abuse budget. New enquiries require a dedicated table, restricted insert endpoint, no public listing, and a Master-only enquiry inbox. Nothing is sent by WhatsApp/email automatically unless that action is separately requested.

## Master Admin assistant

Examples: “Site A की इस महीने की salary निकालो, Food/advance काटकर slips बनाओ”; “सभी sites के pending client payments दिखाओ”; “आज की attendance में कौन missing है”; “इस worker की monthly salary अगले महीने से 18,000 करो”; “Worker को दूसरी accessible site में transfer करो”.

The assistant verifies the active Master session, resolves exact site/worker/date IDs, then uses named application tools. Tools can read records, compute/report, prepare documents, set effective rates or submit validated actions through the existing guarded backend. No arbitrary SQL or blanket service-role execution is exposed to the model.

Reports/calculations run directly. Payments, Food finalization and access changes show one concrete summary and require one final confirmation. A plan has a short-lived ID, record version/hash and idempotency key; confirmation rereads balances/access before execution. Existing salary, Food locks and RLS still apply. Ambiguous names/dates trigger only necessary clarification. Actual changes are recorded with requester, intent, resolved scope, tool result and before/after audit references, excluding passwords and secret keys.

## Execution sequence

1. User instruction → validated intent + scoped plan.
2. Read/compute tools → result or one reviewable action summary.
3. If a sensitive write is requested, one explicit confirmation executes that exact plan.
4. Server revalidates active Master access, source data and guards; then returns a receipt/audit ID.
5. Partial failures remain visible and resumable. The assistant never says “paid/saved” before the backend confirms it.

## Required configuration

Use a backend-only AI provider connection with a dedicated key, model allowlist, usage cap and request limits. No key goes in HTML, Android resources or public JavaScript. An AI provider/key and spending budget have not been supplied for this app, so no paid inference service has been activated. Selecting and connecting that provider is needed before deploying a real free-text AI assistant. The public FAQ can optionally start as a clearly labelled FAQ without AI inference.

Rollout: public service answers/enquiries → Master read-only reports → guarded write plans → selected multi-step commands. Each stage needs synthetic tests for permissions, prompt injection, wrong-site/person resolution, retries and duplicate prevention before production use.
