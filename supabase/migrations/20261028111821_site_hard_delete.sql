-- Owner-authorized site-record hard delete. Installing this migration deletes no business records.
-- Recovery archives and append-only audit remain; site configuration and logins remain.
CREATE SCHEMA aaw_private;
REVOKE ALL ON SCHEMA aaw_private FROM PUBLIC,anon,authenticated;
GRANT USAGE ON SCHEMA aaw_private TO authenticated;
CREATE TABLE aaw_private.site_delete_requests(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), actor_id uuid NOT NULL, site_id uuid NOT NULL,
 site_name text NOT NULL, archive jsonb NOT NULL, digest text NOT NULL,
 phase integer NOT NULL DEFAULT 1 CHECK(phase IN(1,2,3)), reason text,
 ready_at timestamptz NOT NULL DEFAULT clock_timestamp()+interval '8 seconds',
 expires_at timestamptz NOT NULL DEFAULT clock_timestamp()+interval '15 minutes',
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(), deleted_at timestamptz, result jsonb
);
CREATE TABLE aaw_private.site_delete_context(transaction_id bigint PRIMARY KEY,actor_id uuid NOT NULL,site_id uuid NOT NULL);
ALTER TABLE aaw_private.site_delete_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE aaw_private.site_delete_context ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA aaw_private FROM PUBLIC,anon,authenticated;

CREATE FUNCTION aaw_private.purge_context(p_site uuid) RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path='' AS $$
 SELECT public.is_master_admin() AND EXISTS(SELECT 1 FROM aaw_private.site_delete_context
 WHERE transaction_id=pg_catalog.txid_current() AND actor_id=auth.uid() AND site_id=p_site);
$$;
REVOKE ALL ON FUNCTION aaw_private.purge_context(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION aaw_private.purge_context(uuid) TO authenticated;
-- Keep normal final-settlement locks; permit DELETE only inside the verified purge transaction.
CREATE OR REPLACE FUNCTION public.guard_final_settlement() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
 IF TG_OP='DELETE' AND aaw_private.purge_context(OLD.site_id) THEN RETURN OLD; END IF;
 IF OLD.status='final' THEN RAISE EXCEPTION 'Final settlement cannot be edited or deleted'; END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF; RETURN NEW;
END $$;
CREATE OR REPLACE FUNCTION public.guard_final_settlement_worker() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
DECLARE s public.food_settlements;
BEGIN
 SELECT * INTO s FROM public.food_settlements WHERE id=OLD.settlement_id;
 IF TG_OP='DELETE' AND aaw_private.purge_context(s.site_id) THEN RETURN OLD; END IF;
 IF s.status='final' THEN RAISE EXCEPTION 'Final worker food share cannot be changed'; END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF; RETURN NEW;
END $$;

CREATE FUNCTION aaw_private.site_snapshot(p_site uuid) RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$
DECLARE result jsonb:='{}'; data jsonb:='{}'; part jsonb; site public.sites; foreign_rows boolean; r record;
BEGIN
 IF auth.uid() IS NULL OR NOT public.is_master_admin() THEN RAISE EXCEPTION 'Active Master Admin access required'; END IF;
 SELECT * INTO site FROM public.sites WHERE id=p_site;
 IF site.id IS NULL THEN RAISE EXCEPTION 'Site not found'; END IF;
 -- Unknown new site-linked tables/foreign keys must be reviewed rather than silently omitted/cascaded.
 IF EXISTS(SELECT 1 FROM pg_catalog.pg_attribute a JOIN pg_catalog.pg_class c ON c.oid=a.attrelid
  WHERE c.relnamespace='public'::regnamespace AND c.relkind IN('r','p') AND a.attname='site_id' AND NOT a.attisdropped
  AND c.relname<>ALL(ARRAY['workers','worker_attendance','worker_advances','worker_salary_payments','worker_salary_rates','worker_food_periods','food_grocery','food_settlements','site_expenses','site_cash_ledger','daily_production_entries','food_daily_attendance','aaw_billing_documents','daily_production_audit','aaw_operational_audit','site_assignments','incharge_accounts'])) THEN RAISE EXCEPTION 'New site table detected; archive mapping requires review'; END IF;
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
 result:=jsonb_build_object('format','AAW-site-recovery-v1','site',to_jsonb(site),'data',data,
  'preserved','Site configuration, logins, assignments and audit trails remain. Active records have no app Undo. Recovery archive retained privately.');
 IF octet_length(result::text)>20*1024*1024 THEN RAISE EXCEPTION 'Recovery archive exceeds 20 MB; use administrator-assisted maintenance'; END IF;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION aaw_private.site_snapshot(uuid) FROM PUBLIC,anon,authenticated;

CREATE FUNCTION aaw_private.prepare_site_delete(p_site uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' SET lock_timeout='5s' AS $$
DECLARE a jsonb; d text; r aaw_private.site_delete_requests; counts jsonb;
BEGIN
 IF auth.uid() IS NULL OR NOT public.is_master_admin() THEN RAISE EXCEPTION 'Active Master Admin access required'; END IF;
 LOCK TABLE public.aaw_billing_document_history,public.aaw_billing_documents,public.aaw_client_payments,public.aaw_operational_audit,public.daily_production_audit,public.daily_production_entries,public.food_daily_attendance,public.food_grocery,public.food_settlement_workers,public.food_settlements,public.site_cash_ledger,public.site_expenses,public.sites,public.worker_advances,public.worker_attendance,public.worker_food_periods,public.worker_salary_payments,public.worker_salary_rates,public.workers IN SHARE ROW EXCLUSIVE MODE;
 DELETE FROM aaw_private.site_delete_requests WHERE phase<3 AND expires_at<clock_timestamp();
 a:=aaw_private.site_snapshot(p_site);d:=encode(sha256(convert_to(a::text,'UTF8')),'hex');
 SELECT jsonb_object_agg(key,jsonb_array_length(value)) INTO counts FROM jsonb_each(a->'data');
 INSERT INTO aaw_private.site_delete_requests(actor_id,site_id,site_name,archive,digest)
 VALUES(auth.uid(),p_site,a->'site'->>'site_name',a,d) RETURNING * INTO r;
 RETURN jsonb_build_object('request_id',r.id,'site_name',r.site_name,'site_id',r.site_id,'digest',d,
  'counts',counts,'archive_text',a::text,'ready_at',r.ready_at,'expires_at',r.expires_at,'wait_seconds',8);
END $$;

CREATE FUNCTION aaw_private.confirm_site_delete(p_request uuid,p_phrase text,p_reason text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE r aaw_private.site_delete_requests;
BEGIN
 IF auth.uid() IS NULL OR NOT public.is_master_admin() THEN RAISE EXCEPTION 'Active Master Admin access required'; END IF;
 SELECT * INTO r FROM aaw_private.site_delete_requests WHERE id=p_request FOR UPDATE;
 IF r.id IS NULL OR r.actor_id<>auth.uid() THEN RAISE EXCEPTION 'Delete request not found for this Master'; END IF;
 IF r.phase<>1 OR clock_timestamp()<r.ready_at OR clock_timestamp()>=r.expires_at THEN RAISE EXCEPTION 'Confirmation not ready, expired or already used'; END IF;
 IF p_phrase IS DISTINCT FROM 'DELETE '||r.site_name OR length(btrim(coalesce(p_reason,''))) NOT BETWEEN 5 AND 500 THEN RAISE EXCEPTION 'Type DELETE followed by the exact site name and enter a reason'; END IF;
 UPDATE aaw_private.site_delete_requests SET phase=2,reason=btrim(p_reason),ready_at=clock_timestamp()+interval '8 seconds' WHERE id=r.id RETURNING * INTO r;
 RETURN jsonb_build_object('request_id',r.id,'ready_at',r.ready_at,'wait_seconds',8);
END $$;

CREATE FUNCTION aaw_private.execute_site_delete(p_request uuid,p_phrase text,p_digest text,p_archive_text text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' SET lock_timeout='5s' AS $$
DECLARE r aaw_private.site_delete_requests; current_data jsonb; counts jsonb; deleted bigint; t text;
BEGIN
 IF auth.uid() IS NULL OR NOT public.is_master_admin() THEN RAISE EXCEPTION 'Active Master Admin access required'; END IF;
 SELECT * INTO r FROM aaw_private.site_delete_requests WHERE id=p_request FOR UPDATE;
 IF r.id IS NULL OR r.actor_id<>auth.uid() THEN RAISE EXCEPTION 'Delete request not found for this Master'; END IF;
 IF r.phase<>2 OR clock_timestamp()<r.ready_at OR clock_timestamp()>=r.expires_at THEN RAISE EXCEPTION 'Confirmation not ready, expired or already used'; END IF;
 IF p_phrase IS DISTINCT FROM 'DELETE '||r.site_name OR p_digest IS DISTINCT FROM r.digest THEN RAISE EXCEPTION 'Site confirmation or digest does not match'; END IF;
 IF octet_length(p_archive_text)>20*1024*1024 OR p_archive_text::jsonb IS DISTINCT FROM r.archive THEN RAISE EXCEPTION 'Re-selected recovery file does not match this request'; END IF;
 LOCK TABLE public.aaw_billing_document_history,public.aaw_billing_documents,public.aaw_client_payments,public.aaw_operational_audit,public.daily_production_audit,public.daily_production_entries,public.food_daily_attendance,public.food_grocery,public.food_settlement_workers,public.food_settlements,public.site_cash_ledger,public.site_expenses,public.sites,public.worker_advances,public.worker_attendance,public.worker_food_periods,public.worker_salary_payments,public.worker_salary_rates,public.workers IN SHARE ROW EXCLUSIVE MODE;
 current_data:=aaw_private.site_snapshot(r.site_id);
 IF current_data IS DISTINCT FROM r.archive THEN RAISE EXCEPTION 'Site records changed after preview. Prepare a new recovery file and confirm again'; END IF;
 INSERT INTO aaw_private.site_delete_context(transaction_id,actor_id,site_id) VALUES(txid_current(),auth.uid(),r.site_id);
 -- Explicit child-first statements, no TRUNCATE, CASCADE, session_replication_role or disabled triggers.
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
 IF (aaw_private.site_snapshot(r.site_id)->'data')<>'{"workers": [], "worker_attendance": [], "worker_advances": [], "worker_salary_payments": [], "worker_salary_rates": [], "worker_food_periods": [], "food_grocery": [], "food_settlements": [], "site_expenses": [], "site_cash_ledger": [], "daily_production_entries": [], "food_daily_attendance": [], "aaw_billing_documents": [], "food_settlement_workers": [], "aaw_billing_document_history": [], "aaw_client_payments": []}'::jsonb THEN RAISE EXCEPTION 'Delete incomplete; transaction rolled back'; END IF;
 DELETE FROM aaw_private.site_delete_context WHERE transaction_id=txid_current();
 SELECT jsonb_object_agg(key,jsonb_array_length(value)) INTO counts FROM jsonb_each(r.archive->'data');
 INSERT INTO public.aaw_operational_audit(table_name,row_id,site_id,actor_id,operation,new_values)
 VALUES('site_records',r.site_id::text,r.site_id,auth.uid(),'SITE_HARD_DELETE',jsonb_build_object('request_id',r.id,'counts',counts,'digest',r.digest,'reason',r.reason));
 UPDATE aaw_private.site_delete_requests SET phase=3,deleted_at=clock_timestamp(),result=counts WHERE id=r.id;
 RETURN jsonb_build_object('deleted',true,'request_id',r.id,'site_name',r.site_name,'counts',counts,'audit_retained',true);
END $$;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA aaw_private FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION aaw_private.purge_context(uuid),aaw_private.prepare_site_delete(uuid),aaw_private.confirm_site_delete(uuid,text,text),aaw_private.execute_site_delete(uuid,text,text,text) TO authenticated;
-- Invoker wrappers expose only the three checked operations to PostgREST.
CREATE FUNCTION public.aaw_prepare_site_delete(p_site uuid) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT aaw_private.prepare_site_delete(p_site) $$;
CREATE FUNCTION public.aaw_confirm_site_delete(p_request uuid,p_phrase text,p_reason text) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT aaw_private.confirm_site_delete(p_request,p_phrase,p_reason) $$;
CREATE FUNCTION public.aaw_execute_site_delete(p_request uuid,p_phrase text,p_digest text,p_archive_text text) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT aaw_private.execute_site_delete(p_request,p_phrase,p_digest,p_archive_text) $$;
REVOKE ALL ON FUNCTION public.aaw_prepare_site_delete(uuid),public.aaw_confirm_site_delete(uuid,text,text),public.aaw_execute_site_delete(uuid,text,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.aaw_prepare_site_delete(uuid),public.aaw_confirm_site_delete(uuid,text,text),public.aaw_execute_site_delete(uuid,text,text,text) TO authenticated;
NOTIFY pgrst,'reload schema';
