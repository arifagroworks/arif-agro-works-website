-- Additive tax-head rounding; no document, payment or audit rows are changed.
CREATE OR REPLACE FUNCTION public.aaw_invoice_payable(p jsonb)
RETURNS numeric
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO 'pg_catalog'
AS $function$
DECLARE item jsonb; qty numeric; rate numeric; subtotal numeric:=0; gst numeric; prev numeric; retention numeric; stage text; tax_amount numeric; mode text;
BEGIN
IF jsonb_typeof(p->'rows') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Invoice rows missing'; END IF;
FOR item IN SELECT value FROM jsonb_array_elements(p->'rows') LOOP
IF (item->>'l') IS NOT NULL AND (item->>'l')<>'' OR (item->>'w') IS NOT NULL AND (item->>'w')<>'' OR (item->>'h') IS NOT NULL AND (item->>'h')<>'' THEN
qty:=COALESCE(NULLIF(item->>'l','')::numeric,1)*COALESCE(NULLIF(item->>'w','')::numeric,1)*COALESCE(NULLIF(item->>'h','')::numeric,1);
ELSE qty:=COALESCE(NULLIF(item->>'qty','')::numeric,0); END IF;
rate:=COALESCE(NULLIF(item->>'rate','')::numeric,0);
IF qty<0 OR rate<0 THEN RAISE EXCEPTION 'Negative quantity or rate'; END IF;
subtotal:=subtotal+round(qty*rate,2);
END LOOP;
subtotal:=round(subtotal,2);
gst:=COALESCE(NULLIF(p->>'gst','')::numeric,0);
IF gst<0 OR gst>100 THEN RAISE EXCEPTION 'Invalid GST rate'; END IF;
stage:=COALESCE(p->>'billStage','regular');
prev:=CASE WHEN stage='regular' THEN 0 ELSE COALESCE(NULLIF(p->>'previousCertified','')::numeric,0) END;
retention:=COALESCE(NULLIF(p->>'retention','')::numeric,0);
IF prev<0 OR retention<0 THEN RAISE EXCEPTION 'Negative deductions'; END IF;
mode:=COALESCE(p->'invoiceParticulars'->>'raInvoiceTax','');
IF mode NOT IN ('','igst','split') THEN RAISE EXCEPTION 'Invalid invoice tax treatment'; END IF;
-- Old documents without a tax-treatment field keep their existing calculation.
tax_amount:=CASE WHEN mode='split' THEN 2*round(subtotal*gst/200,2) ELSE round(subtotal*gst/100,2) END;
RETURN round(subtotal+tax_amount-prev-retention,2);
END $function$
;
