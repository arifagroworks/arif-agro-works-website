-- Read-only browsing and policy/index optimisation. No business-record mutations.
CREATE INDEX IF NOT EXISTS aaw_history_document_idx ON public.aaw_billing_document_history(document_id);
CREATE INDEX IF NOT EXISTS aaw_assignments_site_idx ON public.site_assignments(site_id);
CREATE INDEX IF NOT EXISTS aaw_cash_site_idx ON public.site_cash_ledger(site_id);
CREATE INDEX IF NOT EXISTS aaw_advances_worker_site_idx ON public.worker_advances(worker_id,site_id);
CREATE INDEX IF NOT EXISTS aaw_food_period_worker_idx ON public.worker_food_periods(worker_id);
CREATE INDEX IF NOT EXISTS aaw_salary_worker_site_idx ON public.worker_salary_payments(worker_id,site_id);
CREATE INDEX IF NOT EXISTS aaw_rates_site_idx ON public.worker_salary_rates(site_id);
CREATE INDEX IF NOT EXISTS aaw_billing_browse_idx ON public.aaw_billing_documents(updated_at DESC,id DESC);
CREATE INDEX IF NOT EXISTS aaw_billing_source_hash_idx ON public.aaw_billing_documents((payload#>>'{raImport,sourceHash}'));
-- Equivalent OR of the prior permissive policies for each action. Restrictive and other-role policies remain untouched.
DO $$
DECLARE t text; old jsonb; x jsonb; command text; q text; c text; expr text;
BEGIN
 FOR t IN SELECT DISTINCT tablename FROM pg_policies WHERE schemaname='public' AND roles=ARRAY['authenticated']::name[] AND permissive='PERMISSIVE' LOOP
  SELECT jsonb_agg(to_jsonb(p)) INTO old FROM pg_policies p WHERE schemaname='public' AND tablename=t AND roles=ARRAY['authenticated']::name[] AND permissive='PERMISSIVE';
  FOR x IN SELECT * FROM jsonb_array_elements(old) LOOP EXECUTE format('DROP POLICY %I ON public.%I',x->>'policyname',t); END LOOP;
  FOREACH command IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE'] LOOP
   q:=NULL;c:=NULL;
   FOR x IN SELECT * FROM jsonb_array_elements(old) WHERE value->>'cmd' IN('ALL',command) LOOP
    expr:=replace(coalesce(x->>'qual','true'),'auth.uid()','(SELECT auth.uid())');
    q:=concat_ws(' OR ',q,'('||expr||')');
    expr:=replace(coalesce(x->>'with_check',x->>'qual','true'),'auth.uid()','(SELECT auth.uid())');
    c:=concat_ws(' OR ',c,'('||expr||')');
   END LOOP;
   IF q IS NOT NULL THEN
    EXECUTE format('CREATE POLICY %I ON public.%I FOR %s TO authenticated %s %s','aaw_access_'||lower(command),t,command,
     CASE WHEN command IN('SELECT','UPDATE','DELETE') THEN 'USING ('||q||')' ELSE '' END,
     CASE WHEN command IN('INSERT','UPDATE') THEN 'WITH CHECK ('||c||')' ELSE '' END);
   END IF;
  END LOOP;
 END LOOP;
END $$;
CREATE FUNCTION public.aaw_search_billing_documents(p_search text DEFAULT '',p_type text DEFAULT '',p_offset integer DEFAULT 0,p_limit integer DEFAULT 50)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE result jsonb;
BEGIN
 IF auth.uid() IS NULL OR NOT public.is_master_admin() THEN RAISE EXCEPTION 'Active Master Admin access required'; END IF;
 IF length(coalesce(p_search,''))>200 OR p_offset IS NULL OR p_offset<0 OR p_offset>1000000 OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 OR p_type NOT IN('','invoice','quotation','letterhead','measurement','proforma') THEN RAISE EXCEPTION 'Invalid search parameters'; END IF;
 WITH matches AS NOT MATERIALIZED (
  SELECT d.id,d.site_id,d.document_type,d.document_number,d.document_date,d.client_name,d.payload,d.updated_at FROM public.aaw_billing_documents d LEFT JOIN public.sites s ON s.id=d.site_id
  WHERE (coalesce(p_type,'')='' OR d.document_type=p_type) AND (coalesce(p_search,'')='' OR position(lower(p_search) in lower(concat_ws(' ',d.document_number,d.client_name,s.site_name,d.document_date::text)))>0)
 ), page AS(SELECT * FROM matches ORDER BY updated_at DESC NULLS LAST,id DESC LIMIT p_limit OFFSET p_offset)
 SELECT jsonb_build_object('rows',coalesce((SELECT jsonb_agg(to_jsonb(page) ORDER BY updated_at DESC NULLS LAST,id DESC) FROM page),'[]'::jsonb),'total',(SELECT count(*) FROM matches),'offset',p_offset,'limit',p_limit) INTO result;
 RETURN result;
END $$;
CREATE FUNCTION public.aaw_next_document_number(p_type text,p_year integer) RETURNS text LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE prefix text; n bigint; candidate text;
BEGIN
 IF auth.uid() IS NULL OR NOT public.is_master_admin() THEN RAISE EXCEPTION 'Active Master Admin access required'; END IF;
 prefix:=CASE p_type WHEN 'invoice' THEN 'INV' WHEN 'quotation' THEN 'QT' WHEN 'proforma' THEN 'WP' WHEN 'measurement' THEN 'MB' WHEN 'letterhead' THEN 'LT' END;
 IF prefix IS NULL OR p_year NOT BETWEEN 2000 AND 9999 THEN RAISE EXCEPTION 'Invalid document type or year'; END IF;
 prefix:=prefix||'-'||p_year::text||'-';
 SELECT coalesce(max(substring(document_number from length(prefix)+1)::bigint),0)+1 INTO n FROM public.aaw_billing_documents WHERE document_type=p_type AND left(document_number,length(prefix))=prefix AND substring(document_number from length(prefix)+1)~'^[0-9]{1,12}$';
 candidate:=prefix||lpad(n::text,greatest(3,length(n::text)),'0'); RETURN candidate;
END $$;
CREATE FUNCTION public.aaw_find_ra_source(p_hash text) RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE found jsonb;
BEGIN
 IF auth.uid() IS NULL OR NOT public.is_master_admin() THEN RAISE EXCEPTION 'Active Master Admin access required'; END IF;
 IF p_hash IS NULL OR p_hash!~'^[0-9a-f]{64}$' THEN RAISE EXCEPTION 'Invalid source hash'; END IF;
 SELECT jsonb_build_object('id',id,'document_number',document_number) INTO found FROM public.aaw_billing_documents WHERE payload#>>'{raImport,sourceHash}'=p_hash ORDER BY updated_at DESC NULLS LAST,id DESC LIMIT 1;
 RETURN found;
END $$;
REVOKE ALL ON FUNCTION public.aaw_search_billing_documents(text,text,integer,integer),public.aaw_next_document_number(text,integer),public.aaw_find_ra_source(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.aaw_search_billing_documents(text,text,integer,integer),public.aaw_next_document_number(text,integer),public.aaw_find_ra_source(text) TO authenticated;
NOTIFY pgrst,'reload schema';
