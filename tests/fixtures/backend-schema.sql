-- Schema-only staging fixture reconstructed from metadata, 27 October 2026.
-- No production records, credentials, or Auth user identifiers. Grants/defaults are
-- simplified for the isolated test harness; this is not a production migration.
CREATE ROLE anon;
CREATE ROLE authenticated;
CREATE SCHEMA auth;
CREATE TABLE auth.users(id uuid PRIMARY KEY, banned_until timestamptz);
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT NULLIF(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
CREATE TABLE public."sites" ("id" uuid DEFAULT gen_random_uuid(),"site_name" text,"is_active" boolean DEFAULT true,"created_at" timestamp with time zone DEFAULT now());
CREATE TABLE public."site_assignments" ("user_id" uuid,"site_id" uuid);
CREATE TABLE public."staff_profiles" ("user_id" uuid,"full_name" text,"role" text,"created_at" timestamp with time zone DEFAULT now());
CREATE TABLE public."food_settlement_workers" ("id" uuid DEFAULT gen_random_uuid(),"settlement_id" uuid,"worker_id" uuid,"food_days" integer,"share_amount" numeric(12,2),"payment_type" text,"created_at" timestamp with time zone DEFAULT now());
CREATE TABLE public."food_settlements" ("id" uuid DEFAULT gen_random_uuid(),"site_id" uuid,"period_start" date,"period_end" date,"grocery_total" numeric(12,2),"total_food_days" integer,"status" text,"finalized_at" timestamp with time zone,"created_by" uuid,"created_at" timestamp with time zone DEFAULT now());
CREATE TABLE public."incharge_accounts" ("user_id" uuid,"username" text,"site_id" uuid,"is_enabled" boolean,"created_at" timestamp with time zone DEFAULT now());
CREATE TABLE public."aaw_billing_document_history" ("audit_id" bigint,"document_id" uuid,"edited_by" uuid,"changed_at" timestamp with time zone,"previous_payload" jsonb,"previous_number" text);
CREATE TABLE public."aaw_client_payments" ("id" uuid DEFAULT gen_random_uuid(),"document_id" uuid,"payment_date" date,"amount" numeric(14,2),"reference" text,"mode" text,"created_by" uuid,"created_at" timestamp with time zone DEFAULT now());
CREATE TABLE public."aaw_billing_documents" ("id" uuid DEFAULT gen_random_uuid(),"document_type" text,"document_number" text,"document_date" date,"client_name" text,"payload" jsonb,"created_by" uuid,"updated_by" uuid,"created_at" timestamp with time zone DEFAULT now(),"updated_at" timestamp with time zone,"site_id" uuid);
CREATE TABLE public."daily_production_audit" ("id" uuid DEFAULT gen_random_uuid(),"entry_id" uuid,"site_id" uuid,"action" text,"changed_by" uuid,"changed_at" timestamp with time zone,"old_record" jsonb,"new_record" jsonb);
CREATE TABLE public."daily_production_entries" ("id" uuid DEFAULT gen_random_uuid(),"site_id" uuid,"work_date" date,"work_activity" text,"location_zone" text,"worker_team" text,"unit" text,"length" numeric,"width" numeric,"height_thickness" numeric,"pieces" numeric,"quantity" numeric,"rate" numeric,"amount" numeric,"remarks" text,"created_by" uuid,"created_at" timestamp with time zone DEFAULT now(),"updated_at" timestamp with time zone,"is_deleted" boolean DEFAULT false,"deleted_at" timestamp with time zone,"deleted_by" uuid);
CREATE TABLE public."food_grocery" ("id" uuid DEFAULT gen_random_uuid(),"site_id" uuid,"purchase_date" date,"description" text,"amount" numeric(12,2),"created_at" timestamp with time zone DEFAULT now());
CREATE TABLE public."worker_food_periods" ("id" uuid DEFAULT gen_random_uuid(),"site_id" uuid,"worker_id" uuid,"start_date" date,"end_date" date,"payment_type" text,"created_at" timestamp with time zone DEFAULT now());
CREATE TABLE public."worker_salary_payments" ("id" uuid DEFAULT gen_random_uuid(),"worker_id" uuid,"site_id" uuid,"payment_date" date,"period_start" date,"period_end" date,"amount" numeric(12,2),"notes" text,"created_at" timestamp with time zone DEFAULT now());
CREATE TABLE public."worker_salary_rates" ("id" uuid DEFAULT gen_random_uuid(),"worker_id" uuid,"site_id" uuid,"effective_from" date,"daily_rate" numeric(12,2),"overtime_hourly_rate" numeric(12,2),"created_at" timestamp with time zone DEFAULT now());
CREATE TABLE public."worker_advances" ("id" uuid DEFAULT gen_random_uuid(),"worker_id" uuid,"site_id" uuid,"advance_date" date,"amount" numeric(12,2),"notes" text,"created_at" timestamp with time zone DEFAULT now());
CREATE TABLE public."worker_attendance" ("id" uuid DEFAULT gen_random_uuid(),"worker_id" uuid,"site_id" uuid,"attendance_date" date,"status" text,"check_in" time without time zone,"check_out" time without time zone,"overtime_hours" numeric(7,2),"notes" text,"created_at" timestamp with time zone DEFAULT now());
CREATE TABLE public."site_cash_ledger" ("id" uuid DEFAULT gen_random_uuid(),"site_id" uuid,"entry_date" date,"entry_type" text,"category" text,"description" text,"amount" numeric(12,2),"created_at" timestamp with time zone DEFAULT now());
CREATE TABLE public."site_expenses" ("id" uuid DEFAULT gen_random_uuid(),"site_id" uuid,"expense_date" date,"category" text,"description" text,"amount" numeric(12,2),"created_at" timestamp with time zone DEFAULT now());
CREATE TABLE public."workers" ("id" uuid DEFAULT gen_random_uuid(),"site_id" uuid,"full_name" text,"mobile_number" text,"joining_date" date,"leaving_date" date,"daily_wage" numeric(12,2),"overtime_rate" numeric(12,2),"is_active" boolean DEFAULT true,"created_at" timestamp with time zone DEFAULT now(),"is_deleted" boolean DEFAULT false,"deleted_at" timestamp with time zone);
CREATE UNIQUE INDEX fixture_workers_id_site ON public.workers(id,site_id);
ALTER TABLE public."site_assignments" ADD CONSTRAINT "site_assignments_pkey" PRIMARY KEY (user_id, site_id);
ALTER TABLE public."workers" ADD CONSTRAINT "workers_pkey" PRIMARY KEY (id);
ALTER TABLE public."staff_profiles" ADD CONSTRAINT "staff_profiles_role_check" CHECK ((role = ANY (ARRAY['master'::text, 'incharge'::text])));
ALTER TABLE public."staff_profiles" ADD CONSTRAINT "staff_profiles_pkey" PRIMARY KEY (user_id);
ALTER TABLE public."sites" ADD CONSTRAINT "sites_pkey" PRIMARY KEY (id);
ALTER TABLE public."worker_attendance" ADD CONSTRAINT "worker_attendance_status_check" CHECK ((status = ANY (ARRAY['present'::text, 'absent'::text, 'half_day'::text, 'leave'::text])));
ALTER TABLE public."worker_attendance" ADD CONSTRAINT "worker_attendance_overtime_hours_check" CHECK ((overtime_hours >= (0)::numeric));
ALTER TABLE public."worker_attendance" ADD CONSTRAINT "worker_attendance_pkey" PRIMARY KEY (id);
ALTER TABLE public."worker_attendance" ADD CONSTRAINT "worker_attendance_worker_id_site_id_attendance_date_key" UNIQUE (worker_id, site_id, attendance_date);
ALTER TABLE public."worker_salary_rates" ADD CONSTRAINT "worker_salary_rates_daily_rate_check" CHECK ((daily_rate >= (0)::numeric));
ALTER TABLE public."worker_salary_rates" ADD CONSTRAINT "worker_salary_rates_overtime_hourly_rate_check" CHECK ((overtime_hourly_rate >= (0)::numeric));
ALTER TABLE public."worker_salary_rates" ADD CONSTRAINT "worker_salary_rates_pkey" PRIMARY KEY (id);
ALTER TABLE public."worker_salary_rates" ADD CONSTRAINT "worker_salary_rates_worker_id_site_id_effective_from_key" UNIQUE (worker_id, site_id, effective_from);
ALTER TABLE public."worker_advances" ADD CONSTRAINT "worker_advances_amount_check" CHECK ((amount > (0)::numeric));
ALTER TABLE public."worker_advances" ADD CONSTRAINT "worker_advances_pkey" PRIMARY KEY (id);
ALTER TABLE public."site_expenses" ADD CONSTRAINT "site_expenses_amount_check" CHECK ((amount > (0)::numeric));
ALTER TABLE public."site_expenses" ADD CONSTRAINT "site_expenses_pkey" PRIMARY KEY (id);
ALTER TABLE public."site_cash_ledger" ADD CONSTRAINT "site_cash_ledger_entry_type_check" CHECK ((entry_type = ANY (ARRAY['cash_in'::text, 'cash_out'::text])));
ALTER TABLE public."site_cash_ledger" ADD CONSTRAINT "site_cash_ledger_amount_check" CHECK ((amount > (0)::numeric));
ALTER TABLE public."site_cash_ledger" ADD CONSTRAINT "site_cash_ledger_pkey" PRIMARY KEY (id);
ALTER TABLE public."worker_salary_payments" ADD CONSTRAINT "worker_salary_payments_amount_check" CHECK ((amount > (0)::numeric));
ALTER TABLE public."worker_salary_payments" ADD CONSTRAINT "worker_salary_payments_check" CHECK (((period_end IS NULL) OR (period_start IS NULL) OR (period_end >= period_start)));
ALTER TABLE public."worker_salary_payments" ADD CONSTRAINT "worker_salary_payments_pkey" PRIMARY KEY (id);
ALTER TABLE public."food_grocery" ADD CONSTRAINT "food_grocery_amount_check" CHECK ((amount > (0)::numeric));
ALTER TABLE public."food_grocery" ADD CONSTRAINT "food_grocery_pkey" PRIMARY KEY (id);
ALTER TABLE public."worker_food_periods" ADD CONSTRAINT "worker_food_periods_payment_type_check" CHECK ((payment_type = ANY (ARRAY['salary_deduction'::text, 'company_paid'::text])));
ALTER TABLE public."worker_food_periods" ADD CONSTRAINT "valid_food_dates" CHECK ((end_date >= start_date));
ALTER TABLE public."worker_food_periods" ADD CONSTRAINT "worker_food_periods_pkey" PRIMARY KEY (id);
ALTER TABLE public."food_settlements" ADD CONSTRAINT "food_settlements_status_check" CHECK ((status = ANY (ARRAY['draft'::text, 'final'::text])));
ALTER TABLE public."food_settlements" ADD CONSTRAINT "food_settlement_valid_dates" CHECK ((period_end >= period_start));
ALTER TABLE public."food_settlements" ADD CONSTRAINT "food_settlements_pkey" PRIMARY KEY (id);
ALTER TABLE public."food_settlements" ADD CONSTRAINT "food_settlement_unique_period" UNIQUE (site_id, period_start, period_end);
ALTER TABLE public."food_settlement_workers" ADD CONSTRAINT "food_settlement_workers_food_days_check" CHECK ((food_days >= 0));
ALTER TABLE public."food_settlement_workers" ADD CONSTRAINT "food_settlement_workers_share_amount_check" CHECK ((share_amount >= (0)::numeric));
ALTER TABLE public."food_settlement_workers" ADD CONSTRAINT "food_settlement_workers_payment_type_check" CHECK ((payment_type = ANY (ARRAY['salary_deduction'::text, 'company_paid'::text])));
ALTER TABLE public."food_settlement_workers" ADD CONSTRAINT "food_settlement_workers_pkey" PRIMARY KEY (id);
ALTER TABLE public."food_settlement_workers" ADD CONSTRAINT "food_settlement_workers_settlement_id_worker_id_key" UNIQUE (settlement_id, worker_id);
ALTER TABLE public."incharge_accounts" ADD CONSTRAINT "incharge_accounts_pkey" PRIMARY KEY (user_id);
ALTER TABLE public."incharge_accounts" ADD CONSTRAINT "incharge_accounts_username_key" UNIQUE (username);
ALTER TABLE public."daily_production_entries" ADD CONSTRAINT "daily_production_entries_quantity_check" CHECK ((quantity > (0)::numeric));
ALTER TABLE public."daily_production_entries" ADD CONSTRAINT "daily_production_entries_rate_check" CHECK (((rate IS NULL) OR (rate >= (0)::numeric)));
ALTER TABLE public."daily_production_entries" ADD CONSTRAINT "daily_production_activity_nonempty" CHECK ((length(TRIM(BOTH FROM work_activity)) > 0));
ALTER TABLE public."daily_production_entries" ADD CONSTRAINT "daily_production_entries_pkey" PRIMARY KEY (id);
ALTER TABLE public."daily_production_audit" ADD CONSTRAINT "daily_production_audit_action_check" CHECK ((action = ANY (ARRAY['INSERT'::text, 'UPDATE'::text, 'ARCHIVE'::text])));
ALTER TABLE public."daily_production_audit" ADD CONSTRAINT "daily_production_audit_pkey" PRIMARY KEY (id);
ALTER TABLE public."aaw_billing_documents" ADD CONSTRAINT "aaw_billing_documents_document_type_check" CHECK ((document_type = ANY (ARRAY['invoice'::text, 'quotation'::text, 'proforma'::text, 'measurement'::text, 'letterhead'::text])));
ALTER TABLE public."aaw_billing_documents" ADD CONSTRAINT "aaw_billing_documents_pkey" PRIMARY KEY (id);
ALTER TABLE public."aaw_billing_documents" ADD CONSTRAINT "aaw_billing_documents_document_type_document_number_key" UNIQUE (document_type, document_number);
ALTER TABLE public."aaw_billing_document_history" ADD CONSTRAINT "aaw_billing_document_history_pkey" PRIMARY KEY (audit_id);
ALTER TABLE public."aaw_client_payments" ADD CONSTRAINT "aaw_client_payments_amount_check" CHECK ((amount > (0)::numeric));
ALTER TABLE public."aaw_client_payments" ADD CONSTRAINT "aaw_client_payments_reference_check" CHECK ((length(TRIM(BOTH FROM reference)) > 0));
ALTER TABLE public."aaw_client_payments" ADD CONSTRAINT "aaw_client_payments_pkey" PRIMARY KEY (id);
ALTER TABLE public."aaw_client_payments" ADD CONSTRAINT "aaw_client_payments_reference_key" UNIQUE (reference);
ALTER TABLE public."site_assignments" ADD CONSTRAINT "site_assignments_user_id_fkey" FOREIGN KEY (user_id) REFERENCES staff_profiles(user_id) ON DELETE CASCADE;
ALTER TABLE public."site_assignments" ADD CONSTRAINT "site_assignments_site_id_fkey" FOREIGN KEY (site_id) REFERENCES sites(id) ON DELETE CASCADE;
ALTER TABLE public."staff_profiles" ADD CONSTRAINT "staff_profiles_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE public."workers" ADD CONSTRAINT "workers_site_id_fkey" FOREIGN KEY (site_id) REFERENCES sites(id);
ALTER TABLE public."worker_attendance" ADD CONSTRAINT "worker_attendance_worker_id_fkey" FOREIGN KEY (worker_id) REFERENCES workers(id);
ALTER TABLE public."worker_attendance" ADD CONSTRAINT "worker_attendance_site_id_fkey" FOREIGN KEY (site_id) REFERENCES sites(id);
ALTER TABLE public."worker_salary_rates" ADD CONSTRAINT "worker_salary_rates_worker_id_fkey" FOREIGN KEY (worker_id) REFERENCES workers(id);
ALTER TABLE public."worker_salary_rates" ADD CONSTRAINT "worker_salary_rates_site_id_fkey" FOREIGN KEY (site_id) REFERENCES sites(id);
ALTER TABLE public."worker_advances" ADD CONSTRAINT "worker_advances_worker_id_fkey" FOREIGN KEY (worker_id) REFERENCES workers(id);
ALTER TABLE public."worker_advances" ADD CONSTRAINT "worker_advances_site_id_fkey" FOREIGN KEY (site_id) REFERENCES sites(id);
ALTER TABLE public."site_expenses" ADD CONSTRAINT "site_expenses_site_id_fkey" FOREIGN KEY (site_id) REFERENCES sites(id);
ALTER TABLE public."site_cash_ledger" ADD CONSTRAINT "site_cash_ledger_site_id_fkey" FOREIGN KEY (site_id) REFERENCES sites(id);
ALTER TABLE public."worker_salary_payments" ADD CONSTRAINT "worker_salary_payments_worker_id_fkey" FOREIGN KEY (worker_id) REFERENCES workers(id);
ALTER TABLE public."worker_salary_payments" ADD CONSTRAINT "worker_salary_payments_site_id_fkey" FOREIGN KEY (site_id) REFERENCES sites(id);
ALTER TABLE public."worker_attendance" ADD CONSTRAINT "worker_attendance_worker_site_fk" FOREIGN KEY (worker_id, site_id) REFERENCES workers(id, site_id);
ALTER TABLE public."worker_salary_rates" ADD CONSTRAINT "worker_salary_rates_worker_site_fk" FOREIGN KEY (worker_id, site_id) REFERENCES workers(id, site_id);
ALTER TABLE public."worker_advances" ADD CONSTRAINT "worker_advances_worker_site_fk" FOREIGN KEY (worker_id, site_id) REFERENCES workers(id, site_id);
ALTER TABLE public."worker_salary_payments" ADD CONSTRAINT "worker_salary_payments_worker_site_fk" FOREIGN KEY (worker_id, site_id) REFERENCES workers(id, site_id);
ALTER TABLE public."food_grocery" ADD CONSTRAINT "food_grocery_site_id_fkey" FOREIGN KEY (site_id) REFERENCES sites(id);
ALTER TABLE public."worker_food_periods" ADD CONSTRAINT "worker_food_periods_site_id_fkey" FOREIGN KEY (site_id) REFERENCES sites(id);
ALTER TABLE public."worker_food_periods" ADD CONSTRAINT "worker_food_periods_worker_id_fkey" FOREIGN KEY (worker_id) REFERENCES workers(id);
ALTER TABLE public."food_settlements" ADD CONSTRAINT "food_settlements_site_id_fkey" FOREIGN KEY (site_id) REFERENCES sites(id);
ALTER TABLE public."food_settlement_workers" ADD CONSTRAINT "food_settlement_workers_settlement_id_fkey" FOREIGN KEY (settlement_id) REFERENCES food_settlements(id) ON DELETE CASCADE;
ALTER TABLE public."food_settlement_workers" ADD CONSTRAINT "food_settlement_workers_worker_id_fkey" FOREIGN KEY (worker_id) REFERENCES workers(id);
ALTER TABLE public."incharge_accounts" ADD CONSTRAINT "incharge_accounts_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE public."incharge_accounts" ADD CONSTRAINT "incharge_accounts_site_id_fkey" FOREIGN KEY (site_id) REFERENCES sites(id);
ALTER TABLE public."daily_production_entries" ADD CONSTRAINT "dp_site_fk" FOREIGN KEY (site_id) REFERENCES sites(id);
ALTER TABLE public."aaw_billing_document_history" ADD CONSTRAINT "aaw_billing_document_history_document_id_fkey" FOREIGN KEY (document_id) REFERENCES aaw_billing_documents(id);
ALTER TABLE public."aaw_client_payments" ADD CONSTRAINT "aaw_client_payments_document_id_fkey" FOREIGN KEY (document_id) REFERENCES aaw_billing_documents(id) ON DELETE RESTRICT;
ALTER TABLE public."aaw_billing_documents" ADD CONSTRAINT "aaw_billing_documents_site_id_fkey" FOREIGN KEY (site_id) REFERENCES sites(id);
CREATE OR REPLACE FUNCTION public.is_master_admin()
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
select exists (
select 1 from public.staff_profiles
where user_id = (select auth.uid())
and role = 'master'
);
$function$
;
CREATE OR REPLACE FUNCTION public.is_staff_master()
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
SELECT EXISTS (
SELECT 1
FROM public.staff_profiles
WHERE user_id = (SELECT auth.uid())
AND role = 'master'
);
$function$
;
CREATE OR REPLACE FUNCTION public.is_assigned_to_site(p_site_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
SELECT EXISTS (
SELECT 1
FROM public.site_assignments sa
JOIN public.staff_profiles sp
ON sp.user_id = sa.user_id
JOIN auth.users au
ON au.id = sa.user_id
WHERE sa.site_id = p_site_id
AND sa.user_id = (SELECT auth.uid())
AND sp.role = 'incharge'
AND (
au.banned_until IS NULL
OR au.banned_until <= now()
)
);
$function$
;
CREATE OR REPLACE FUNCTION public.has_site_access(p_site_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
SELECT EXISTS (
SELECT 1
FROM public.site_assignments sa
JOIN public.staff_profiles sp
ON sp.user_id = sa.user_id
JOIN auth.users au
ON au.id = sa.user_id
WHERE sa.site_id = p_site_id
AND sa.user_id = (SELECT auth.uid())
AND sp.role = 'incharge'
AND (
au.banned_until IS NULL
OR au.banned_until <= now()
)
);
$function$
;
CREATE OR REPLACE FUNCTION public.can_access_site(p_site_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
SELECT
(SELECT public.is_master_admin())
OR
(SELECT public.is_assigned_to_site(p_site_id));
$function$
;
CREATE OR REPLACE FUNCTION public.daily_production_site_access(p_site_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
select auth.uid() is not null
and (
exists (
select 1
from public.staff_profiles sp
where sp.user_id = auth.uid()
and sp.role = 'master'
)
or exists (
select 1
from public.staff_profiles sp
join public.site_assignments sa
on sa.user_id = sp.user_id
where sp.user_id = auth.uid()
and sp.role = 'incharge'
and sa.site_id = p_site_id
)
);
$function$
;
CREATE OR REPLACE FUNCTION public.validate_worker_salary_payment()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO ''
AS $function$
BEGIN

-- Payment must be positive
IF NEW.amount IS NULL OR NEW.amount <= 0 THEN
RAISE EXCEPTION
'Salary payment amount must be greater than zero';
END IF;

-- Valid salary period
IF NEW.period_start IS NULL
OR NEW.period_end IS NULL
OR NEW.period_start > NEW.period_end THEN
RAISE EXCEPTION
'Invalid salary payment period';
END IF;

-- Required worker and site
IF NEW.worker_id IS NULL OR NEW.site_id IS NULL THEN
RAISE EXCEPTION
'Worker and site are required';
END IF;

-- Prevent payments against a different worker site
IF NOT EXISTS (
SELECT 1
FROM public.workers w
WHERE w.id = NEW.worker_id
AND w.site_id = NEW.site_id
) THEN
RAISE EXCEPTION
'Worker does not belong to selected site';
END IF;

-- Prevent changing the worker/site of existing payment
IF TG_OP = 'UPDATE' THEN
IF NEW.worker_id IS DISTINCT FROM OLD.worker_id
OR NEW.site_id IS DISTINCT FROM OLD.site_id THEN
RAISE EXCEPTION
'Cannot change worker or site of salary payment';
END IF;
END IF;

RETURN NEW;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.aaw_invoice_payable(p jsonb)
RETURNS numeric
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO 'pg_catalog'
AS $function$
DECLARE item jsonb; qty numeric; rate numeric; subtotal numeric:=0; gst numeric; prev numeric; retention numeric; stage text;
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
RETURN round(subtotal+round(subtotal*gst/100,2)-prev-retention,2);
END $function$
;
CREATE OR REPLACE FUNCTION public.rls_auto_enable()
RETURNS event_trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $function$
DECLARE
cmd record;
tbl name;
BEGIN
FOR cmd IN
SELECT *
FROM pg_event_trigger_ddl_commands()
WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
AND object_type IN ('table','partitioned table')
LOOP
IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
BEGIN
SELECT c.relname INTO tbl FROM pg_catalog.pg_class c WHERE c.oid = cmd.objid;
EXECUTE format('alter table if exists %I.%I enable row level security', cmd.schema_name, tbl);
RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
EXCEPTION
WHEN OTHERS THEN
RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
END;
ELSE
RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
END IF;
END LOOP;
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
and a.notes ilike 'FOOD:%'
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
for v_worker in
select
worker_id,
min(payment_type) as payment_type,
sum(
least(end_date,p_end)
- greatest(start_date,p_start) + 1
)::integer as food_days
from public.worker_food_periods
where site_id = p_site_id
and start_date <= p_end
and end_date >= p_start
group by worker_id
order by worker_id
loop
v_index := v_index + 1;

if v_index = v_count then
v_share := v_total - v_allocated;
else
v_share := round(
v_total * v_worker.food_days / v_days, 2
);
end if;

insert into public.food_settlement_workers (
settlement_id,
worker_id,
food_days,
share_amount,
payment_type
)
values (
v_id,
v_worker.worker_id,
v_worker.food_days,
v_share,
v_worker.payment_type
);

v_allocated := v_allocated + v_share;
end loop;

return v_id;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.guard_final_food_grocery()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
begin
-- Serialize changes with settlement finalization
perform pg_catalog.pg_advisory_xact_lock(
pg_catalog.hashtext(
coalesce(old.site_id,new.site_id)::text
)
);

if tg_op in ('UPDATE','DELETE') then
if exists (
select 1
from public.food_settlements s
where s.site_id = old.site_id
and s.status = 'final'
and old.purchase_date
between s.period_start and s.period_end
) then
raise exception
'Grocery is locked by a final food settlement';
end if;
end if;

if tg_op in ('INSERT','UPDATE') then
if exists (
select 1
from public.food_settlements s
where s.site_id = new.site_id
and s.status = 'final'
and new.purchase_date
between s.period_start and s.period_end
) then
raise exception
'Cannot add or move grocery into finalized period';
end if;
end if;

if tg_op = 'DELETE' then
return old;
end if;

return new;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.guard_final_worker_food_period()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
begin
perform pg_catalog.pg_advisory_xact_lock(
pg_catalog.hashtext(
coalesce(old.site_id,new.site_id)::text
)
);

if tg_op in ('UPDATE','DELETE') then
if exists (
select 1
from public.food_settlements s
where s.site_id = old.site_id
and s.status = 'final'
and old.start_date <= s.period_end
and old.end_date >= s.period_start
) then
raise exception
'Food period is locked by final settlement';
end if;
end if;

if tg_op in ('INSERT','UPDATE') then
if exists (
select 1
from public.food_settlements s
where s.site_id = new.site_id
and s.status = 'final'
and new.start_date <= s.period_end
and new.end_date >= s.period_start
) then
raise exception
'Cannot add food period overlapping final settlement';
end if;
end if;

if tg_op = 'DELETE' then
return old;
end if;

return new;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.guard_final_settlement()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO ''
AS $function$
begin
if old.status = 'final' then
raise exception
'Final settlement cannot be edited or deleted';
end if;

if tg_op = 'DELETE' then
return old;
end if;

return new;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.guard_final_settlement_worker()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO ''
AS $function$
begin
if exists (
select 1
from public.food_settlements s
where s.id = old.settlement_id
and s.status = 'final'
) then
raise exception
'Final worker food share cannot be changed';
end if;

if tg_op = 'DELETE' then
return old;
end if;

return new;
end;
$function$
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
if coalesce(new.notes,'') ilike 'FOOD:%'
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

IF v_role IS DISTINCT FROM 'master' AND NOT (v_role = 'incharge' AND EXISTS (SELECT 1 FROM public.site_assignments sa WHERE sa.user_id = auth.uid() AND sa.site_id = NEW.site_id)) THEN
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
CREATE OR REPLACE FUNCTION public.dp_audit_changes_v525()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE op text;
BEGIN
IF TG_OP = 'INSERT' THEN
INSERT INTO public.daily_production_audit(entry_id,site_id,action,changed_by,old_record,new_record)
VALUES (NEW.id,NEW.site_id,'INSERT',auth.uid(),NULL,to_jsonb(NEW));
RETURN NEW;
END IF;
IF to_jsonb(NEW) IS DISTINCT FROM to_jsonb(OLD) THEN
op := CASE WHEN NEW.is_deleted AND NOT OLD.is_deleted THEN 'ARCHIVE' ELSE 'UPDATE' END;
INSERT INTO public.daily_production_audit(entry_id,site_id,action,changed_by,old_record,new_record)
VALUES (NEW.id,NEW.site_id,op,auth.uid(),to_jsonb(OLD),to_jsonb(NEW));
END IF;
RETURN NEW;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.v519_salary_guard_check()
RETURNS TABLE(test_name text, result text, detail text)
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
v_uid uuid := auth.uid();
w record;
d record;
msg text;
from_date date;
to_date date;
BEGIN
IF v_uid IS NULL OR NOT EXISTS (SELECT 1 FROM public.staff_profiles WHERE user_id=v_uid AND role='master') THEN
RETURN QUERY SELECT 'Authentication'::text,'BLOCKED'::text,'Master Admin login required'::text;
RETURN;
END IF;
SELECT id,site_id,joining_date INTO w FROM public.workers
WHERE COALESCE(is_deleted,false)=false AND COALESCE(is_active,true)=true
ORDER BY created_at DESC LIMIT 1;
IF NOT FOUND THEN
RETURN QUERY SELECT 'Negative payment'::text,'SKIPPED'::text,'No active worker visible'::text;
RETURN QUERY SELECT 'Overpayment'::text,'SKIPPED'::text,'No active worker visible'::text;
ELSE
from_date:=COALESCE(w.joining_date,CURRENT_DATE);
to_date:=GREATEST(from_date,CURRENT_DATE);
BEGIN
INSERT INTO public.worker_salary_payments(worker_id,site_id,payment_date,period_start,period_end,amount,notes)
VALUES(w.id,w.site_id,CURRENT_DATE,from_date,to_date,-100,'DIAGNOSTIC ROLLBACK');
RAISE EXCEPTION 'TEST_INSERT_ACCEPTED';
EXCEPTION WHEN OTHERS THEN
GET STACKED DIAGNOSTICS msg=MESSAGE_TEXT;
IF msg='TEST_INSERT_ACCEPTED' THEN
RETURN QUERY SELECT 'Negative payment'::text,'FAIL'::text,'Accepted, but test rolled back'::text;
ELSIF msg ILIKE '%amount%' OR msg ILIKE '%positive%' OR msg ILIKE '%negative%' THEN
RETURN QUERY SELECT 'Negative payment'::text,'PASS'::text,msg;
ELSE
RETURN QUERY SELECT 'Negative payment'::text,'INCONCLUSIVE'::text,msg;
END IF;
END;
BEGIN
INSERT INTO public.worker_salary_payments(worker_id,site_id,payment_date,period_start,period_end,amount,notes)
VALUES(w.id,w.site_id,CURRENT_DATE,from_date,to_date,999999999,'DIAGNOSTIC ROLLBACK');
RAISE EXCEPTION 'TEST_INSERT_ACCEPTED';
EXCEPTION WHEN OTHERS THEN
GET STACKED DIAGNOSTICS msg=MESSAGE_TEXT;
IF msg='TEST_INSERT_ACCEPTED' THEN
RETURN QUERY SELECT 'Overpayment'::text,'FAIL'::text,'Accepted, but test rolled back'::text;
ELSIF msg ILIKE '%overpay%' OR msg ILIKE '%exceed%' OR msg ILIKE '%balance%' OR msg ILIKE '%outstanding%' OR msg ILIKE '%payable%' OR msg ILIKE '%available rs%' OR msg ILIKE '%requested rs%' THEN
RETURN QUERY SELECT 'Overpayment'::text,'PASS'::text,msg;
ELSE
RETURN QUERY SELECT 'Overpayment'::text,'INCONCLUSIVE'::text,msg;
END IF;
END;
END IF;
SELECT id,site_id INTO d FROM public.workers WHERE is_deleted IS TRUE LIMIT 1;
IF NOT FOUND THEN
RETURN QUERY SELECT 'Deleted worker'::text,'SKIPPED'::text,'No deleted worker visible'::text;
ELSE
BEGIN
INSERT INTO public.worker_salary_payments(worker_id,site_id,payment_date,period_start,period_end,amount,notes)
VALUES(d.id,d.site_id,CURRENT_DATE,CURRENT_DATE,CURRENT_DATE,1,'DIAGNOSTIC ROLLBACK');
RAISE EXCEPTION 'TEST_INSERT_ACCEPTED';
EXCEPTION WHEN OTHERS THEN
GET STACKED DIAGNOSTICS msg=MESSAGE_TEXT;
IF msg='TEST_INSERT_ACCEPTED' THEN
RETURN QUERY SELECT 'Deleted worker'::text,'FAIL'::text,'Accepted, but test rolled back'::text;
ELSIF msg ILIKE '%delet%' OR msg ILIKE '%inactive%' OR msg ILIKE '%archiv%' THEN
RETURN QUERY SELECT 'Deleted worker'::text,'PASS'::text,msg;
ELSE
RETURN QUERY SELECT 'Deleted worker'::text,'INCONCLUSIVE'::text,msg;
END IF;
END;
END IF;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.aaw_billing_audit_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
begin
insert into public.aaw_billing_document_history(document_id,edited_by,previous_payload,previous_number)
values(old.id,auth.uid(),old.payload,old.document_number);
new.created_by=old.created_by;
new.created_at=old.created_at;
new.updated_at=now();
return new;
end $function$
;
CREATE OR REPLACE FUNCTION public.aaw_payment_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE doc record; already numeric;
BEGIN
IF auth.uid() IS NULL OR NEW.created_by IS DISTINCT FROM auth.uid() OR NOT EXISTS(SELECT 1 FROM public.staff_profiles WHERE user_id=auth.uid() AND role='master') THEN
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
CREATE OR REPLACE FUNCTION public.aaw_invoice_edit_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE paid numeric;
BEGIN
IF OLD.document_type='invoice' THEN
SELECT COALESCE(sum(amount),0) INTO paid FROM public.aaw_client_payments WHERE document_id=OLD.id;
IF paid>0 AND (NEW.document_type<>'invoice' OR public.aaw_invoice_payable(NEW.payload)<paid) THEN
RAISE EXCEPTION 'Invoice edit would exceed its recorded payments';
END IF;
END IF;
RETURN NEW;
END $function$
;
CREATE OR REPLACE FUNCTION public.get_final_food_deductions(p_site_id uuid, p_start date, p_end date)
RETURNS TABLE(worker_id uuid, food_days bigint, deduction_amount numeric)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
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
CREATE TRIGGER trg_guard_final_food_grocery BEFORE INSERT OR DELETE OR UPDATE ON public.food_grocery FOR EACH ROW EXECUTE FUNCTION guard_final_food_grocery();
CREATE TRIGGER trg_guard_final_worker_food_period BEFORE INSERT OR DELETE OR UPDATE ON public.worker_food_periods FOR EACH ROW EXECUTE FUNCTION guard_final_worker_food_period();
CREATE TRIGGER trg_guard_final_settlement BEFORE DELETE OR UPDATE ON public.food_settlements FOR EACH ROW EXECUTE FUNCTION guard_final_settlement();
CREATE TRIGGER trg_guard_final_settlement_worker BEFORE DELETE OR UPDATE ON public.food_settlement_workers FOR EACH ROW EXECUTE FUNCTION guard_final_settlement_worker();
CREATE TRIGGER trg_guard_manual_food_advance BEFORE INSERT OR UPDATE ON public.worker_advances FOR EACH ROW EXECUTE FUNCTION guard_manual_food_advance();
CREATE TRIGGER trg_v515_salary_payment_lock BEFORE INSERT OR UPDATE ON public.worker_salary_payments FOR EACH ROW EXECUTE FUNCTION v515_salary_payment_lock();
CREATE TRIGGER trg_validate_worker_salary_payment BEFORE INSERT OR UPDATE ON public.worker_salary_payments FOR EACH ROW EXECUTE FUNCTION validate_worker_salary_payment();
CREATE TRIGGER trg_dp_audit_v525 AFTER INSERT OR UPDATE ON public.daily_production_entries FOR EACH ROW EXECUTE FUNCTION dp_audit_changes_v525();
CREATE TRIGGER aaw_billing_audit_update_trigger BEFORE UPDATE ON public.aaw_billing_documents FOR EACH ROW EXECUTE FUNCTION aaw_billing_audit_update();
CREATE TRIGGER aaw_payment_guard_trigger BEFORE INSERT ON public.aaw_client_payments FOR EACH ROW EXECUTE FUNCTION aaw_payment_guard();
CREATE TRIGGER aaw_invoice_edit_guard_trigger BEFORE UPDATE ON public.aaw_billing_documents FOR EACH ROW EXECUTE FUNCTION aaw_invoice_edit_guard();
ALTER TABLE public."sites" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."site_assignments" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."staff_profiles" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."food_settlement_workers" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."food_settlements" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."incharge_accounts" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."aaw_billing_document_history" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."aaw_client_payments" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."aaw_billing_documents" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."daily_production_audit" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."daily_production_entries" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."food_grocery" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."worker_food_periods" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."worker_salary_payments" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."worker_salary_rates" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."worker_advances" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."worker_attendance" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."site_cash_ledger" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."site_expenses" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."workers" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Read own profile or master" ON public."staff_profiles" AS PERMISSIVE FOR SELECT TO "authenticated" USING (((user_id = ( SELECT auth.uid() AS uid)) OR is_master_admin()));
CREATE POLICY "Master manages sites" ON public."sites" AS PERMISSIVE FOR ALL TO "authenticated" USING (is_master_admin()) WITH CHECK (is_master_admin());
CREATE POLICY "Master manages assignments" ON public."site_assignments" AS PERMISSIVE FOR ALL TO "authenticated" USING (is_master_admin()) WITH CHECK (is_master_admin());
CREATE POLICY "Incharge reads assigned sites" ON public."sites" AS PERMISSIVE FOR SELECT TO "authenticated" USING (is_assigned_to_site(id));
CREATE POLICY "Incharge reads own assignments" ON public."site_assignments" AS PERMISSIVE FOR SELECT TO "authenticated" USING ((user_id = ( SELECT auth.uid() AS uid)));
CREATE POLICY "workers_select" ON public."workers" AS PERMISSIVE FOR SELECT TO "authenticated" USING ((is_master_admin() OR has_site_access(site_id)));
CREATE POLICY "workers_insert" ON public."workers" AS PERMISSIVE FOR INSERT TO "authenticated" WITH CHECK ((is_master_admin() OR has_site_access(site_id)));
CREATE POLICY "workers_update" ON public."workers" AS PERMISSIVE FOR UPDATE TO "authenticated" USING ((is_master_admin() OR has_site_access(site_id))) WITH CHECK ((is_master_admin() OR has_site_access(site_id)));
CREATE POLICY "workers_delete" ON public."workers" AS PERMISSIVE FOR DELETE TO "authenticated" USING (is_master_admin());
CREATE POLICY "site_read" ON public."worker_attendance" AS PERMISSIVE FOR SELECT TO "authenticated" USING (can_access_site(site_id));
CREATE POLICY "incharge_insert" ON public."worker_advances" AS PERMISSIVE FOR INSERT TO "authenticated" WITH CHECK (is_assigned_to_site(site_id));
CREATE POLICY "master_write" ON public."worker_attendance" AS PERMISSIVE FOR ALL TO "authenticated" USING (( SELECT is_master_admin() AS is_master_admin)) WITH CHECK (( SELECT is_master_admin() AS is_master_admin));
CREATE POLICY "site_read" ON public."worker_salary_rates" AS PERMISSIVE FOR SELECT TO "authenticated" USING (can_access_site(site_id));
CREATE POLICY "master_write" ON public."worker_salary_rates" AS PERMISSIVE FOR ALL TO "authenticated" USING (( SELECT is_master_admin() AS is_master_admin)) WITH CHECK (( SELECT is_master_admin() AS is_master_admin));
CREATE POLICY "site_read" ON public."worker_advances" AS PERMISSIVE FOR SELECT TO "authenticated" USING (can_access_site(site_id));
CREATE POLICY "master_write" ON public."worker_advances" AS PERMISSIVE FOR ALL TO "authenticated" USING (( SELECT is_master_admin() AS is_master_admin)) WITH CHECK (( SELECT is_master_admin() AS is_master_admin));
CREATE POLICY "site_read" ON public."site_expenses" AS PERMISSIVE FOR SELECT TO "authenticated" USING (can_access_site(site_id));
CREATE POLICY "incharge_update" ON public."worker_advances" AS PERMISSIVE FOR UPDATE TO "authenticated" USING (is_assigned_to_site(site_id)) WITH CHECK (is_assigned_to_site(site_id));
CREATE POLICY "master_write" ON public."site_expenses" AS PERMISSIVE FOR ALL TO "authenticated" USING (( SELECT is_master_admin() AS is_master_admin)) WITH CHECK (( SELECT is_master_admin() AS is_master_admin));
CREATE POLICY "site_read" ON public."site_cash_ledger" AS PERMISSIVE FOR SELECT TO "authenticated" USING (can_access_site(site_id));
CREATE POLICY "master_write" ON public."site_cash_ledger" AS PERMISSIVE FOR ALL TO "authenticated" USING (( SELECT is_master_admin() AS is_master_admin)) WITH CHECK (( SELECT is_master_admin() AS is_master_admin));
CREATE POLICY "site_read" ON public."worker_salary_payments" AS PERMISSIVE FOR SELECT TO "authenticated" USING (can_access_site(site_id));
CREATE POLICY "master_write" ON public."worker_salary_payments" AS PERMISSIVE FOR ALL TO "authenticated" USING (( SELECT is_master_admin() AS is_master_admin)) WITH CHECK (( SELECT is_master_admin() AS is_master_admin));
CREATE POLICY "incharge_insert" ON public."worker_attendance" AS PERMISSIVE FOR INSERT TO "authenticated" WITH CHECK (is_assigned_to_site(site_id));
CREATE POLICY "incharge_update" ON public."worker_attendance" AS PERMISSIVE FOR UPDATE TO "authenticated" USING (is_assigned_to_site(site_id)) WITH CHECK (is_assigned_to_site(site_id));
CREATE POLICY "incharge_insert" ON public."site_expenses" AS PERMISSIVE FOR INSERT TO "authenticated" WITH CHECK (is_assigned_to_site(site_id));
CREATE POLICY "incharge_update" ON public."site_expenses" AS PERMISSIVE FOR UPDATE TO "authenticated" USING (is_assigned_to_site(site_id)) WITH CHECK (is_assigned_to_site(site_id));
CREATE POLICY "master_update_workers" ON public."workers" AS PERMISSIVE FOR UPDATE TO "authenticated" USING (( SELECT is_master_admin() AS is_master_admin)) WITH CHECK (( SELECT is_master_admin() AS is_master_admin));
CREATE POLICY "food_grocery_select_v59" ON public."food_grocery" AS PERMISSIVE FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM sites s
  WHERE (s.id = food_grocery.site_id))));
CREATE POLICY "food_grocery_insert_v59" ON public."food_grocery" AS PERMISSIVE FOR INSERT TO "authenticated" WITH CHECK ((EXISTS ( SELECT 1
   FROM sites s
  WHERE (s.id = food_grocery.site_id))));
CREATE POLICY "food_grocery_update_v59" ON public."food_grocery" AS PERMISSIVE FOR UPDATE TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM sites s
  WHERE (s.id = food_grocery.site_id)))) WITH CHECK ((EXISTS ( SELECT 1
   FROM sites s
  WHERE (s.id = food_grocery.site_id))));
CREATE POLICY "food_grocery_delete_v59" ON public."food_grocery" AS PERMISSIVE FOR DELETE TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM sites s
  WHERE (s.id = food_grocery.site_id))));
CREATE POLICY "food_period_select_v59" ON public."worker_food_periods" AS PERMISSIVE FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM sites s
  WHERE (s.id = worker_food_periods.site_id))));
CREATE POLICY "food_period_insert_v59" ON public."worker_food_periods" AS PERMISSIVE FOR INSERT TO "authenticated" WITH CHECK (((EXISTS ( SELECT 1
   FROM sites s
  WHERE (s.id = worker_food_periods.site_id))) AND (EXISTS ( SELECT 1
   FROM workers w
  WHERE ((w.id = worker_food_periods.worker_id) AND (w.site_id = w.site_id))))));
CREATE POLICY "food_period_update_v59" ON public."worker_food_periods" AS PERMISSIVE FOR UPDATE TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM sites s
  WHERE (s.id = worker_food_periods.site_id)))) WITH CHECK (((EXISTS ( SELECT 1
   FROM sites s
  WHERE (s.id = worker_food_periods.site_id))) AND (EXISTS ( SELECT 1
   FROM workers w
  WHERE ((w.id = worker_food_periods.worker_id) AND (w.site_id = w.site_id))))));
CREATE POLICY "food_period_delete_v59" ON public."worker_food_periods" AS PERMISSIVE FOR DELETE TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM sites s
  WHERE (s.id = worker_food_periods.site_id))));
CREATE POLICY "food_settlements_read_v59" ON public."food_settlements" AS PERMISSIVE FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM sites s
  WHERE (s.id = food_settlements.site_id))));
CREATE POLICY "food_settlement_workers_read_v59" ON public."food_settlement_workers" AS PERMISSIVE FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM food_settlements fs
  WHERE (fs.id = food_settlement_workers.settlement_id))));
CREATE POLICY "incharge_accounts_master_read" ON public."incharge_accounts" AS PERMISSIVE FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM staff_profiles p
  WHERE ((p.user_id = auth.uid()) AND (p.role = 'master'::text)))));
CREATE POLICY "staff_profiles_secure_read" ON public."staff_profiles" AS PERMISSIVE FOR SELECT TO "authenticated" USING (((user_id = ( SELECT auth.uid() AS uid)) OR ( SELECT is_staff_master() AS is_staff_master)));
CREATE POLICY "v59_food_grocery_select" ON public."food_grocery" AS PERMISSIVE FOR SELECT TO "authenticated" USING (can_access_site(site_id));
CREATE POLICY "v59_food_grocery_insert" ON public."food_grocery" AS PERMISSIVE FOR INSERT TO "authenticated" WITH CHECK (can_access_site(site_id));
CREATE POLICY "v59_food_grocery_update" ON public."food_grocery" AS PERMISSIVE FOR UPDATE TO "authenticated" USING (can_access_site(site_id)) WITH CHECK (can_access_site(site_id));
CREATE POLICY "v59_food_grocery_delete" ON public."food_grocery" AS PERMISSIVE FOR DELETE TO "authenticated" USING (is_master_admin());
CREATE POLICY "v59_worker_food_periods_select" ON public."worker_food_periods" AS PERMISSIVE FOR SELECT TO "authenticated" USING (can_access_site(site_id));
CREATE POLICY "v59_worker_food_periods_insert" ON public."worker_food_periods" AS PERMISSIVE FOR INSERT TO "authenticated" WITH CHECK (can_access_site(site_id));
CREATE POLICY "v59_worker_food_periods_update" ON public."worker_food_periods" AS PERMISSIVE FOR UPDATE TO "authenticated" USING (can_access_site(site_id)) WITH CHECK (can_access_site(site_id));
CREATE POLICY "v59_worker_food_periods_delete" ON public."worker_food_periods" AS PERMISSIVE FOR DELETE TO "authenticated" USING (is_master_admin());
CREATE POLICY "dp_select" ON public."daily_production_entries" AS PERMISSIVE FOR SELECT TO "authenticated" USING (daily_production_site_access(site_id));
CREATE POLICY "dp_insert" ON public."daily_production_entries" AS PERMISSIVE FOR INSERT TO "authenticated" WITH CHECK ((daily_production_site_access(site_id) AND (created_by = auth.uid())));
CREATE POLICY "dp_update" ON public."daily_production_entries" AS PERMISSIVE FOR UPDATE TO "authenticated" USING (daily_production_site_access(site_id)) WITH CHECK (daily_production_site_access(site_id));
CREATE POLICY "dp_audit_read_v525" ON public."daily_production_audit" AS PERMISSIVE FOR SELECT TO "authenticated" USING (((EXISTS ( SELECT 1
   FROM staff_profiles p
  WHERE ((p.user_id = ( SELECT auth.uid() AS uid)) AND (p.role = 'master'::text)))) OR (EXISTS ( SELECT 1
   FROM (staff_profiles p
     JOIN site_assignments sa ON ((sa.user_id = p.user_id)))
  WHERE ((p.user_id = ( SELECT auth.uid() AS uid)) AND (p.role = 'incharge'::text) AND (sa.site_id = daily_production_audit.site_id))))));
CREATE POLICY "aaw_billing_master_select" ON public."aaw_billing_documents" AS PERMISSIVE FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM staff_profiles sp
  WHERE ((sp.user_id = auth.uid()) AND (sp.role = 'master'::text)))));
CREATE POLICY "aaw_billing_master_insert" ON public."aaw_billing_documents" AS PERMISSIVE FOR INSERT TO "authenticated" WITH CHECK (((created_by = auth.uid()) AND (updated_by = auth.uid()) AND (EXISTS ( SELECT 1
   FROM staff_profiles sp
  WHERE ((sp.user_id = auth.uid()) AND (sp.role = 'master'::text))))));
CREATE POLICY "aaw_billing_master_update" ON public."aaw_billing_documents" AS PERMISSIVE FOR UPDATE TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM staff_profiles sp
  WHERE ((sp.user_id = auth.uid()) AND (sp.role = 'master'::text))))) WITH CHECK (((updated_by = auth.uid()) AND (EXISTS ( SELECT 1
   FROM staff_profiles sp
  WHERE ((sp.user_id = auth.uid()) AND (sp.role = 'master'::text))))));
CREATE POLICY "aaw_billing_history_master_select" ON public."aaw_billing_document_history" AS PERMISSIVE FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM staff_profiles sp
  WHERE ((sp.user_id = auth.uid()) AND (sp.role = 'master'::text)))));
CREATE POLICY "aaw_client_payments_master_select" ON public."aaw_client_payments" AS PERMISSIVE FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM staff_profiles s
  WHERE ((s.user_id = auth.uid()) AND (s.role = 'master'::text)))));
CREATE POLICY "aaw_client_payments_master_insert" ON public."aaw_client_payments" AS PERMISSIVE FOR INSERT TO "authenticated" WITH CHECK (((created_by = auth.uid()) AND (EXISTS ( SELECT 1
   FROM staff_profiles s
  WHERE ((s.user_id = auth.uid()) AND (s.role = 'master'::text)))) AND (EXISTS ( SELECT 1
   FROM aaw_billing_documents d
  WHERE ((d.id = aaw_client_payments.document_id) AND (d.document_type = 'invoice'::text))))));
CREATE POLICY "aaw_salary_incharge_insert" ON public."worker_salary_payments" AS PERMISSIVE FOR INSERT TO "authenticated" WITH CHECK (((EXISTS ( SELECT 1
   FROM staff_profiles sp
  WHERE ((sp.user_id = auth.uid()) AND (sp.role = 'incharge'::text)))) AND (EXISTS ( SELECT 1
   FROM site_assignments sa
  WHERE ((sa.user_id = auth.uid()) AND (sa.site_id = worker_salary_payments.site_id)))) AND (EXISTS ( SELECT 1
   FROM workers w
  WHERE ((w.id = worker_salary_payments.worker_id) AND (w.site_id = worker_salary_payments.site_id) AND (COALESCE(w.is_deleted, false) = false))))));
GRANT USAGE ON SCHEMA public,auth TO anon,authenticated;
GRANT SELECT,INSERT,UPDATE,DELETE ON ALL TABLES IN SCHEMA public TO anon,authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA auth TO anon,authenticated;
