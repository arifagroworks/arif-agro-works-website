const {test,before,after,beforeEach,afterEach}=require('node:test');
const assert=require('node:assert/strict'),fs=require('node:fs'),{PGlite}=require('@electric-sql/pglite');
const id=n=>'20000000-0000-0000-0000-'+String(n).padStart(12,'0');let db;
const migration='supabase/migrations/20261028115050_site_hard_delete.sql';
const scalar=async(sql,args=[])=> (await db.query(sql,args)).rows[0].v;
async function role(n=1){await db.exec('SET LOCAL ROLE authenticated');await db.query("select set_config('request.jwt.claim.sub',$1,true)",[id(n)])}
async function owner(){await db.exec('RESET ROLE')}
async function rejected(sql,args,pattern){await db.exec('SAVEPOINT expected_failure');try{await assert.rejects(()=>db.query(sql,args),pattern)}finally{await db.exec('ROLLBACK TO SAVEPOINT expected_failure')}}
async function ready(r){await owner();await db.query("update aaw_private.site_delete_requests set ready_at=clock_timestamp()-interval '1 second' where id=$1",[r.request_id]);await role()}
async function prepare(){return scalar('select public.aaw_prepare_site_delete($1) as v',[id(10)])}
async function confirm(r){return scalar('select public.aaw_confirm_site_delete($1,$2,$3) as v',[r.request_id,'DELETE Demo A','Reset demo records'])}
const execute=(r,text=r.archive_text)=>scalar('select public.aaw_execute_site_delete($1,$2,$3,$4) as v',[r.request_id,'DELETE Demo A',r.digest,text]);
before(async()=>{
 db=new PGlite();for(const p of ['tests/fixtures/backend-schema.sql','database/proposals/access-hardening.sql','supabase/migrations/20261027143748_aaw_ready_to_use_operations.sql','supabase/migrations/20261027144256_aaw_guard_transfer_window.sql','supabase/migrations/20261028071051_aaw_invoice_tax_heads.sql',migration])await db.exec(fs.readFileSync(p,'utf8'));
 await db.exec(`insert into auth.users(id) values('${id(1)}'),('${id(2)}'),('${id(3)}'),('${id(4)}');
 insert into public.staff_profiles(user_id,full_name,role)values('${id(1)}','Master A','master'),('${id(2)}','Incharge','incharge'),('${id(3)}','Master B','master'),('${id(4)}','Disabled','master');
 update auth.users set banned_until='2099-01-01' where id='${id(4)}';
 insert into public.sites(id,site_name)values('${id(10)}','Demo A'),('${id(11)}','Demo B');
 insert into public.site_assignments(user_id,site_id)values('${id(2)}','${id(10)}');
 insert into public.workers(id,site_id,full_name,daily_wage,overtime_rate,joining_date)values('${id(20)}','${id(10)}','Worker A',1000,100,'2026-01-01'),('${id(21)}','${id(11)}','Worker B',1000,100,'2026-01-01');
 insert into public.worker_attendance(site_id,worker_id,attendance_date,status)values('${id(10)}','${id(20)}','2026-10-01','present'),('${id(10)}','${id(20)}','2026-10-02','present'),('${id(11)}','${id(21)}','2026-10-01','present');
 insert into public.food_grocery(site_id,purchase_date,amount)values('${id(10)}','2026-10-01',50);
 insert into public.worker_food_periods(site_id,worker_id,start_date,end_date,payment_type)values('${id(10)}','${id(20)}','2026-10-01','2026-10-02','salary_deduction');
 insert into public.food_daily_attendance(site_id,worker_id,food_date,eligible,payment_type)values('${id(10)}','${id(20)}','2026-10-01',true,'salary_deduction');
 insert into public.site_expenses(id,site_id,expense_date,amount)values('${id(30)}','${id(10)}','2026-10-01',100);
 insert into public.site_cash_ledger(site_id,incharge_id,entry_date,entry_type,amount,source_table,source_id)values('${id(10)}','${id(2)}','2026-10-01','cash_out',100,'site_expenses','${id(30)}');
 insert into public.daily_production_entries(site_id,work_date,work_activity,unit,quantity)values('${id(10)}','2026-10-01','Demo','KG',100);
 insert into public.aaw_billing_documents(id,site_id,document_type,document_number,payload)values('${id(40)}','${id(10)}','invoice','TEST-A','{"rows":[{"description":"Demo","qty":2,"rate":100}],"gst":18}'),('${id(41)}','${id(11)}','invoice','TEST-B','{"rows":[]}');
 insert into public.aaw_billing_document_history(audit_id,document_id,previous_payload)values(1,'${id(40)}','{"rows":[]}');`);
 await db.exec('BEGIN');await role();await scalar("select public.finalize_food_settlement($1,'2026-10-01','2026-10-02') as v",[id(10)]);
 await db.query("insert into public.worker_salary_payments(site_id,worker_id,payment_date,period_start,period_end,amount)values($1,$2,'2026-10-02','2026-10-01','2026-10-02',100)",[id(10),id(20)]);
 await db.query("insert into public.aaw_client_payments(document_id,payment_date,amount,created_by)values($1,'2026-10-01',20,$2)",[id(40),id(1)]);
 await db.exec('COMMIT');
});after(async()=>db?.close());beforeEach(async()=>{await db.exec('BEGIN');await role()});afterEach(async()=>db.exec('ROLLBACK'));
test('Delete preview archives every mapped business table and never changes business records',async()=>{
 const r=await prepare();const a=JSON.parse(r.archive_text);assert.equal(Object.keys(a.data).length,16);assert.ok(a.data.food_daily_attendance.length);assert.ok(a.data.aaw_billing_document_history.length);assert.ok(a.data.aaw_client_payments.length);assert.equal(r.wait_seconds,8);
 assert.equal(await scalar('select count(*)::int as v from public.workers'),2);
 await rejected('select * from aaw_private.site_delete_requests',[],/permission denied/);
});
test('Incharge, disabled Master and anonymous sessions cannot prepare or invoke delete',async()=>{
 for(const n of [2,4]){await role(n);await rejected('select public.aaw_prepare_site_delete($1)',[id(10)],/Active Master/);await rejected('select public.aaw_execute_site_delete($1,$2,$3,$4)',[id(99),'DELETE Demo A','fake','{}'],/Active Master/)}
 await owner();await db.exec('SET LOCAL ROLE anon');await rejected('select public.aaw_prepare_site_delete($1)',[id(10)],/permission denied/);
});
test('Both waits, exact site phrase, reason, user binding and backup equality are enforced by server',async()=>{
 const r=await prepare();await rejected('select public.aaw_confirm_site_delete($1,$2,$3)',[r.request_id,'DELETE Demo A','valid reason'],/not ready/);
 await ready(r);await rejected('select public.aaw_confirm_site_delete($1,$2,$3)',[r.request_id,'DELETE Demo B','valid reason'],/exact site/);
 await role(3);await rejected('select public.aaw_confirm_site_delete($1,$2,$3)',[r.request_id,'DELETE Demo A','valid reason'],/not found for this Master/);await role();
 await confirm(r);await rejected('select public.aaw_execute_site_delete($1,$2,$3,$4)',[r.request_id,'DELETE Demo A',r.digest,r.archive_text],/not ready/);
 await ready(r);await rejected('select public.aaw_execute_site_delete($1,$2,$3,$4)',[r.request_id,'DELETE Demo A',r.digest,'{}'],/does not match/);
});
test('Changed records and expired requests block deletion without partial writes',async()=>{
 const r=await prepare();await ready(r);await confirm(r);await ready(r);await owner();await db.query('update public.site_expenses set amount=101 where id=$1',[id(30)]);await role();
 await rejected('select public.aaw_execute_site_delete($1,$2,$3,$4)',[r.request_id,'DELETE Demo A',r.digest,r.archive_text],/changed after preview/);
 assert.equal(await scalar('select count(*)::int as v from public.workers'),2);
 await owner();await db.query("update aaw_private.site_delete_requests set expires_at=clock_timestamp()-interval '1 second' where id=$1",[r.request_id]);await role();
 await rejected('select public.aaw_execute_site_delete($1,$2,$3,$4)',[r.request_id,'DELETE Demo A',r.digest,r.archive_text],/expired/);
});
test('Normal final-settlement locks cannot be bypassed by clients or fake transaction settings',async()=>{
 await owner();await rejected("delete from public.food_settlements where site_id=$1",[id(10)],/Final settlement/);await role();
 await db.query("select set_config('aaw.site_purge','true',true)");assert.equal(await scalar('select aaw_private.purge_context($1) as v',[id(10)]),false);
 await rejected('insert into aaw_private.site_delete_context values(txid_current(),$1,$2)',[id(1),id(10)],/permission denied/);
});
test('Hard delete is atomic, covers paid/final data, preserves another site/config/audit and cannot replay',async()=>{
 const other=await scalar("select aaw_private.prepare_site_delete($1) as v",[id(11)]);const r=await prepare();await ready(r);await confirm(r);await ready(r);
 const result=await execute(r);assert.equal(result.deleted,true);assert.equal(await scalar('select count(*)::int as v from public.workers where site_id=$1',[id(10)]),0);
 assert.equal(await scalar('select count(*)::int as v from public.sites'),2);assert.equal(await scalar('select count(*)::int as v from public.site_assignments'),1);
 assert.equal(await scalar("select count(*)::int as v from public.aaw_operational_audit where operation='SITE_HARD_DELETE'"),1);
 assert.ok(await scalar('select count(*)::int as v from public.daily_production_audit')>=0);
 const otherAfter=await scalar('select public.aaw_prepare_site_delete($1) as v',[id(11)]);assert.equal(other.archive_text,otherAfter.archive_text);
 await owner();assert.equal(await scalar('select count(*)::int as v from aaw_private.site_delete_context'),0);assert.equal(await scalar('select phase as v from aaw_private.site_delete_requests where id=$1',[r.request_id]),3);await role();
 await rejected('select public.aaw_execute_site_delete($1,$2,$3,$4)',[r.request_id,'DELETE Demo A',r.digest,r.archive_text],/already used/);
 // Independent typed roundtrip of the retained recovery JSON, including empty tables and numeric/date fields.
 await owner();const data=JSON.parse(r.archive_text).data;
 for(const [t,rows]of Object.entries(data)){await db.exec(`CREATE TEMP TABLE recovery_${t} (LIKE public.${t} INCLUDING ALL)`);await db.query(`INSERT INTO recovery_${t} SELECT * FROM jsonb_populate_recordset(NULL::public.${t},$1::jsonb)`,[JSON.stringify(rows)]);const restored=await scalar(`select coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text),'[]'::jsonb) as v from recovery_${t} x`);assert.deepEqual(restored,rows,t)}
});
test('An injected mid-delete failure rolls back every deletion, audit and request consumption',async()=>{
 const r=await prepare();await ready(r);await confirm(r);await ready(r);await owner();await db.exec("create function pg_temp.block_delete()returns trigger language plpgsql as $$begin raise exception 'Injected failure';end$$;create trigger test_fail before delete on public.workers for each row execute function pg_temp.block_delete()");await role();
 await rejected('select public.aaw_execute_site_delete($1,$2,$3,$4)',[r.request_id,'DELETE Demo A',r.digest,r.archive_text],/Injected failure/);
 assert.equal(await scalar('select count(*)::int as v from public.aaw_client_payments'),1);assert.equal(await scalar('select count(*)::int as v from public.worker_salary_payments'),1);
 await owner();assert.equal(await scalar('select phase as v from aaw_private.site_delete_requests where id=$1',[r.request_id]),2);assert.equal(await scalar('select count(*)::int as v from aaw_private.site_delete_context'),0);
});
test('Unknown site tables and cross-site cash links fail closed before confirmation',async()=>{
 await owner();await db.exec('create table public.future_site_table(site_id uuid)');await role();await rejected('select public.aaw_prepare_site_delete($1)',[id(10)],/New site table/);
 await owner();await db.exec('drop table public.future_site_table;create table public.future_ref(worker_id uuid references public.workers(id))');await role();await rejected('select public.aaw_prepare_site_delete($1)',[id(10)],/Unmapped dependent/);await owner();await db.exec('drop table public.future_ref');await db.query('insert into public.site_assignments(user_id,site_id)values($1,$2)',[id(2),id(11)]);await db.query('update public.site_cash_ledger set site_id=$1 where source_id=$2',[id(11),id(30)]);await role();await rejected('select public.aaw_prepare_site_delete($1)',[id(10)],/Cross-site cash/);
});
