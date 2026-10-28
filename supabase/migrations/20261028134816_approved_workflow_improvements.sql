-- Approved workflow additions. Installs features; does not modify existing business records.
CREATE FUNCTION public.aaw_today_work(p_site uuid,p_day date) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path='' AS $$
DECLARE missing integer; pending integer; dues jsonb;
BEGIN
 IF NOT public.can_access_site(p_site) THEN RAISE EXCEPTION 'Site access denied'; END IF;
 IF p_day IS NULL OR p_day>(now() AT TIME ZONE 'Asia/Kolkata')::date THEN RAISE EXCEPTION 'Choose today or an earlier date'; END IF;
 SELECT count(*) INTO missing FROM public.workers w WHERE w.site_id=p_site AND NOT w.is_deleted AND coalesce(w.is_active,true)
 AND coalesce(w.joining_date,p_day)<=p_day AND (w.leaving_date IS NULL OR w.leaving_date>=p_day)
 AND NOT EXISTS(SELECT 1 FROM public.worker_attendance a WHERE a.worker_id=w.id AND a.site_id=p_site AND a.attendance_date=p_day);
 SELECT count(DISTINCT d.worker_id) INTO pending FROM public.aaw_food_day_rows(p_site,date_trunc('month',p_day)::date,p_day)d
 WHERE NOT EXISTS(SELECT 1 FROM public.food_settlements s WHERE s.site_id=p_site AND s.status='final' AND d.food_date BETWEEN s.period_start AND s.period_end);
 IF public.is_master_admin() THEN dues:=public.aaw_site_financials(p_site,date_trunc('month',p_day)::date,p_day); END IF;
 RETURN jsonb_build_object('missing_attendance',missing,'unfinalized_food_workers',pending,'client_dues',dues->'receivable');
END $$;
REVOKE ALL ON FUNCTION public.aaw_today_work(uuid,date) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.aaw_today_work(uuid,date) TO authenticated;

INSERT INTO storage.buckets(id,name,public,file_size_limit,allowed_mime_types) VALUES
('aaw-receipts','aaw-receipts',false,5242880,ARRAY['image/jpeg','image/png','image/webp','application/pdf']);
CREATE TABLE public.aaw_receipt_attachments(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),site_id uuid NOT NULL REFERENCES public.sites(id),
 source_table text NOT NULL CHECK(source_table IN('site_expenses','food_grocery')),source_id uuid NOT NULL,
 object_path text NOT NULL UNIQUE,file_name text NOT NULL CHECK(length(file_name) BETWEEN 1 AND 180),
 mime_type text NOT NULL CHECK(mime_type IN('image/jpeg','image/png','image/webp','application/pdf')),
 file_size integer NOT NULL CHECK(file_size BETWEEN 1 AND 5242880),created_by uuid NOT NULL DEFAULT auth.uid(),
 created_at timestamptz NOT NULL DEFAULT now(),is_archived boolean NOT NULL DEFAULT false
);
CREATE INDEX ON public.aaw_receipt_attachments(site_id,source_table,source_id);
ALTER TABLE public.aaw_receipt_attachments ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.aaw_receipt_attachments FROM PUBLIC,anon,authenticated;
GRANT SELECT,INSERT ON public.aaw_receipt_attachments TO authenticated;
GRANT UPDATE(is_archived) ON public.aaw_receipt_attachments TO authenticated;
CREATE POLICY receipt_read ON public.aaw_receipt_attachments FOR SELECT TO authenticated USING(public.can_access_site(site_id));
CREATE POLICY receipt_insert ON public.aaw_receipt_attachments FOR INSERT TO authenticated WITH CHECK(public.can_access_site(site_id) AND created_by=auth.uid() AND NOT is_archived);
CREATE POLICY receipt_archive ON public.aaw_receipt_attachments FOR UPDATE TO authenticated USING(public.can_access_site(site_id) AND (created_by=auth.uid() OR public.is_master_admin())) WITH CHECK(public.can_access_site(site_id));
CREATE FUNCTION aaw_private.receipt_path_allowed(p_name text,p_own boolean) RETURNS boolean LANGUAGE plpgsql STABLE SET search_path='' AS $$
BEGIN
 IF p_name !~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}[.](jpg|png|webp|pdf)$' THEN RETURN false; END IF;
 RETURN auth.uid() IS NOT NULL AND public.can_access_site(split_part(p_name,'/',1)::uuid) AND (NOT p_own OR split_part(p_name,'/',2)::uuid=auth.uid());
EXCEPTION WHEN invalid_text_representation THEN RETURN false;
END $$;
REVOKE ALL ON FUNCTION aaw_private.receipt_path_allowed(text,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION aaw_private.receipt_path_allowed(text,boolean) TO authenticated;
CREATE POLICY aaw_receipt_upload ON storage.objects FOR INSERT TO authenticated WITH CHECK(bucket_id='aaw-receipts' AND aaw_private.receipt_path_allowed(name,true));
CREATE POLICY aaw_receipt_download ON storage.objects FOR SELECT TO authenticated USING(bucket_id='aaw-receipts' AND aaw_private.receipt_path_allowed(name,false));
CREATE POLICY aaw_receipt_orphan_cleanup ON storage.objects FOR DELETE TO authenticated USING(bucket_id='aaw-receipts' AND aaw_private.receipt_path_allowed(name,true) AND NOT EXISTS(SELECT 1 FROM public.aaw_receipt_attachments r WHERE r.object_path=name));
CREATE FUNCTION public.aaw_guard_receipt() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
DECLARE sid uuid; meta jsonb;
BEGIN
 IF TG_OP='UPDATE' THEN
 IF (to_jsonb(NEW)-'is_archived') IS DISTINCT FROM (to_jsonb(OLD)-'is_archived') THEN RAISE EXCEPTION 'Receipt identity is immutable'; END IF;
 RETURN NEW; END IF;
 IF NEW.source_table='site_expenses' THEN SELECT site_id INTO sid FROM public.site_expenses WHERE id=NEW.source_id;
 ELSE SELECT site_id INTO sid FROM public.food_grocery WHERE id=NEW.source_id; END IF;
 IF sid IS DISTINCT FROM NEW.site_id OR NOT aaw_private.receipt_path_allowed(NEW.object_path,true)
 OR split_part(split_part(NEW.object_path,'/',3),'.',1)<>NEW.id::text THEN RAISE EXCEPTION 'Receipt source/path does not match this site and user'; END IF;
 SELECT metadata INTO meta FROM storage.objects WHERE bucket_id='aaw-receipts' AND name=NEW.object_path;
 IF meta IS NULL OR (meta->>'size')::bigint IS DISTINCT FROM NEW.file_size OR meta->>'mimetype' IS DISTINCT FROM NEW.mime_type THEN RAISE EXCEPTION 'Upload a matching receipt file first'; END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.aaw_guard_receipt() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER aaw_guard_receipt BEFORE INSERT OR UPDATE ON public.aaw_receipt_attachments FOR EACH ROW EXECUTE FUNCTION public.aaw_guard_receipt();
CREATE TRIGGER aaw_operational_audit AFTER INSERT OR UPDATE OR DELETE ON public.aaw_receipt_attachments FOR EACH ROW EXECUTE FUNCTION public.aaw_capture_operational_audit();

CREATE TABLE public.aaw_enquiries(
 id uuid PRIMARY KEY,full_name text NOT NULL CHECK(length(full_name) BETWEEN 2 AND 100),contact text NOT NULL CHECK(length(contact) BETWEEN 6 AND 150),
 project_type text NOT NULL CHECK(length(project_type) BETWEEN 1 AND 100),location text NOT NULL CHECK(length(location) BETWEEN 2 AND 200),
 description text NOT NULL CHECK(length(description) BETWEEN 10 AND 2000),status text NOT NULL DEFAULT 'new' CHECK(status IN('new','contacted','quoted','won','closed')),
 admin_notes text NOT NULL DEFAULT '' CHECK(length(admin_notes)<=4000),follow_up_on date,
 created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now(),payload_hash text NOT NULL
);
CREATE INDEX ON public.aaw_enquiries(status,created_at DESC);
ALTER TABLE public.aaw_enquiries ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.aaw_enquiries FROM PUBLIC,anon,authenticated;
GRANT SELECT(id,full_name,contact,project_type,location,description,status,admin_notes,follow_up_on,created_at,updated_at) ON public.aaw_enquiries TO authenticated;
GRANT UPDATE(status,admin_notes,follow_up_on) ON public.aaw_enquiries TO authenticated;
CREATE POLICY enquiry_read ON public.aaw_enquiries FOR SELECT TO authenticated USING(public.is_master_admin());
CREATE POLICY enquiry_followup ON public.aaw_enquiries FOR UPDATE TO authenticated USING(public.is_master_admin()) WITH CHECK(public.is_master_admin());
CREATE FUNCTION public.aaw_touch_enquiry() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$ BEGIN NEW.updated_at:=now();RETURN NEW;END $$;
REVOKE ALL ON FUNCTION public.aaw_touch_enquiry() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER aaw_touch_enquiry BEFORE UPDATE ON public.aaw_enquiries FOR EACH ROW EXECUTE FUNCTION public.aaw_touch_enquiry();
CREATE TRIGGER aaw_operational_audit AFTER INSERT OR UPDATE ON public.aaw_enquiries FOR EACH ROW EXECUTE FUNCTION public.aaw_capture_operational_audit();
CREATE TABLE aaw_private.enquiry_quota(ip_hash text NOT NULL,hour_at timestamptz NOT NULL,requests integer NOT NULL,PRIMARY KEY(ip_hash,hour_at));
ALTER TABLE aaw_private.enquiry_quota ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON aaw_private.enquiry_quota FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.aaw_submit_enquiry(p_id uuid,p_name text,p_contact text,p_type text,p_location text,p_description text,p_ip_hash text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE h text; existing text; used integer; bucket timestamptz:=date_trunc('hour',now());
BEGIN
 PERFORM pg_advisory_xact_lock(72938104);
 h:=encode(sha256(convert_to(jsonb_build_array(p_name,p_contact,p_type,p_location,p_description)::text,'UTF8')),'hex');
 SELECT payload_hash INTO existing FROM public.aaw_enquiries WHERE id=p_id;
 IF existing IS NOT NULL THEN IF existing<>h THEN RAISE EXCEPTION 'Request conflict';END IF;RETURN p_id;END IF;
 IF p_ip_hash IS NULL OR length(p_ip_hash)<>64 THEN RAISE EXCEPTION 'Invalid request';END IF;
 DELETE FROM aaw_private.enquiry_quota WHERE hour_at<date_trunc('day',now())-interval '1 day';
 SELECT coalesce(sum(requests),0) INTO used FROM aaw_private.enquiry_quota WHERE hour_at>=date_trunc('day',now());
 IF used>=200 OR coalesce((SELECT requests FROM aaw_private.enquiry_quota WHERE ip_hash=p_ip_hash AND hour_at=bucket),0)>=5 THEN RAISE EXCEPTION 'Rate limit';END IF;
 INSERT INTO aaw_private.enquiry_quota VALUES(p_ip_hash,bucket,1) ON CONFLICT(ip_hash,hour_at) DO UPDATE SET requests=aaw_private.enquiry_quota.requests+1;
 INSERT INTO public.aaw_enquiries(id,full_name,contact,project_type,location,description,payload_hash)VALUES(p_id,p_name,p_contact,p_type,p_location,p_description,h);
 RETURN p_id;
END $$;
REVOKE ALL ON FUNCTION public.aaw_submit_enquiry(uuid,text,text,text,text,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.aaw_submit_enquiry(uuid,text,text,text,text,text,text) TO service_role;

CREATE OR REPLACE FUNCTION aaw_private.site_snapshot(p_site uuid) RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$
DECLARE result jsonb:='{}'; data jsonb:='{}'; part jsonb; site public.sites; foreign_rows boolean; r record;
BEGIN
 IF auth.uid() IS NULL OR NOT public.is_master_admin() THEN RAISE EXCEPTION 'Active Master Admin access required'; END IF;
 SELECT * INTO site FROM public.sites WHERE id=p_site;
 IF site.id IS NULL THEN RAISE EXCEPTION 'Site not found'; END IF;
 -- Unknown new site-linked tables/foreign keys must be reviewed rather than silently omitted/cascaded.
 IF EXISTS(SELECT 1 FROM pg_catalog.pg_attribute a JOIN pg_catalog.pg_class c ON c.oid=a.attrelid
  WHERE c.relnamespace='public'::regnamespace AND c.relkind IN('r','p') AND a.attname='site_id' AND NOT a.attisdropped
  AND c.relname<>ALL(ARRAY['workers','worker_attendance','worker_advances','worker_salary_payments','worker_salary_rates','worker_food_periods','food_grocery','food_settlements','site_expenses','site_cash_ledger','daily_production_entries','food_daily_attendance','aaw_billing_documents','daily_production_audit','aaw_operational_audit','site_assignments','incharge_accounts','aaw_receipt_attachments'])) THEN RAISE EXCEPTION 'New site table detected; archive mapping requires review'; END IF;
 IF EXISTS(SELECT 1 FROM pg_catalog.pg_constraint c WHERE c.contype='f'
  AND c.confrelid IN('public.workers'::regclass,'public.worker_attendance'::regclass,'public.worker_advances'::regclass,'public.worker_salary_payments'::regclass,'public.worker_salary_rates'::regclass,'public.worker_food_periods'::regclass,'public.food_grocery'::regclass,'public.food_settlements'::regclass,'public.site_expenses'::regclass,'public.site_cash_ledger'::regclass,'public.daily_production_entries'::regclass,'public.food_daily_attendance'::regclass,'public.aaw_billing_documents'::regclass,'public.food_settlement_workers'::regclass,'public.aaw_billing_document_history'::regclass,'public.aaw_client_payments'::regclass)
  AND c.conrelid NOT IN('public.workers'::regclass,'public.worker_attendance'::regclass,'public.worker_advances'::regclass,'public.worker_salary_payments'::regclass,'public.worker_salary_rates'::regclass,'public.worker_food_periods'::regclass,'public.food_grocery'::regclass,'public.food_settlements'::regclass,'public.site_expenses'::regclass,'public.site_cash_ledger'::regclass,'public.daily_production_entries'::regclass,'public.food_daily_attendance'::regclass,'public.aaw_billing_documents'::regclass,'public.food_settlement_workers'::regclass,'public.aaw_billing_document_history'::regclass,'public.aaw_client_payments'::regclass)) THEN RAISE EXCEPTION 'Unmapped dependent table detected'; END IF;
 -- Worker identity shared through a relation at another site must not cascade or be changed.
 FOR r IN SELECT c.relname FROM pg_catalog.pg_class c JOIN pg_catalog.pg_attribute a ON a.attrelid=c.oid
  WHERE c.relnamespace='public'::regnamespace AND c.relkind='r' AND a.attname='worker_id' AND NOT a.attisdropped
  AND EXISTS(SELECT 1 FROM pg_catalog.pg_attribute b WHERE b.attrelid=c.oid AND b.attname='site_id' AND NOT b.attisdropped)
 LOOP
  EXECUTE format('SELECT EXISTS(SELECT 1 FROM public.%I x JOIN public.workers w ON w.id=x.worker_id WHERE w.site_id=$1 AND x.site_id IS DISTINCT FROM $1)',r.relname) INTO foreign_rows USING p_site;
  IF foreign_rows THEN RAISE EXCEPTION 'Worker has linked records at another site; deletion blocked'; END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM public.food_settlement_workers f JOIN public.workers w ON w.id=f.worker_id
 JOIN public.food_settlements s ON s.id=f.settlement_id WHERE w.site_id=p_site AND s.site_id IS DISTINCT FROM p_site)
 OR EXISTS(SELECT 1 FROM public.food_grocery g JOIN public.site_expenses e ON e.id=g.linked_expense_id WHERE e.site_id=p_site AND g.site_id IS DISTINCT FROM p_site)
 THEN RAISE EXCEPTION 'Cross-site dependent records exist; deletion blocked'; END IF;
 IF EXISTS(SELECT 1 FROM public.site_cash_ledger l JOIN public.site_expenses x ON x.id=l.source_id WHERE l.source_table='site_expenses' AND x.site_id=p_site AND l.site_id IS DISTINCT FROM p_site) THEN RAISE EXCEPTION 'Cross-site cash link exists; deletion blocked'; END IF;
 IF EXISTS(SELECT 1 FROM public.site_cash_ledger l JOIN public.worker_advances x ON x.id=l.source_id WHERE l.source_table='worker_advances' AND x.site_id=p_site AND l.site_id IS DISTINCT FROM p_site) THEN RAISE EXCEPTION 'Cross-site cash link exists; deletion blocked'; END IF;
 IF EXISTS(SELECT 1 FROM public.site_cash_ledger l JOIN public.worker_salary_payments x ON x.id=l.source_id WHERE l.source_table='worker_salary_payments' AND x.site_id=p_site AND l.site_id IS DISTINCT FROM p_site) THEN RAISE EXCEPTION 'Cross-site cash link exists; deletion blocked'; END IF;
 IF EXISTS(SELECT 1 FROM public.site_cash_ledger l JOIN public.food_grocery x ON x.id=l.source_id WHERE l.source_table='food_grocery' AND x.site_id=p_site AND l.site_id IS DISTINCT FROM p_site) THEN RAISE EXCEPTION 'Cross-site cash link exists; deletion blocked'; END IF;
 SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text),'[]'::jsonb) INTO part FROM public.workers x WHERE x.site_id=p_site; data:=data||jsonb_build_object('workers',part);
 SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text),'[]'::jsonb) INTO part FROM public.worker_attendance x WHERE x.site_id=p_site; data:=data||jsonb_build_object('worker_attendance',part);
 SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text),'[]'::jsonb) INTO part FROM public.worker_advances x WHERE x.site_id=p_site; data:=data||jsonb_build_object('worker_advances',part);
 SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text),'[]'::jsonb) INTO part FROM public.worker_salary_payments x WHERE x.site_id=p_site; data:=data||jsonb_build_object('worker_salary_payments',part);
 SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text),'[]'::jsonb) INTO part FROM public.worker_salary_rates x WHERE x.site_id=p_site; data:=data||jsonb_build_object('worker_salary_rates',part);
 SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text),'[]'::jsonb) INTO part FROM public.worker_food_periods x WHERE x.site_id=p_site; data:=data||jsonb_build_object('worker_food_periods',part);
 SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text),'[]'::jsonb) INTO part FROM public.food_grocery x WHERE x.site_id=p_site; data:=data||jsonb_build_object('food_grocery',part);
 SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text),'[]'::jsonb) INTO part FROM public.food_settlements x WHERE x.site_id=p_site; data:=data||jsonb_build_object('food_settlements',part);
 SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text),'[]'::jsonb) INTO part FROM public.site_expenses x WHERE x.site_id=p_site; data:=data||jsonb_build_object('site_expenses',part);
 SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text),'[]'::jsonb) INTO part FROM public.site_cash_ledger x WHERE x.site_id=p_site; data:=data||jsonb_build_object('site_cash_ledger',part);
 SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text),'[]'::jsonb) INTO part FROM public.daily_production_entries x WHERE x.site_id=p_site; data:=data||jsonb_build_object('daily_production_entries',part);
 SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text),'[]'::jsonb) INTO part FROM public.food_daily_attendance x WHERE x.site_id=p_site; data:=data||jsonb_build_object('food_daily_attendance',part);
 SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text),'[]'::jsonb) INTO part FROM public.aaw_billing_documents x WHERE x.site_id=p_site; data:=data||jsonb_build_object('aaw_billing_documents',part);
 SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text),'[]'::jsonb) INTO part FROM public.food_settlement_workers x JOIN public.food_settlements p ON p.id=x.settlement_id WHERE p.site_id=p_site; data:=data||jsonb_build_object('food_settlement_workers',part);
 SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text),'[]'::jsonb) INTO part FROM public.aaw_billing_document_history x JOIN public.aaw_billing_documents p ON p.id=x.document_id WHERE p.site_id=p_site; data:=data||jsonb_build_object('aaw_billing_document_history',part);
 SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text),'[]'::jsonb) INTO part FROM public.aaw_client_payments x JOIN public.aaw_billing_documents p ON p.id=x.document_id WHERE p.site_id=p_site; data:=data||jsonb_build_object('aaw_client_payments',part);
 SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text),'[]'::jsonb) INTO part FROM public.aaw_receipt_attachments x WHERE x.site_id=p_site; data:=data||jsonb_build_object('aaw_receipt_attachments',part);
 result:=jsonb_build_object('format','AAW-site-recovery-v1','site',to_jsonb(site),'data',data,
  'preserved','Site configuration, logins, assignments and audit trails remain. Active records have no app Undo. Recovery archive retained privately. Receipt binaries remain in private Storage and are not embedded in JSON.');
 IF octet_length(result::text)>20*1024*1024 THEN RAISE EXCEPTION 'Recovery archive exceeds 20 MB; use administrator-assisted maintenance'; END IF;
 RETURN result;
END $$;

CREATE OR REPLACE FUNCTION aaw_private.prepare_site_delete(p_site uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' SET lock_timeout='5s' AS $$
DECLARE a jsonb; d text; r aaw_private.site_delete_requests; counts jsonb;
BEGIN
 IF auth.uid() IS NULL OR NOT public.is_master_admin() THEN RAISE EXCEPTION 'Active Master Admin access required'; END IF;
 LOCK TABLE public.aaw_receipt_attachments,public.aaw_billing_document_history,public.aaw_billing_documents,public.aaw_client_payments,public.aaw_operational_audit,public.daily_production_audit,public.daily_production_entries,public.food_daily_attendance,public.food_grocery,public.food_settlement_workers,public.food_settlements,public.site_cash_ledger,public.site_expenses,public.sites,public.worker_advances,public.worker_attendance,public.worker_food_periods,public.worker_salary_payments,public.worker_salary_rates,public.workers IN SHARE ROW EXCLUSIVE MODE;
 DELETE FROM aaw_private.site_delete_requests WHERE phase<3 AND expires_at<clock_timestamp();
 a:=aaw_private.site_snapshot(p_site);d:=encode(sha256(convert_to(a::text,'UTF8')),'hex');
 SELECT jsonb_object_agg(key,jsonb_array_length(value)) INTO counts FROM jsonb_each(a->'data');
 INSERT INTO aaw_private.site_delete_requests(actor_id,site_id,site_name,archive,digest)
 VALUES(auth.uid(),p_site,a->'site'->>'site_name',a,d) RETURNING * INTO r;
 RETURN jsonb_build_object('request_id',r.id,'site_name',r.site_name,'site_id',r.site_id,'digest',d,
  'counts',counts,'archive_text',a::text,'ready_at',r.ready_at,'expires_at',r.expires_at,'wait_seconds',8);
END $$;

CREATE OR REPLACE FUNCTION aaw_private.execute_site_delete(p_request uuid,p_phrase text,p_digest text,p_archive_text text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' SET lock_timeout='5s' AS $$
DECLARE r aaw_private.site_delete_requests; current_data jsonb; counts jsonb; deleted bigint; t text;
BEGIN
 IF auth.uid() IS NULL OR NOT public.is_master_admin() THEN RAISE EXCEPTION 'Active Master Admin access required'; END IF;
 SELECT * INTO r FROM aaw_private.site_delete_requests WHERE id=p_request FOR UPDATE;
 IF r.id IS NULL OR r.actor_id<>auth.uid() THEN RAISE EXCEPTION 'Delete request not found for this Master'; END IF;
 IF r.phase<>2 OR clock_timestamp()<r.ready_at OR clock_timestamp()>=r.expires_at THEN RAISE EXCEPTION 'Confirmation not ready, expired or already used'; END IF;
 IF p_phrase IS DISTINCT FROM 'DELETE '||r.site_name OR p_digest IS DISTINCT FROM r.digest THEN RAISE EXCEPTION 'Site confirmation or digest does not match'; END IF;
 IF octet_length(p_archive_text)>20*1024*1024 OR p_archive_text::jsonb IS DISTINCT FROM r.archive THEN RAISE EXCEPTION 'Re-selected recovery file does not match this request'; END IF;
 LOCK TABLE public.aaw_receipt_attachments,public.aaw_billing_document_history,public.aaw_billing_documents,public.aaw_client_payments,public.aaw_operational_audit,public.daily_production_audit,public.daily_production_entries,public.food_daily_attendance,public.food_grocery,public.food_settlement_workers,public.food_settlements,public.site_cash_ledger,public.site_expenses,public.sites,public.worker_advances,public.worker_attendance,public.worker_food_periods,public.worker_salary_payments,public.worker_salary_rates,public.workers IN SHARE ROW EXCLUSIVE MODE;
 current_data:=aaw_private.site_snapshot(r.site_id);
 IF current_data IS DISTINCT FROM r.archive THEN RAISE EXCEPTION 'Site records changed after preview. Prepare a new recovery file and confirm again'; END IF;
 INSERT INTO aaw_private.site_delete_context(transaction_id,actor_id,site_id) VALUES(txid_current(),auth.uid(),r.site_id);
 -- Explicit child-first statements, no TRUNCATE, CASCADE, session_replication_role or disabled triggers.
 DELETE FROM public.aaw_receipt_attachments WHERE site_id=r.site_id;
 DELETE FROM public.site_cash_ledger WHERE site_id=r.site_id;
 DELETE FROM public.food_settlement_workers x USING public.food_settlements p WHERE p.id=x.settlement_id AND p.site_id=r.site_id;
 DELETE FROM public.aaw_client_payments x USING public.aaw_billing_documents p WHERE p.id=x.document_id AND p.site_id=r.site_id;
 DELETE FROM public.aaw_billing_document_history x USING public.aaw_billing_documents p WHERE p.id=x.document_id AND p.site_id=r.site_id;
 DELETE FROM public.food_settlements WHERE site_id=r.site_id;
 DELETE FROM public.worker_salary_payments WHERE site_id=r.site_id;
 DELETE FROM public.worker_advances WHERE site_id=r.site_id;
 DELETE FROM public.worker_attendance WHERE site_id=r.site_id;
 DELETE FROM public.worker_salary_rates WHERE site_id=r.site_id;
 DELETE FROM public.food_daily_attendance WHERE site_id=r.site_id;
 DELETE FROM public.worker_food_periods WHERE site_id=r.site_id;
 DELETE FROM public.food_grocery WHERE site_id=r.site_id;
 DELETE FROM public.site_expenses WHERE site_id=r.site_id;
 DELETE FROM public.daily_production_entries WHERE site_id=r.site_id;
 DELETE FROM public.aaw_billing_documents WHERE site_id=r.site_id;
 DELETE FROM public.workers WHERE site_id=r.site_id;
 IF (aaw_private.site_snapshot(r.site_id)->'data')<>'{"workers": [], "worker_attendance": [], "worker_advances": [], "worker_salary_payments": [], "worker_salary_rates": [], "worker_food_periods": [], "food_grocery": [], "food_settlements": [], "site_expenses": [], "site_cash_ledger": [], "daily_production_entries": [], "food_daily_attendance": [], "aaw_billing_documents": [], "food_settlement_workers": [], "aaw_billing_document_history": [], "aaw_client_payments": [], "aaw_receipt_attachments": []}'::jsonb THEN RAISE EXCEPTION 'Delete incomplete; transaction rolled back'; END IF;
 DELETE FROM aaw_private.site_delete_context WHERE transaction_id=txid_current();
 SELECT jsonb_object_agg(key,jsonb_array_length(value)) INTO counts FROM jsonb_each(r.archive->'data');
 INSERT INTO public.aaw_operational_audit(table_name,row_id,site_id,actor_id,operation,new_values)
 VALUES('site_records',r.site_id::text,r.site_id,auth.uid(),'SITE_HARD_DELETE',jsonb_build_object('request_id',r.id,'counts',counts,'digest',r.digest,'reason',r.reason));
 UPDATE aaw_private.site_delete_requests SET phase=3,deleted_at=clock_timestamp(),result=counts WHERE id=r.id;
 RETURN jsonb_build_object('deleted',true,'request_id',r.id,'site_name',r.site_name,'counts',counts,'audit_retained',true);
END $$;
