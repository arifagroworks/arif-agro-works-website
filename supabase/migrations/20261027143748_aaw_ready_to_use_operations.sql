-- Additive operational upgrade. Existing payments, attendance, workers and site
-- records are retained. Unknown historical cash ownership remains unassigned.
ALTER TABLE public.workers ADD COLUMN IF NOT EXISTS salary_basis text NOT NULL DEFAULT 'daily' CHECK (salary_basis IN ('daily','monthly'));
ALTER TABLE public.workers ADD COLUMN IF NOT EXISTS monthly_salary numeric(14,2) CHECK (monthly_salary>=0);
ALTER TABLE public.workers ADD COLUMN IF NOT EXISTS person_id uuid;
UPDATE public.workers SET person_id=id WHERE person_id IS NULL;
ALTER TABLE public.workers ALTER COLUMN person_id SET DEFAULT gen_random_uuid();
ALTER TABLE public.workers ALTER COLUMN person_id SET NOT NULL;
ALTER TABLE public.worker_salary_rates ADD COLUMN IF NOT EXISTS salary_basis text NOT NULL DEFAULT 'daily' CHECK (salary_basis IN ('daily','monthly'));
ALTER TABLE public.worker_salary_rates ADD COLUMN IF NOT EXISTS monthly_salary numeric(14,2) CHECK (monthly_salary>=0);

CREATE TABLE public.aaw_operational_audit(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 table_name text NOT NULL,row_id text,site_id uuid,actor_id uuid,
 operation text NOT NULL,old_values jsonb,new_values jsonb,changed_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.aaw_operational_audit ENABLE ROW LEVEL SECURITY;
CREATE POLICY operational_audit_read ON public.aaw_operational_audit FOR SELECT TO authenticated
 USING (public.is_master_admin() OR (actor_id=auth.uid() AND public.can_access_site(site_id)));
REVOKE ALL ON public.aaw_operational_audit FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.aaw_operational_audit TO authenticated;
REVOKE INSERT,UPDATE,DELETE ON public.aaw_operational_audit FROM anon,authenticated;
CREATE FUNCTION public.aaw_capture_operational_audit() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE oldj jsonb; newj jsonb; recordj jsonb;
BEGIN
 IF TG_OP<>'INSERT' THEN oldj:=to_jsonb(OLD); END IF;
 IF TG_OP<>'DELETE' THEN newj:=to_jsonb(NEW); END IF;
 recordj:=coalesce(newj,oldj);
 INSERT INTO public.aaw_operational_audit(table_name,row_id,site_id,actor_id,operation,old_values,new_values)
 VALUES(TG_TABLE_NAME,coalesce(recordj->>'id',recordj->>'worker_id',recordj->>'user_id'),nullif(recordj->>'site_id','')::uuid,auth.uid(),TG_OP,oldj,newj);
 RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
END $$;
REVOKE EXECUTE ON FUNCTION public.aaw_capture_operational_audit() FROM PUBLIC,anon,authenticated;
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['workers','worker_salary_rates','worker_attendance','worker_advances','worker_salary_payments','site_expenses','site_cash_ledger','food_grocery','worker_food_periods','site_assignments'] LOOP
 EXECUTE format('CREATE TRIGGER aaw_operational_audit AFTER INSERT OR UPDATE OR DELETE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.aaw_capture_operational_audit()',t);
 END LOOP;
END $$;

CREATE FUNCTION public.aaw_session_context() RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE profile record; enabled boolean;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Login required'; END IF;
 SELECT p.role,p.full_name,u.banned_until INTO profile FROM public.staff_profiles p JOIN auth.users u ON u.id=p.user_id WHERE p.user_id=auth.uid();
 IF NOT FOUND OR profile.role NOT IN ('master','incharge') THEN RAISE EXCEPTION 'Staff account required'; END IF;
 enabled:=profile.banned_until IS NULL OR profile.banned_until<=now();
 RETURN jsonb_build_object('user_id',auth.uid(),'role',profile.role,'full_name',profile.full_name,'enabled',enabled);
END $$;
REVOKE EXECUTE ON FUNCTION public.aaw_session_context() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.aaw_session_context() TO authenticated;

-- Rate lookup is evaluated for each attendance date; monthly division stays
-- numeric throughout and is rounded only when the full wage total is known.
CREATE FUNCTION public.aaw_effective_rate(p_worker uuid,p_day date)
RETURNS TABLE(daily_rate numeric,overtime_rate numeric) LANGUAGE sql STABLE SET search_path='' AS $$
 SELECT CASE WHEN coalesce(r.salary_basis,w.salary_basis)='monthly'
             THEN coalesce(r.monthly_salary,w.monthly_salary,0)/30
             ELSE coalesce(r.daily_rate,w.daily_wage,0) END,
        coalesce(r.overtime_hourly_rate,w.overtime_rate,0)
 FROM public.workers w LEFT JOIN LATERAL (
  SELECT sr.* FROM public.worker_salary_rates sr WHERE sr.worker_id=w.id AND sr.site_id=w.site_id AND sr.effective_from<=p_day
  ORDER BY sr.effective_from DESC LIMIT 1
 ) r ON true WHERE w.id=p_worker;
$$;
REVOKE EXECUTE ON FUNCTION public.aaw_effective_rate(uuid,date) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.aaw_effective_rate(uuid,date) TO authenticated;

CREATE FUNCTION public.aaw_set_worker_rate(p_worker uuid,p_site uuid,p_basis text,p_monthly numeric,p_daily numeric,p_ot numeric,p_effective date)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE w public.workers; result uuid;
BEGIN
 IF NOT public.can_access_site(p_site) THEN RAISE EXCEPTION 'Site access denied'; END IF;
 SELECT * INTO w FROM public.workers WHERE id=p_worker AND site_id=p_site AND NOT coalesce(is_deleted,false) FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Worker not found at this site'; END IF;
 IF p_basis NOT IN ('monthly','daily') OR p_effective IS NULL OR p_ot IS NULL OR p_ot<0
    OR (p_basis='monthly' AND (p_monthly IS NULL OR p_monthly<0)) OR (p_basis='daily' AND (p_daily IS NULL OR p_daily<0)) THEN RAISE EXCEPTION 'Invalid salary rate'; END IF;
 IF EXISTS(SELECT 1 FROM public.worker_salary_payments WHERE worker_id=p_worker AND period_end>=p_effective) THEN
   RAISE EXCEPTION 'Rate date overlaps a paid salary period; choose a later effective date';
 END IF;
 INSERT INTO public.worker_salary_rates(worker_id,site_id,effective_from,daily_rate,overtime_hourly_rate,salary_basis,monthly_salary)
 VALUES(p_worker,p_site,p_effective,CASE WHEN p_basis='monthly' THEN round(p_monthly/30,2) ELSE p_daily END,p_ot,p_basis,CASE WHEN p_basis='monthly' THEN p_monthly ELSE NULL END)
 ON CONFLICT(worker_id,site_id,effective_from) DO UPDATE SET daily_rate=excluded.daily_rate,overtime_hourly_rate=excluded.overtime_hourly_rate,salary_basis=excluded.salary_basis,monthly_salary=excluded.monthly_salary
 RETURNING id INTO result;
 -- Preserve fallback rates for old dates. Attendance after the effective date
 -- resolves the history row rather than rewriting the worker's old base wage.
 RETURN result;
END $$;
REVOKE EXECUTE ON FUNCTION public.aaw_set_worker_rate(uuid,uuid,text,numeric,numeric,numeric,date) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.aaw_set_worker_rate(uuid,uuid,text,numeric,numeric,numeric,date) TO authenticated;

-- Historical worker identity is immutable. A transfer creates a new site record
-- with the same person_id and leaves prior attendance/payments at the old site.
CREATE FUNCTION public.aaw_guard_worker_identity() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
 IF TG_OP='UPDATE' AND NEW.site_id IS DISTINCT FROM OLD.site_id THEN RAISE EXCEPTION 'Use Worker Transfer to change site and retain history'; END IF;
 IF TG_OP='UPDATE' AND NEW.person_id IS DISTINCT FROM OLD.person_id THEN RAISE EXCEPTION 'Worker identity cannot be changed'; END IF;
 IF NEW.salary_basis='monthly' AND NEW.monthly_salary IS NULL THEN RAISE EXCEPTION 'Monthly salary is required'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER aaw_worker_identity BEFORE INSERT OR UPDATE ON public.workers FOR EACH ROW EXECUTE FUNCTION public.aaw_guard_worker_identity();
REVOKE EXECUTE ON FUNCTION public.aaw_guard_worker_identity() FROM PUBLIC,anon,authenticated;

-- Per-incharge cash ledger. Existing unassigned entries remain Master-visible.
ALTER TABLE public.site_cash_ledger ADD COLUMN incharge_id uuid REFERENCES auth.users(id);
ALTER TABLE public.site_cash_ledger ADD COLUMN source_table text;
ALTER TABLE public.site_cash_ledger ADD COLUMN source_id uuid;
ALTER TABLE public.site_cash_ledger ADD COLUMN is_archived boolean NOT NULL DEFAULT false;
CREATE UNIQUE INDEX aaw_cash_source_unique ON public.site_cash_ledger(source_table,source_id) WHERE source_id IS NOT NULL;
DROP POLICY IF EXISTS site_read ON public.site_cash_ledger;
DROP POLICY IF EXISTS master_write ON public.site_cash_ledger;
CREATE POLICY cash_owner_read ON public.site_cash_ledger FOR SELECT TO authenticated
 USING(public.is_master_admin() OR (incharge_id=auth.uid() AND public.can_access_site(site_id)));
CREATE POLICY cash_owner_insert ON public.site_cash_ledger FOR INSERT TO authenticated
 WITH CHECK(source_table IS NULL AND (public.is_master_admin() OR (incharge_id=auth.uid() AND public.can_access_site(site_id))));
CREATE POLICY cash_owner_update ON public.site_cash_ledger FOR UPDATE TO authenticated
 USING(source_table IS NULL AND (public.is_master_admin() OR (incharge_id=auth.uid() AND public.can_access_site(site_id))))
 WITH CHECK(source_table IS NULL AND (public.is_master_admin() OR (incharge_id=auth.uid() AND public.can_access_site(site_id))));
CREATE FUNCTION public.aaw_validate_cash_owner() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF TG_OP='UPDATE' AND NEW.incharge_id IS NOT DISTINCT FROM OLD.incharge_id AND NEW.site_id=OLD.site_id THEN RETURN NEW; END IF;
 IF NEW.incharge_id IS NULL AND TG_OP='UPDATE' AND OLD.incharge_id IS NULL AND public.is_master_admin() THEN RETURN NEW; END IF;
 IF NEW.incharge_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.staff_profiles p JOIN public.site_assignments sa ON sa.user_id=p.user_id
   WHERE p.user_id=NEW.incharge_id AND p.role='incharge' AND sa.site_id=NEW.site_id) THEN RAISE EXCEPTION 'Select an Incharge assigned to this site'; END IF;
 IF TG_OP='UPDATE' AND NOT public.is_master_admin() AND (NEW.incharge_id IS DISTINCT FROM OLD.incharge_id OR NEW.site_id IS DISTINCT FROM OLD.site_id) THEN RAISE EXCEPTION 'Cash owner/site cannot be changed'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER aaw_cash_owner BEFORE INSERT OR UPDATE ON public.site_cash_ledger FOR EACH ROW EXECUTE FUNCTION public.aaw_validate_cash_owner();
REVOKE EXECUTE ON FUNCTION public.aaw_validate_cash_owner() FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.aaw_cash_movement_sync() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE j jsonb; cash_owner uuid; existing public.site_cash_ledger; moved_date date;
BEGIN
 j:=CASE WHEN TG_OP='DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
 SELECT * INTO existing FROM public.site_cash_ledger WHERE source_table=TG_TABLE_NAME AND source_id=(j->>'id')::uuid FOR UPDATE;
 cash_owner:=existing.incharge_id;
 IF cash_owner IS NULL AND EXISTS(SELECT 1 FROM public.staff_profiles WHERE user_id=auth.uid() AND role='incharge') THEN cash_owner:=auth.uid(); END IF;
 IF (TG_TABLE_NAME='food_grocery' AND j->>'linked_expense_id' IS NOT NULL) OR (TG_TABLE_NAME='worker_advances' AND btrim(j->>'notes') ILIKE 'FOOD:%') THEN
  IF existing.id IS NOT NULL THEN UPDATE public.site_cash_ledger SET is_archived=true WHERE id=existing.id; END IF;
  RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
 END IF;
 IF cash_owner IS NULL THEN RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END; END IF;
 IF TG_OP='DELETE' THEN
  UPDATE public.site_cash_ledger SET is_archived=true,description=coalesce(description,'')||' [source removed; audit retained]' WHERE id=existing.id;
  RETURN OLD;
 END IF;
 moved_date:=coalesce((j->>'expense_date')::date,(j->>'advance_date')::date,(j->>'payment_date')::date,(j->>'purchase_date')::date);
 INSERT INTO public.site_cash_ledger(site_id,incharge_id,entry_date,entry_type,category,description,amount,source_table,source_id)
 VALUES((j->>'site_id')::uuid,cash_owner,moved_date,'cash_out',TG_TABLE_NAME,coalesce(j->>'description',j->>'notes',''),(j->>'amount')::numeric,TG_TABLE_NAME,(j->>'id')::uuid)
 ON CONFLICT(source_table,source_id) WHERE source_id IS NOT NULL DO UPDATE SET amount=excluded.amount,entry_date=excluded.entry_date,description=excluded.description,is_archived=false;
 RETURN NEW;
END $$;
REVOKE EXECUTE ON FUNCTION public.aaw_cash_movement_sync() FROM PUBLIC,anon,authenticated;
DO $$ DECLARE t text; BEGIN FOREACH t IN ARRAY ARRAY['site_expenses','worker_advances','worker_salary_payments','food_grocery'] LOOP
 EXECUTE format('CREATE TRIGGER aaw_cash_sync AFTER INSERT OR UPDATE OR DELETE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.aaw_cash_movement_sync()',t);
END LOOP; END $$;

CREATE FUNCTION public.aaw_incharge_choices(p_site uuid) RETURNS TABLE(user_id uuid,full_name text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF NOT public.can_access_site(p_site) THEN RAISE EXCEPTION 'Site access denied'; END IF;
 RETURN QUERY SELECT p.user_id,p.full_name FROM public.staff_profiles p JOIN public.site_assignments s ON s.user_id=p.user_id
 WHERE s.site_id=p_site AND p.role='incharge' AND (public.is_master_admin() OR p.user_id=auth.uid()) ORDER BY p.full_name;
END $$;
REVOKE EXECUTE ON FUNCTION public.aaw_incharge_choices(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.aaw_incharge_choices(uuid) TO authenticated;

-- Food days: explicit daily attendance overrides date periods; a person/day can
-- never be allocated at two sites. Old purchase-date behavior remains the default.
ALTER TABLE public.food_grocery ADD COLUMN consumption_start date;
ALTER TABLE public.food_grocery ADD COLUMN consumption_end date;
ALTER TABLE public.food_grocery ADD CONSTRAINT food_consumption_dates CHECK ((consumption_start IS NULL AND consumption_end IS NULL) OR (consumption_start IS NOT NULL AND consumption_end IS NOT NULL AND consumption_end>=consumption_start));
ALTER TABLE public.worker_food_periods ADD COLUMN is_cancelled boolean NOT NULL DEFAULT false;
CREATE TABLE public.food_daily_attendance(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),site_id uuid NOT NULL REFERENCES public.sites(id),worker_id uuid NOT NULL REFERENCES public.workers(id),
 food_date date NOT NULL,eligible boolean NOT NULL DEFAULT true,payment_type text NOT NULL CHECK(payment_type IN ('salary_deduction','company_paid')),
 notes text,created_by uuid DEFAULT auth.uid(),created_at timestamptz NOT NULL DEFAULT now(),UNIQUE(worker_id,food_date)
);
ALTER TABLE public.food_daily_attendance ENABLE ROW LEVEL SECURITY;
CREATE POLICY food_daily_read ON public.food_daily_attendance FOR SELECT TO authenticated USING(public.can_access_site(site_id));
CREATE POLICY food_daily_insert ON public.food_daily_attendance FOR INSERT TO authenticated WITH CHECK(public.can_access_site(site_id) AND EXISTS(SELECT 1 FROM public.workers w WHERE w.id=worker_id AND w.site_id=food_daily_attendance.site_id));
CREATE POLICY food_daily_update ON public.food_daily_attendance FOR UPDATE TO authenticated USING(public.can_access_site(site_id)) WITH CHECK(public.can_access_site(site_id) AND EXISTS(SELECT 1 FROM public.workers w WHERE w.id=worker_id AND w.site_id=food_daily_attendance.site_id));
REVOKE ALL ON public.food_daily_attendance FROM PUBLIC,anon,authenticated;
GRANT SELECT,INSERT,UPDATE ON public.food_daily_attendance TO authenticated;
CREATE TRIGGER aaw_operational_audit AFTER INSERT OR UPDATE ON public.food_daily_attendance FOR EACH ROW EXECUTE FUNCTION public.aaw_capture_operational_audit();
ALTER TABLE public.food_settlement_workers DROP CONSTRAINT food_settlement_workers_settlement_id_worker_id_key;
ALTER TABLE public.food_settlement_workers ADD CONSTRAINT food_worker_payer_unique UNIQUE(settlement_id,worker_id,payment_type);

CREATE FUNCTION public.aaw_food_day_rows(p_site uuid,p_start date,p_end date)
RETURNS TABLE(worker_id uuid,person_id uuid,food_date date,payment_type text)
LANGUAGE plpgsql STABLE SET search_path='' AS $$
BEGIN
 IF NOT public.can_access_site(p_site) THEN RAISE EXCEPTION 'Site access denied'; END IF;
 IF p_start IS NULL OR p_end IS NULL OR p_end<p_start OR p_end-p_start>366 THEN RAISE EXCEPTION 'Choose a food report of at most 367 days'; END IF;
 IF EXISTS(SELECT 1 FROM public.worker_food_periods a JOIN public.worker_food_periods b ON a.worker_id=b.worker_id AND a.id<b.id
   AND a.site_id=b.site_id AND a.start_date<=b.end_date AND b.start_date<=a.end_date
   WHERE a.site_id=p_site AND NOT a.is_cancelled AND NOT b.is_cancelled AND a.start_date<=p_end AND a.end_date>=p_start AND b.start_date<=p_end AND b.end_date>=p_start) THEN RAISE EXCEPTION 'Overlapping worker food periods found'; END IF;
 RETURN QUERY
 SELECT w.id,w.person_id,d.day::date,coalesce(f.payment_type,p.payment_type)
 FROM public.workers w CROSS JOIN LATERAL generate_series(p_start::timestamp,p_end::timestamp,interval '1 day') d(day)
 LEFT JOIN public.food_daily_attendance f ON f.worker_id=w.id AND f.site_id=p_site AND f.food_date=d.day::date
 LEFT JOIN LATERAL(SELECT fp.payment_type FROM public.worker_food_periods fp WHERE fp.worker_id=w.id AND fp.site_id=p_site AND NOT fp.is_cancelled AND d.day::date BETWEEN fp.start_date AND fp.end_date LIMIT 1)p ON true
 WHERE w.site_id=p_site
 AND CASE WHEN f.id IS NOT NULL THEN f.eligible ELSE p.payment_type IS NOT NULL END;
END $$;
REVOKE EXECUTE ON FUNCTION public.aaw_food_day_rows(uuid,date,date) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.aaw_food_day_rows(uuid,date,date) TO authenticated;

CREATE FUNCTION public.aaw_food_preview(p_site uuid,p_start date,p_end date) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path='' AS $$
DECLARE total_cents numeric; total_days integer; result jsonb;
BEGIN
 IF NOT public.can_access_site(p_site) THEN RAISE EXCEPTION 'Site access denied'; END IF;
 IF p_start IS NULL OR p_end IS NULL OR p_end<p_start OR p_end-p_start>366 THEN RAISE EXCEPTION 'Choose valid food dates within 367 days'; END IF;
 -- Allocate each grocery's integer paise across its consumption days first, so
 -- adjacent report periods add up to the exact original grocery amount.
 WITH g AS(SELECT *,coalesce(consumption_start,purchase_date) lo,coalesce(consumption_end,purchase_date) hi FROM public.food_grocery WHERE site_id=p_site),
 portions AS(SELECT round(amount*100) cents,(hi-lo+1) days,lo,hi,greatest(lo,p_start) first_day,least(hi,p_end) last_day FROM g WHERE lo<=p_end AND hi>=p_start)
 SELECT coalesce(sum(floor(cents/days)*(last_day-first_day+1)+greatest(0,least(last_day,lo+(mod(cents,days)::integer)-1)-first_day+1)),0) INTO total_cents FROM portions;
 SELECT count(*) INTO total_days FROM public.aaw_food_day_rows(p_site,p_start,p_end);
 WITH grouped AS(SELECT d.worker_id,d.payment_type,count(*)::integer days FROM public.aaw_food_day_rows(p_site,p_start,p_end)d GROUP BY d.worker_id,d.payment_type),
 raw AS(SELECT *,total_cents*days/nullif(total_days,0) exact FROM grouped),
 ranked AS(SELECT *,floor(exact) base,row_number()over(order by exact-floor(exact)desc,worker_id,payment_type)rank,sum(floor(exact))over()bases FROM raw)
 SELECT coalesce(jsonb_agg(jsonb_build_object('worker_id',r.worker_id,'full_name',w.full_name,'payment_type',r.payment_type,'food_days',r.days,'share_amount',(r.base+CASE WHEN r.rank<=total_cents-r.bases THEN 1 ELSE 0 END)/100) ORDER BY w.full_name,r.payment_type),'[]'::jsonb)
 INTO result FROM ranked r JOIN public.workers w ON w.id=r.worker_id;
 RETURN jsonb_build_object('grocery_total',total_cents/100,'total_food_days',total_days,'entries',result,'can_finalize',total_cents>0 AND total_days>0);
END $$;
REVOKE EXECUTE ON FUNCTION public.aaw_food_preview(uuid,date,date) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.aaw_food_preview(uuid,date,date) TO authenticated;

CREATE OR REPLACE FUNCTION public.finalize_food_settlement(p_site_id uuid,p_start date,p_end date) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE preview jsonb; result uuid; entry jsonb;
BEGIN
 IF NOT public.is_master_admin() THEN RAISE EXCEPTION 'Active Master Admin required'; END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(p_site_id::text));
 IF EXISTS(SELECT 1 FROM public.food_settlements WHERE site_id=p_site_id AND status='final' AND period_start<=p_end AND period_end>=p_start) THEN RAISE EXCEPTION 'This period overlaps an existing final settlement'; END IF;
 IF EXISTS(SELECT 1 FROM public.worker_advances a WHERE a.site_id=p_site_id AND a.advance_date BETWEEN p_start AND p_end AND btrim(a.notes) ILIKE 'FOOD:%'
  AND EXISTS(SELECT 1 FROM public.aaw_food_day_rows(p_site_id,p_start,p_end)d WHERE d.worker_id=a.worker_id AND d.payment_type='salary_deduction')) THEN RAISE EXCEPTION 'Existing manual FOOD advances found. Reconcile before finalizing'; END IF;
 -- Serialize against payroll before introducing a new salary deduction.
 PERFORM 1 FROM public.workers WHERE id IN(SELECT d.worker_id FROM public.aaw_food_day_rows(p_site_id,p_start,p_end)d WHERE d.payment_type='salary_deduction') ORDER BY id FOR UPDATE;
 IF EXISTS(SELECT 1 FROM public.worker_salary_payments p WHERE p.site_id=p_site_id AND p.period_end>=p_start AND p.worker_id IN(SELECT d.worker_id FROM public.aaw_food_day_rows(p_site_id,p_start,p_end)d WHERE d.payment_type='salary_deduction')) THEN RAISE EXCEPTION 'Food deduction overlaps a paid salary period; reconcile before finalizing'; END IF;
 preview:=public.aaw_food_preview(p_site_id,p_start,p_end);
 IF NOT (preview->>'can_finalize')::boolean THEN RAISE EXCEPTION 'Grocery cost and eligible food days are required'; END IF;
 INSERT INTO public.food_settlements(site_id,period_start,period_end,grocery_total,total_food_days,status,finalized_at,created_by)
 VALUES(p_site_id,p_start,p_end,(preview->>'grocery_total')::numeric,(preview->>'total_food_days')::integer,'final',now(),auth.uid()) RETURNING id INTO result;
 FOR entry IN SELECT value FROM jsonb_array_elements(preview->'entries') LOOP
 INSERT INTO public.food_settlement_workers(settlement_id,worker_id,food_days,share_amount,payment_type)
 VALUES(result,(entry->>'worker_id')::uuid,(entry->>'food_days')::integer,(entry->>'share_amount')::numeric,entry->>'payment_type');
 END LOOP;
 RETURN result;
END $$;
REVOKE EXECUTE ON FUNCTION public.finalize_food_settlement(uuid,date,date) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.finalize_food_settlement(uuid,date,date) TO authenticated;

CREATE OR REPLACE FUNCTION public.guard_final_food_grocery() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_old jsonb; v_new jsonb; v jsonb;
BEGIN
 IF TG_OP<>'INSERT' THEN v_old:=to_jsonb(OLD); END IF;
 IF TG_OP<>'DELETE' THEN v_new:=to_jsonb(NEW); END IF;
 FOR v IN SELECT x FROM unnest(ARRAY[v_old,v_new]) x WHERE x IS NOT NULL ORDER BY x->>'site_id' LOOP
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(v->>'site_id'));
 IF EXISTS(SELECT 1 FROM public.food_settlements s WHERE s.site_id=(v->>'site_id')::uuid AND s.status='final'
   AND coalesce((v->>'consumption_start')::date,(v->>'purchase_date')::date)<=s.period_end
   AND coalesce((v->>'consumption_end')::date,(v->>'purchase_date')::date)>=s.period_start) THEN RAISE EXCEPTION 'Grocery is locked by a final food settlement'; END IF;
 END LOOP;
 RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
END $$;

CREATE FUNCTION public.aaw_guard_food_daily() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE who uuid;
BEGIN
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(NEW.site_id::text));
 IF TG_OP='UPDATE' AND (NEW.worker_id IS DISTINCT FROM OLD.worker_id OR NEW.site_id IS DISTINCT FROM OLD.site_id OR NEW.food_date IS DISTINCT FROM OLD.food_date) THEN RAISE EXCEPTION 'Daily food attendance identity cannot be changed'; END IF;
 SELECT person_id INTO who FROM public.workers WHERE id=NEW.worker_id AND site_id=NEW.site_id;
 IF who IS NULL THEN RAISE EXCEPTION 'Worker does not belong to this site'; END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(who::text));
 IF EXISTS(SELECT 1 FROM public.food_settlements WHERE site_id=NEW.site_id AND status='final' AND NEW.food_date BETWEEN period_start AND period_end) THEN RAISE EXCEPTION 'Daily food attendance is finalized and locked'; END IF;
 IF NEW.eligible AND EXISTS(SELECT 1 FROM public.worker_food_periods p JOIN public.workers w ON w.id=p.worker_id
 WHERE w.person_id=who AND p.site_id<>NEW.site_id AND NOT p.is_cancelled AND NEW.food_date BETWEEN p.start_date AND p.end_date
 AND NOT EXISTS(SELECT 1 FROM public.food_daily_attendance d WHERE d.worker_id=p.worker_id AND d.food_date=NEW.food_date AND NOT d.eligible)) THEN RAISE EXCEPTION 'This person has an eligible food period at another site'; END IF;
 IF NEW.eligible AND EXISTS(SELECT 1 FROM public.food_daily_attendance f JOIN public.workers w ON w.id=f.worker_id WHERE w.person_id=who AND f.site_id<>NEW.site_id AND f.food_date=NEW.food_date AND f.eligible) THEN RAISE EXCEPTION 'This worker already has food attendance at another site on this date'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER aaw_food_daily_guard BEFORE INSERT OR UPDATE ON public.food_daily_attendance FOR EACH ROW EXECUTE FUNCTION public.aaw_guard_food_daily();
REVOKE EXECUTE ON FUNCTION public.aaw_guard_food_daily() FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.aaw_transfer_worker(p_worker uuid,p_to_site uuid,p_date date) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE w public.workers; result uuid; current_rate public.worker_salary_rates;
BEGIN
 SELECT * INTO w FROM public.workers WHERE id=p_worker;
 IF NOT FOUND OR NOT coalesce(w.is_active,true) OR w.is_deleted THEN RAISE EXCEPTION 'Select an active worker'; END IF;
 IF w.site_id=p_to_site OR p_date IS NULL OR p_date<coalesce(w.joining_date,p_date) OR NOT public.can_access_site(w.site_id) OR NOT public.can_access_site(p_to_site) THEN RAISE EXCEPTION 'Both sites and a valid transfer date are required'; END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(least(w.site_id,p_to_site)::text));
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(greatest(w.site_id,p_to_site)::text));
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(w.person_id::text));
 SELECT * INTO w FROM public.workers WHERE id=p_worker FOR UPDATE;
 IF NOT coalesce(w.is_active,true) OR w.is_deleted THEN RAISE EXCEPTION 'Worker already transferred or inactive'; END IF;
 SELECT * INTO current_rate FROM public.worker_salary_rates WHERE worker_id=w.id AND effective_from<=p_date ORDER BY effective_from DESC LIMIT 1;
 IF EXISTS(SELECT 1 FROM public.food_settlements WHERE site_id=w.site_id AND status='final' AND period_end>=p_date) THEN RAISE EXCEPTION 'Transfer date overlaps a finalized Food period'; END IF;
 UPDATE public.worker_food_periods SET is_cancelled=(start_date>=p_date),end_date=CASE WHEN start_date<p_date THEN least(end_date,p_date-1) ELSE end_date END WHERE worker_id=w.id AND end_date>=p_date;
 UPDATE public.food_daily_attendance SET eligible=false,notes=coalesce(notes,'')||' [transfer]' WHERE worker_id=w.id AND food_date>=p_date;
 UPDATE public.workers SET leaving_date=p_date-1,is_active=false WHERE id=w.id;
 INSERT INTO public.workers(site_id,full_name,mobile_number,joining_date,daily_wage,overtime_rate,is_active,person_id,salary_basis,monthly_salary)
 VALUES(p_to_site,w.full_name,w.mobile_number,p_date,coalesce(current_rate.daily_rate,w.daily_wage),coalesce(current_rate.overtime_hourly_rate,w.overtime_rate),true,w.person_id,coalesce(current_rate.salary_basis,w.salary_basis),coalesce(current_rate.monthly_salary,w.monthly_salary)) RETURNING id INTO result;
 RETURN result;
END $$;
REVOKE EXECUTE ON FUNCTION public.aaw_transfer_worker(uuid,uuid,date) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.aaw_transfer_worker(uuid,uuid,date) TO authenticated;

-- Operational reports are Master-only. Cash movement and tax-inclusive billed
-- surplus are deliberately separated; advances are cash out, not labour expense.
CREATE FUNCTION public.aaw_site_financials(p_site uuid,p_start date,p_end date) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path='' AS $$
DECLARE billed numeric; collected numeric; receivable numeric; expenses numeric; grocery numeric; salary_cash numeric; advance_cash numeric; earned numeric; company_food numeric;
BEGIN
 IF NOT public.is_master_admin() THEN RAISE EXCEPTION 'Master Admin only'; END IF;
 IF p_start IS NULL OR p_end IS NULL OR p_start>p_end THEN RAISE EXCEPTION 'Choose valid report dates'; END IF;
 SELECT coalesce(sum(public.aaw_invoice_payable(payload)),0) INTO billed FROM public.aaw_billing_documents WHERE site_id=p_site AND document_type='invoice' AND document_date BETWEEN p_start AND p_end;
 SELECT coalesce(sum(p.amount),0) INTO collected FROM public.aaw_client_payments p JOIN public.aaw_billing_documents d ON d.id=p.document_id WHERE d.site_id=p_site AND p.payment_date BETWEEN p_start AND p_end;
 SELECT coalesce(sum(greatest(0,public.aaw_invoice_payable(d.payload)-coalesce((SELECT sum(p.amount) FROM public.aaw_client_payments p WHERE p.document_id=d.id AND p.payment_date<=p_end),0))),0)
 INTO receivable FROM public.aaw_billing_documents d WHERE d.site_id=p_site AND d.document_type='invoice' AND d.document_date<=p_end;
 SELECT coalesce(sum(amount),0) INTO expenses FROM public.site_expenses e WHERE site_id=p_site AND expense_date BETWEEN p_start AND p_end AND NOT EXISTS(SELECT 1 FROM public.food_grocery g WHERE g.linked_expense_id=e.id);
 SELECT coalesce(sum(amount),0) INTO grocery FROM public.food_grocery WHERE site_id=p_site AND purchase_date BETWEEN p_start AND p_end;
 SELECT coalesce(sum(amount),0) INTO salary_cash FROM public.worker_salary_payments WHERE site_id=p_site AND payment_date BETWEEN p_start AND p_end;
 SELECT coalesce(sum(amount),0) INTO advance_cash FROM public.worker_advances WHERE site_id=p_site AND advance_date BETWEEN p_start AND p_end AND coalesce(btrim(notes),'') NOT ILIKE 'FOOD:%';
 SELECT coalesce(round(sum((CASE a.status WHEN 'present' THEN 1 WHEN 'half_day' THEN 0.5 ELSE 0 END)*r.daily_rate+coalesce(a.overtime_hours,0)*r.overtime_rate),2),0)
 INTO earned FROM public.worker_attendance a CROSS JOIN LATERAL public.aaw_effective_rate(a.worker_id,a.attendance_date)r WHERE a.site_id=p_site AND a.attendance_date BETWEEN p_start AND p_end;
 SELECT coalesce(sum(w.share_amount),0) INTO company_food FROM public.food_settlement_workers w JOIN public.food_settlements s ON s.id=w.settlement_id WHERE s.site_id=p_site AND s.status='final' AND w.payment_type='company_paid' AND s.period_end BETWEEN p_start AND p_end;
 RETURN jsonb_build_object('billed',billed,'collected',collected,'receivable',receivable,'site_expenses',expenses,'grocery_cash',grocery,'salary_cash',salary_cash,'advance_cash',advance_cash,'earned_labour',earned,'company_food',company_food,
 'cash_surplus',collected-expenses-grocery-salary_cash-advance_cash,'billed_operating_surplus',billed-expenses-earned-company_food);
END $$;
REVOKE EXECUTE ON FUNCTION public.aaw_site_financials(uuid,date,date) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.aaw_site_financials(uuid,date,date) TO authenticated;

CREATE INDEX aaw_attendance_site_date ON public.worker_attendance(site_id,attendance_date);
CREATE INDEX aaw_advances_site_worker_date ON public.worker_advances(site_id,worker_id,advance_date);
CREATE INDEX aaw_payments_site_worker_date ON public.worker_salary_payments(site_id,worker_id,payment_date);
CREATE INDEX aaw_expenses_site_date ON public.site_expenses(site_id,expense_date);
CREATE INDEX aaw_ledger_owner_date ON public.site_cash_ledger(incharge_id,site_id,entry_date);
CREATE INDEX aaw_food_daily_site_date ON public.food_daily_attendance(site_id,food_date);
CREATE INDEX aaw_audit_site_date ON public.aaw_operational_audit(site_id,changed_at);
CREATE OR REPLACE FUNCTION public.v515_salary_payment_lock()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
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

-- Effective-date wages; monthly rates are divided by 30 without daily rounding.
SELECT COALESCE(ROUND(SUM((CASE a.status WHEN 'present' THEN 1 WHEN 'half_day' THEN 0.5 ELSE 0 END)*r.daily_rate+COALESCE(a.overtime_hours,0)*r.overtime_rate),2),0)
INTO v_gross FROM public.worker_attendance a CROSS JOIN LATERAL public.aaw_effective_rate(a.worker_id,a.attendance_date) r
WHERE a.worker_id=NEW.worker_id AND a.site_id=NEW.site_id AND a.attendance_date<=NEW.period_end;

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
REVOKE EXECUTE ON FUNCTION public.v515_salary_payment_lock() FROM PUBLIC,anon,authenticated;
NOTIFY pgrst,'reload schema';

-- Preserve the existing fallback wage before any future rate change. These are
-- carry-forward baselines, not reconstructed historical rate-change events.
INSERT INTO public.worker_salary_rates(worker_id,site_id,effective_from,daily_rate,overtime_hourly_rate,salary_basis,monthly_salary)
SELECT id,site_id,date '0001-01-01',coalesce(daily_wage,0),coalesce(overtime_rate,0),salary_basis,monthly_salary FROM public.workers
ON CONFLICT(worker_id,site_id,effective_from) DO NOTHING;
CREATE FUNCTION public.aaw_record_worker_rate_edit() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF TG_OP='INSERT' THEN
  INSERT INTO public.worker_salary_rates(worker_id,site_id,effective_from,daily_rate,overtime_hourly_rate,salary_basis,monthly_salary)
  VALUES(NEW.id,NEW.site_id,date '0001-01-01',coalesce(NEW.daily_wage,0),coalesce(NEW.overtime_rate,0),NEW.salary_basis,NEW.monthly_salary) ON CONFLICT DO NOTHING;
 ELSIF NEW.daily_wage IS DISTINCT FROM OLD.daily_wage OR NEW.overtime_rate IS DISTINCT FROM OLD.overtime_rate OR NEW.monthly_salary IS DISTINCT FROM OLD.monthly_salary OR NEW.salary_basis IS DISTINCT FROM OLD.salary_basis THEN
  IF EXISTS(SELECT 1 FROM public.worker_salary_payments WHERE worker_id=NEW.id AND period_end>=CURRENT_DATE) THEN RAISE EXCEPTION 'Direct rate edit overlaps a paid period; use a later effective date in Salary Rates'; END IF;
  INSERT INTO public.worker_salary_rates(worker_id,site_id,effective_from,daily_rate,overtime_hourly_rate,salary_basis,monthly_salary)
  VALUES(NEW.id,NEW.site_id,CURRENT_DATE,coalesce(NEW.daily_wage,0),coalesce(NEW.overtime_rate,0),NEW.salary_basis,NEW.monthly_salary)
  ON CONFLICT(worker_id,site_id,effective_from) DO UPDATE SET daily_rate=excluded.daily_rate,overtime_hourly_rate=excluded.overtime_hourly_rate,salary_basis=excluded.salary_basis,monthly_salary=excluded.monthly_salary;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER aaw_worker_rate_edit AFTER INSERT OR UPDATE ON public.workers FOR EACH ROW EXECUTE FUNCTION public.aaw_record_worker_rate_edit();
REVOKE EXECUTE ON FUNCTION public.aaw_record_worker_rate_edit() FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.aaw_guard_food_person_period() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE who uuid;
BEGIN
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(NEW.site_id::text));
 SELECT person_id INTO who FROM public.workers WHERE id=NEW.worker_id AND site_id=NEW.site_id;
 IF who IS NULL THEN RAISE EXCEPTION 'Worker does not belong to this site'; END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(who::text));
 IF NOT NEW.is_cancelled AND EXISTS(SELECT 1 FROM public.worker_food_periods p JOIN public.workers w ON w.id=p.worker_id
 WHERE p.id<>NEW.id AND w.person_id=who AND NOT p.is_cancelled AND p.start_date<=NEW.end_date AND p.end_date>=NEW.start_date) THEN RAISE EXCEPTION 'Overlapping food period for this person'; END IF;
 IF NOT NEW.is_cancelled AND EXISTS(SELECT 1 FROM public.food_daily_attendance d JOIN public.workers w ON w.id=d.worker_id
 WHERE w.person_id=who AND d.site_id<>NEW.site_id AND d.eligible AND d.food_date BETWEEN NEW.start_date AND NEW.end_date) THEN RAISE EXCEPTION 'Person has food attendance at another site in this period'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER aaw_food_person_period BEFORE INSERT OR UPDATE ON public.worker_food_periods FOR EACH ROW EXECUTE FUNCTION public.aaw_guard_food_person_period();
REVOKE EXECUTE ON FUNCTION public.aaw_guard_food_person_period() FROM PUBLIC,anon,authenticated;

-- Explicit links prevent counting the same bill as both Grocery and Site Expense.
ALTER TABLE public.food_grocery ADD COLUMN linked_expense_id uuid REFERENCES public.site_expenses(id);
CREATE UNIQUE INDEX aaw_food_expense_link ON public.food_grocery(linked_expense_id) WHERE linked_expense_id IS NOT NULL;
CREATE FUNCTION public.aaw_guard_food_expense_link() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF TG_TABLE_NAME='food_grocery' THEN
  IF NEW.linked_expense_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.site_expenses e WHERE e.id=NEW.linked_expense_id AND e.site_id=NEW.site_id AND e.amount=NEW.amount) THEN RAISE EXCEPTION 'Linked site expense must belong to this site and have the same amount'; END IF;
 ELSE
  IF EXISTS(SELECT 1 FROM public.food_grocery g WHERE g.linked_expense_id=NEW.id AND (g.site_id<>NEW.site_id OR g.amount<>NEW.amount)) THEN RAISE EXCEPTION 'Unlink the Grocery bill before changing its linked expense amount/site'; END IF;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER aaw_grocery_expense BEFORE INSERT OR UPDATE ON public.food_grocery FOR EACH ROW EXECUTE FUNCTION public.aaw_guard_food_expense_link();
CREATE TRIGGER aaw_expense_grocery BEFORE UPDATE ON public.site_expenses FOR EACH ROW EXECUTE FUNCTION public.aaw_guard_food_expense_link();
REVOKE EXECUTE ON FUNCTION public.aaw_guard_food_expense_link() FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.aaw_log_admin_action(p_action text,p_target uuid,p_details jsonb DEFAULT '{}'::jsonb) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF NOT public.is_master_admin() THEN RAISE EXCEPTION 'Master Admin only'; END IF;
 IF p_action NOT IN ('create_incharge','reset_password','disable_incharge','enable_incharge','assign_site') THEN RAISE EXCEPTION 'Unsupported audit action'; END IF;
 INSERT INTO public.aaw_operational_audit(table_name,row_id,actor_id,operation,new_values) VALUES('incharge_accounts',p_target::text,auth.uid(),p_action,p_details-'password'-'new_password');
END $$;
REVOKE EXECUTE ON FUNCTION public.aaw_log_admin_action(text,uuid,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.aaw_log_admin_action(text,uuid,jsonb) TO authenticated;

-- Direct table writes must enforce the same paid-period boundary as the RPC.
CREATE FUNCTION public.aaw_guard_rate_history() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM 1 FROM public.workers WHERE id=NEW.worker_id AND site_id=NEW.site_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Invalid worker/site rate'; END IF;
 IF TG_OP='UPDATE' AND (NEW.worker_id<>OLD.worker_id OR NEW.site_id<>OLD.site_id OR NEW.effective_from<>OLD.effective_from) THEN RAISE EXCEPTION 'Rate history identity cannot be changed'; END IF;
 IF NEW.salary_basis='monthly' AND NEW.monthly_salary IS NULL THEN RAISE EXCEPTION 'Monthly salary required'; END IF;
 IF EXISTS(SELECT 1 FROM public.worker_salary_payments WHERE worker_id=NEW.worker_id AND period_end>=NEW.effective_from) THEN RAISE EXCEPTION 'Rate overlaps a paid salary period'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER aaw_rate_history_guard BEFORE INSERT OR UPDATE ON public.worker_salary_rates FOR EACH ROW EXECUTE FUNCTION public.aaw_guard_rate_history();
REVOKE EXECUTE ON FUNCTION public.aaw_guard_rate_history() FROM PUBLIC,anon,authenticated;
-- Rates are retained; corrections use a later effective date, never deletion.
REVOKE DELETE ON public.worker_salary_rates FROM authenticated;
ALTER TABLE public.site_cash_ledger ADD CONSTRAINT aaw_cash_source_pair CHECK ((source_table IS NULL AND source_id IS NULL) OR (source_table IS NOT NULL AND source_id IS NOT NULL));
NOTIFY pgrst,'reload schema';

CREATE FUNCTION public.aaw_guard_paid_payroll_entry() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE j jsonb; oldj jsonb; day date; worker uuid;
BEGIN
 j:=CASE WHEN TG_OP='DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
 IF TG_OP='UPDATE' THEN oldj:=to_jsonb(OLD);
  IF j->>'worker_id' IS DISTINCT FROM oldj->>'worker_id' OR j->>'site_id' IS DISTINCT FROM oldj->>'site_id' THEN RAISE EXCEPTION 'Payroll entry worker/site cannot be changed'; END IF;
 END IF;
 worker:=(j->>'worker_id')::uuid;
 PERFORM 1 FROM public.workers WHERE id=worker FOR UPDATE;
 day:=coalesce((j->>'attendance_date')::date,(j->>'advance_date')::date);
 IF EXISTS(SELECT 1 FROM public.worker_salary_payments p WHERE p.worker_id=worker AND (day<=p.period_end OR (TG_OP='UPDATE' AND coalesce((oldj->>'attendance_date')::date,(oldj->>'advance_date')::date)<=p.period_end))) THEN RAISE EXCEPTION 'Payroll entry belongs to a paid salary period and is locked'; END IF;
 RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
END $$;
CREATE TRIGGER aaw_paid_payroll_guard BEFORE INSERT OR UPDATE OR DELETE ON public.worker_attendance FOR EACH ROW EXECUTE FUNCTION public.aaw_guard_paid_payroll_entry();
CREATE TRIGGER aaw_paid_payroll_guard BEFORE INSERT OR UPDATE OR DELETE ON public.worker_advances FOR EACH ROW EXECUTE FUNCTION public.aaw_guard_paid_payroll_entry();
REVOKE EXECUTE ON FUNCTION public.aaw_guard_paid_payroll_entry() FROM PUBLIC,anon,authenticated;
REVOKE TRUNCATE,TRIGGER,REFERENCES ON public.site_cash_ledger,public.worker_salary_rates FROM anon,authenticated;
