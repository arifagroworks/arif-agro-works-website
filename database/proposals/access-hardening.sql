-- PROPOSAL ONLY: tested in an isolated, schema-derived PGlite database.
-- Do not apply to production without the owner's explicit database-change approval.
-- This file changes policies/functions/grants; it does not rewrite business records.
BEGIN;
CREATE OR REPLACE FUNCTION public.is_master_admin() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (SELECT 1 FROM public.staff_profiles p JOIN auth.users u ON u.id=p.user_id
    WHERE p.user_id=(SELECT auth.uid()) AND p.role='master'
      AND (u.banned_until IS NULL OR u.banned_until<=now()));
$$;
CREATE OR REPLACE FUNCTION public.is_staff_master() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT public.is_master_admin();
$$;
CREATE OR REPLACE FUNCTION public.daily_production_site_access(p_site_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT auth.uid() IS NOT NULL AND public.can_access_site(p_site_id);
$$;
ALTER POLICY dp_audit_read_v525 ON public.daily_production_audit
  USING (public.can_access_site(site_id));
-- Legacy permissive policies are OR'ed with newer policies. Remove overlapping
-- legacy write permissions before strengthening the remaining policies.
DROP POLICY IF EXISTS food_grocery_select_v59 ON public.food_grocery;
DROP POLICY IF EXISTS food_grocery_insert_v59 ON public.food_grocery;
DROP POLICY IF EXISTS food_grocery_update_v59 ON public.food_grocery;
DROP POLICY IF EXISTS food_grocery_delete_v59 ON public.food_grocery;
DROP POLICY IF EXISTS food_period_select_v59 ON public.worker_food_periods;
DROP POLICY IF EXISTS food_period_insert_v59 ON public.worker_food_periods;
DROP POLICY IF EXISTS food_period_update_v59 ON public.worker_food_periods;
DROP POLICY IF EXISTS food_period_delete_v59 ON public.worker_food_periods;
ALTER POLICY v59_worker_food_periods_insert ON public.worker_food_periods
  WITH CHECK (public.can_access_site(site_id) AND EXISTS (
    SELECT 1 FROM public.workers w WHERE w.id=worker_food_periods.worker_id
      AND w.site_id=worker_food_periods.site_id));
ALTER POLICY v59_worker_food_periods_update ON public.worker_food_periods
  USING (public.can_access_site(site_id))
  WITH CHECK (public.can_access_site(site_id) AND EXISTS (
    SELECT 1 FROM public.workers w WHERE w.id=worker_food_periods.worker_id
      AND w.site_id=worker_food_periods.site_id));
ALTER POLICY aaw_salary_incharge_insert ON public.worker_salary_payments
  WITH CHECK (public.is_assigned_to_site(site_id) AND EXISTS (
    SELECT 1 FROM public.workers w WHERE w.id=worker_salary_payments.worker_id
      AND w.site_id=worker_salary_payments.site_id AND NOT coalesce(w.is_deleted,false)));
ALTER POLICY incharge_accounts_master_read ON public.incharge_accounts USING (public.is_master_admin());
ALTER POLICY aaw_billing_master_select ON public.aaw_billing_documents USING (public.is_master_admin());
ALTER POLICY aaw_billing_master_insert ON public.aaw_billing_documents
  WITH CHECK (public.is_master_admin() AND created_by=auth.uid() AND updated_by=auth.uid());
ALTER POLICY aaw_billing_master_update ON public.aaw_billing_documents USING (public.is_master_admin())
  WITH CHECK (public.is_master_admin() AND updated_by=auth.uid());
ALTER POLICY aaw_billing_history_master_select ON public.aaw_billing_document_history USING (public.is_master_admin());
ALTER POLICY aaw_client_payments_master_select ON public.aaw_client_payments USING (public.is_master_admin());
ALTER POLICY aaw_client_payments_master_insert ON public.aaw_client_payments WITH CHECK (
  public.is_master_admin() AND created_by=auth.uid() AND EXISTS (
    SELECT 1 FROM public.aaw_billing_documents d WHERE d.id=document_id AND d.document_type='invoice'));
-- Trigger-only functions do not need a public RPC execution grant.
REVOKE EXECUTE ON FUNCTION public.aaw_billing_audit_update() FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.dp_audit_changes_v525() FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.guard_final_food_grocery() FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.guard_final_worker_food_period() FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.guard_manual_food_advance() FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.rls_auto_enable() FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.v515_salary_payment_lock() FROM PUBLIC,anon,authenticated;

-- Keep authorization current inside privileged entry points, even if a token
-- predates an account disable operation. Preserve their existing calculations.
CREATE OR REPLACE FUNCTION public.get_final_food_deductions(p_site_id uuid, p_start date, p_end date)
RETURNS TABLE(worker_id uuid, food_days bigint, deduction_amount numeric)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
IF NOT public.can_access_site(p_site_id) THEN RAISE EXCEPTION 'Site access denied'; END IF;
IF auth.uid() IS NULL OR NOT EXISTS (
SELECT 1
FROM public.staff_profiles sp
WHERE sp.user_id = auth.uid()
AND (
sp.role = 'master'
OR (
sp.role = 'incharge'
AND EXISTS (
SELECT 1
FROM public.site_assignments sa
WHERE sa.user_id = sp.user_id
AND sa.site_id = p_site_id
)
)
)
) THEN
RAISE EXCEPTION 'Permission denied for this site';
END IF;

IF p_site_id IS NULL
OR p_start IS NULL
OR p_end IS NULL
OR p_end < p_start THEN
RAISE EXCEPTION 'Invalid site or date range';
END IF;

IF EXISTS (
SELECT 1
FROM public.food_settlements fs
WHERE fs.site_id = p_site_id
AND fs.status = 'final'
AND fs.period_start <= p_end
AND fs.period_end >= p_start
AND (
fs.period_start < p_start
OR fs.period_end > p_end
)
) THEN
RAISE EXCEPTION
'Salary date range cuts through a final food settlement';
END IF;

RETURN QUERY
SELECT
fsw.worker_id,
SUM(fsw.food_days)::bigint,
SUM(fsw.share_amount)::numeric
FROM public.food_settlement_workers fsw
JOIN public.food_settlements fs
ON fs.id = fsw.settlement_id
JOIN public.workers w
ON w.id = fsw.worker_id
AND w.site_id = fs.site_id
WHERE fs.site_id = p_site_id
AND fs.status = 'final'
AND fs.period_start >= p_start
AND fs.period_end <= p_end
AND fsw.payment_type = 'salary_deduction'
GROUP BY fsw.worker_id;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.finalize_food_settlement(p_site_id uuid, p_start date, p_end date)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
v_id uuid;
v_total numeric(12,2);
v_days integer;
v_allocated numeric(12,2) := 0;
v_share numeric(12,2);
v_count integer;
v_index integer := 0;
v_worker record;
begin
if not public.is_master_admin() then raise exception 'Active Master Admin required'; end if;
-- Authentication + Master permission
if auth.uid() is null or not exists (
select 1 from public.staff_profiles
where user_id = auth.uid()
and role = 'master'
) then
raise exception 'Master Admin permission required';
end if;

if p_site_id is null
or p_start is null
or p_end is null
or p_end < p_start then
raise exception 'Invalid site or date range';
end if;

-- Prevent concurrent settlements for same site
perform pg_catalog.pg_advisory_xact_lock(
pg_catalog.hashtext(p_site_id::text)
);

if not exists (
select 1 from public.sites
where id = p_site_id
) then
raise exception 'Site not found';
end if;

-- Prevent overlapping finalized settlements
if exists (
select 1 from public.food_settlements
where site_id = p_site_id
and status = 'final'
and period_start <= p_end
and period_end >= p_start
) then
raise exception 'This period overlaps an existing final settlement';
end if;

-- Check food-period overlaps per worker
if exists (
select 1
from public.worker_food_periods a
join public.worker_food_periods b
on a.worker_id = b.worker_id
and a.site_id = b.site_id
and a.id < b.id
and a.start_date <= b.end_date
and b.start_date <= a.end_date
where a.site_id = p_site_id
and a.start_date <= p_end
and a.end_date >= p_start
and b.start_date <= p_end
and b.end_date >= p_start
) then
raise exception 'Overlapping worker food periods found';
end if;

-- A worker must have one payment type per settlement
if exists (
select 1
from public.worker_food_periods
where site_id = p_site_id
and start_date <= p_end
and end_date >= p_start
group by worker_id
having count(distinct payment_type) > 1
) then
raise exception 'Worker has mixed payment types in this period. Split the settlement';
end if;

-- Do not finalize when old manual FOOD deductions
-- exist for participating workers in this period.
if exists (
select 1
from public.worker_advances a
where a.site_id = p_site_id
and a.advance_date between p_start and p_end
and btrim(a.notes) ilike 'FOOD:%'
and exists (
select 1
from public.worker_food_periods fp
where fp.site_id = p_site_id
and fp.worker_id = a.worker_id
and fp.payment_type = 'salary_deduction'
and fp.start_date <= p_end
and fp.end_date >= p_start
)
) then
raise exception 'Existing manual FOOD advances found. Reconcile before finalizing';
end if;

select coalesce(sum(amount),0)
into v_total
from public.food_grocery
where site_id = p_site_id
and purchase_date between p_start and p_end;

if v_total <= 0 then
raise exception 'No grocery expenses found in selected period';
end if;

select coalesce(sum(
least(end_date,p_end)
- greatest(start_date,p_start) + 1
),0)
into v_days
from public.worker_food_periods
where site_id = p_site_id
and start_date <= p_end
and end_date >= p_start;

if v_days <= 0 then
raise exception 'No food days found in selected period';
end if;

-- Create finalized header
insert into public.food_settlements (
site_id, period_start, period_end,
grocery_total, total_food_days,
status, finalized_at, created_by
)
values (
p_site_id, p_start, p_end,
v_total, v_days,
'final', now(), auth.uid()
)
returning id into v_id;

-- Count participating workers
select count(distinct worker_id)
into v_count
from public.worker_food_periods
where site_id = p_site_id
and start_date <= p_end
and end_date >= p_start;

-- Allocate exact grocery total, including rounding remainder
-- Largest-remainder allocation in integer paise: exact total, no negative
-- residual for small bills split among many workers. Stable worker-id tie break.
for v_worker in
with eligible as (
 select worker_id,min(payment_type) as payment_type,
   sum(least(end_date,p_end)-greatest(start_date,p_start)+1)::integer as food_days
 from public.worker_food_periods
 where site_id=p_site_id and start_date<=p_end and end_date>=p_start
 group by worker_id
), raw_shares as (
 select *,v_total*100*food_days/v_days as exact_paise from eligible
), ranked as (
 select *,floor(exact_paise) as base_paise,
   row_number() over(order by exact_paise-floor(exact_paise) desc,worker_id) as rank,
   sum(floor(exact_paise)) over() as base_total
 from raw_shares
)
select worker_id,payment_type,food_days,
 (base_paise+case when rank<=v_total*100-base_total then 1 else 0 end)/100 as share_amount
from ranked order by worker_id
loop
 insert into public.food_settlement_workers(settlement_id,worker_id,food_days,share_amount,payment_type)
 values(v_id,v_worker.worker_id,v_worker.food_days,v_worker.share_amount,v_worker.payment_type);
end loop;

return v_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.v515_salary_payment_lock()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
v_role text;
v_site uuid;
v_wage numeric;
v_ot_rate numeric;
v_gross numeric;
v_advances numeric;
v_food numeric;
v_paid numeric;
v_balance numeric;
BEGIN

-- Do not allow editing existing payments.
IF TG_OP = 'UPDATE' THEN
RAISE EXCEPTION
'Existing salary payments cannot be edited';
END IF;

SELECT role INTO v_role
FROM public.staff_profiles
WHERE user_id = auth.uid();

IF NOT public.can_access_site(NEW.site_id) THEN
RAISE EXCEPTION
'PAYMENT BLOCKED: Master Admin only';
END IF;

IF NEW.amount IS NULL OR NEW.amount <= 0 THEN
RAISE EXCEPTION
'PAYMENT BLOCKED: Invalid amount';
END IF;

IF NEW.worker_id IS NULL
OR NEW.site_id IS NULL
OR NEW.payment_date IS NULL
OR NEW.period_start IS NULL
OR NEW.period_end IS NULL
OR NEW.period_start > NEW.period_end
OR NEW.payment_date < NEW.period_start
OR NEW.payment_date > NEW.period_end THEN
RAISE EXCEPTION
'PAYMENT BLOCKED: Invalid dates or worker';
END IF;

-- Serialize payments for the same worker.
SELECT site_id, daily_wage, overtime_rate
INTO v_site, v_wage, v_ot_rate
FROM public.workers
WHERE id = NEW.worker_id
AND COALESCE(is_deleted, false) = false
FOR UPDATE;

IF NOT FOUND OR v_site IS DISTINCT FROM NEW.site_id THEN
RAISE EXCEPTION
'PAYMENT BLOCKED: Invalid worker/site';
END IF;

-- Never insert a payment behind a later
-- recorded payment or completed salary period.
IF EXISTS (
SELECT 1
FROM public.worker_salary_payments p
WHERE p.worker_id = NEW.worker_id
AND (
p.payment_date > NEW.payment_date
OR p.period_end > NEW.period_end
)
) THEN
RAISE EXCEPTION
'PAYMENT BLOCKED: Earlier salary cutoff';
END IF;

-- Reject salary cutoff inside a finalized
-- food settlement involving this worker.
IF EXISTS (
SELECT 1
FROM public.food_settlement_workers fw
JOIN public.food_settlements fs
ON fs.id = fw.settlement_id
WHERE fw.worker_id = NEW.worker_id
AND fw.payment_type = 'salary_deduction'
AND fs.site_id = NEW.site_id
AND fs.status = 'final'
AND fs.period_start <= NEW.period_end
AND fs.period_end > NEW.period_end
) THEN
RAISE EXCEPTION
'PAYMENT BLOCKED: Incomplete food period';
END IF;

-- Earnings through the requested cutoff.
SELECT COALESCE(SUM(
(CASE
WHEN a.status = 'present' THEN 1
WHEN a.status = 'half_day' THEN 0.5
ELSE 0
END) * COALESCE(v_wage, 0)
+ COALESCE(a.overtime_hours, 0)
* COALESCE(v_ot_rate, 0)
), 0)
INTO v_gross
FROM public.worker_attendance a
WHERE a.worker_id = NEW.worker_id
AND a.site_id = NEW.site_id
AND a.attendance_date <= NEW.period_end;

-- Includes regular advances and manual FOOD.
SELECT COALESCE(SUM(a.amount), 0)
INTO v_advances
FROM public.worker_advances a
WHERE a.worker_id = NEW.worker_id
AND a.site_id = NEW.site_id
AND a.advance_date <= NEW.period_end;

-- Finalized food deductions through cutoff.
SELECT COALESCE(SUM(fw.share_amount), 0)
INTO v_food
FROM public.food_settlement_workers fw
JOIN public.food_settlements fs
ON fs.id = fw.settlement_id
WHERE fw.worker_id = NEW.worker_id
AND fw.payment_type = 'salary_deduction'
AND fs.site_id = NEW.site_id
AND fs.status = 'final'
AND fs.period_end <= NEW.period_end;

-- Count all previous payments through cutoff,
-- including payments covering overlapping periods.
SELECT COALESCE(SUM(p.amount), 0)
INTO v_paid
FROM public.worker_salary_payments p
WHERE p.worker_id = NEW.worker_id
AND p.site_id = NEW.site_id
AND p.payment_date <= NEW.period_end;

v_balance :=
v_gross - v_advances - v_food - v_paid;

IF v_balance <= 0 OR NEW.amount > v_balance THEN
RAISE EXCEPTION
'PAYMENT BLOCKED: Available Rs %, requested Rs %',
ROUND(v_balance, 2),
ROUND(NEW.amount, 2);
END IF;

RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.aaw_payment_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE doc record; already numeric;
BEGIN
IF auth.uid() IS NULL OR NEW.created_by IS DISTINCT FROM auth.uid() OR NOT public.is_master_admin() THEN
RAISE EXCEPTION 'Master Admin authorization required';
END IF;
SELECT document_type,payload INTO doc FROM public.aaw_billing_documents WHERE id=NEW.document_id FOR UPDATE;
IF NOT FOUND OR doc.document_type<>'invoice' THEN RAISE EXCEPTION 'Valid invoice required'; END IF;
SELECT COALESCE(sum(amount),0) INTO already FROM public.aaw_client_payments WHERE document_id=NEW.document_id;
IF already+NEW.amount>public.aaw_invoice_payable(doc.payload) THEN
RAISE EXCEPTION 'Payment exceeds outstanding invoice balance';
END IF;
RETURN NEW;
END $function$
;

CREATE OR REPLACE FUNCTION public.guard_manual_food_advance()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
v_site_id uuid;
begin
if tg_op = 'DELETE' then
v_site_id := old.site_id;
else
v_site_id := new.site_id;
end if;

perform pg_catalog.pg_advisory_xact_lock(
pg_catalog.hashtext(v_site_id::text)
);

-- Prevent adding/changing a manual FOOD advance
-- for a worker whose matching food settlement
-- is already finalized.

if tg_op in ('INSERT','UPDATE') then
if btrim(coalesce(new.notes,'')) ilike 'FOOD:%'
and exists (
select 1
from public.food_settlements fs
join public.food_settlement_workers fsw
on fsw.settlement_id = fs.id
where fs.site_id = new.site_id
and fs.status = 'final'
and fsw.worker_id = new.worker_id
and fsw.payment_type = 'salary_deduction'
and new.advance_date
between fs.period_start and fs.period_end
)
then
raise exception
'Manual FOOD advance conflicts with finalized food settlement';
end if;
end if;

return case
when tg_op = 'DELETE' then old
else new
end;
end;
$function$
;
COMMIT;
