CREATE OR REPLACE FUNCTION public.aaw_transfer_worker(p_worker uuid,p_to_site uuid,p_date date) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE w public.workers; result uuid; current_rate public.worker_salary_rates;
BEGIN
 SELECT * INTO w FROM public.workers WHERE id=p_worker;
 IF NOT FOUND OR NOT coalesce(w.is_active,true) OR w.is_deleted THEN RAISE EXCEPTION 'Select an active worker'; END IF;
 IF p_date>CURRENT_DATE THEN RAISE EXCEPTION 'Transfer cannot be scheduled in the future; record it when the worker moves'; END IF;
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
