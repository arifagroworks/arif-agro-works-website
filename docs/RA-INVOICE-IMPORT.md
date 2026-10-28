# RA bill → reviewed GST invoice

Available to the authenticated Master in Billing Studio. The original bill is an input document, not an instruction or an automatically issued invoice.

## Workflow

1. Open **Details → Import RA Bill → GST Invoice**. Choose a clear English printed PDF, JPG, PNG or WebP and press **Read selected file**. TXT/CSV and pasted labelled table text are also supported.
2. Compare the original with the extracted work rows. The supported abstract layout is: work-order quantity/rate/amount, previous/current/cumulative quantities, and previous/current/cumulative amounts. Explicit labelled tab/pipe/CSV tables can use other column orders. An unfamiliar layout produces a manual review grid, never a guessed invoice.
3. Verify **This Bill quantity**, work-order rate, description/unit, GST rate and IGST vs CGST+SGST. Source row amounts and source taxable/GST/gross can be compared separately. Incorrect OCR grouping/decimals must be corrected. Differences above ₹1 block preparation; smaller rounding differences require acknowledgement.
4. Prepare the draft. Select the site; complete recipient GSTIN and addresses, verified place of supply, SAC/HSN and RA reference. A previous document can provide particulars for review. The RA's old invoice number/date are not copied; the portal suggests a new number and today's local date.
5. Review the current preview and tick the verification box. Then Save Online and use Print / Save PDF. Invoice payment-loading guards still apply. Editing financial/recipient/source particulars invalidates the verification.

## Calculations and settlement

- BigInt scaled decimal arithmetic; quantities up to six decimals, rates up to four. Each work line is rounded half-up to paise, then summed.
- IGST is rounded once. CGST and SGST are each rounded separately at half the entered total tax rate. Backend `aaw_invoice_payable` follows the same tax-head policy; old payloads without a treatment retain their previous calculation.
- A current-period RA import uses **regular invoice** mode and current-period quantities. Previous certified amounts are **zero** so previous work is not subtracted twice. Source retention/TDS/receipts are not silently substituted for taxable value or actual client payments.
- The generated document is a GST invoice draft for the RA period; it does not certify completion of the whole contract.
- Human review remains required. OCR is not guaranteed to read every layout or tiny decimal correctly. A missing quantity decimal is reconstructed only when previous/cumulative quantities and printed line value independently agree; this is flagged for verification.

## Privacy, runtime and limits

Original file bytes, OCR text and preview image stay in browser memory. Only selected invoice fields plus source name/SHA-256/provenance and acknowledged amount differences are included when the owner explicitly saves the invoice. No third-party document/AI API receives the bill. No original images, customer signatures or customer document fixtures are committed.

The browser downloads version-pinned Tesseract.js 7.0.0, its 7.0.0 WASM core and English data 1.0.0 from jsDelivr. The main loader has SHA-384 integrity verification. PDF.js 6.4.299 reads PDF text locally or renders scanned pages for OCR. No paid inference API/key is configured. CDN availability, first-load downloads, device memory and image quality affect reading; pasted text/manual reviewed rows remain available when reading fails.

Limit: 20 MB, six PDF pages, one RA abstract and one combined GST rate per invoice. Mixed slabs are not automatically combined. No handwritten-bill guarantee. Cancel releases the reader; long reads time out. Duplicate-source checks cover the currently loaded document list (latest 200); normal database invoice-number uniqueness remains authoritative.

PDF/XLS exports are portal-generated documents; statutory e-invoice/IRN or return filing is not performed by this feature.

Primary implementation references: [Tesseract.js API](https://github.com/naptha/tesseract.js/blob/master/docs/api.md), [local runtime paths](https://github.com/naptha/tesseract.js/blob/master/docs/local-installation.md), [PDF.js examples](https://mozilla.github.io/pdf.js/examples/), [CBIC invoice particulars](https://taxinformation.cbic.gov.in/content-page/explore-rules/1000136/1000001).
