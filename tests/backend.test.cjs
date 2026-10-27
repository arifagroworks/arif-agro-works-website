const {test,before,after}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const {PGlite}=require('@electric-sql/pglite');
const uid=n=>'00000000-0000-0000-0000-'+String(n).padStart(12,'0');
let db;
async function as(user,fn){await db.exec('BEGIN; SET LOCAL ROLE authenticated;');try{await db.query("select set_config('request.jwt.claim.sub',$1,true)",[uid(user)]);return await fn();}finally{await db.exec('ROLLBACK');}}
async function scalar(sql,params=[]){return (await db.query(sql,params)).rows[0].v;}
before(async()=>{
 db=new PGlite();await db.exec(fs.readFileSync('tests/fixtures/backend-schema.sql','utf8'));
 await db.exec(`INSERT INTO auth.users(id,banned_until) VALUES ('${uid(1)}',null),('${uid(2)}',null),('${uid(3)}','2099-01-01'),('${uid(4)}','2099-01-01');
 INSERT INTO public.staff_profiles(user_id,full_name,role) VALUES ('${uid(1)}','Demo Master','master'),('${uid(2)}','Demo Incharge','incharge'),('${uid(3)}','Demo Disabled Incharge','incharge'),('${uid(4)}','Demo Disabled Master','master');
 INSERT INTO public.sites(id,site_name,is_active) VALUES ('${uid(10)}','Demo A',true),('${uid(11)}','Demo B',true);
 INSERT INTO public.site_assignments(user_id,site_id) VALUES ('${uid(2)}','${uid(10)}'),('${uid(3)}','${uid(10)}');
 INSERT INTO public.workers(id,site_id,full_name,daily_wage,overtime_rate) VALUES ('${uid(20)}','${uid(10)}','Demo Worker A',1000,100),('${uid(21)}','${uid(11)}','Demo Worker B',1000,100);
 INSERT INTO public.worker_attendance(id,worker_id,site_id,attendance_date,status,overtime_hours) VALUES ('${uid(30)}','${uid(20)}','${uid(10)}','2026-10-01','present',2),('${uid(31)}','${uid(20)}','${uid(10)}','2026-10-02','half_day',0);
 INSERT INTO public.food_grocery(id,site_id,purchase_date,amount) VALUES ('${uid(40)}','${uid(10)}','2026-10-01',300);
 INSERT INTO public.worker_food_periods(id,site_id,worker_id,start_date,end_date,payment_type) VALUES ('${uid(41)}','${uid(10)}','${uid(20)}','2026-10-01','2026-10-03','salary_deduction');`);
 // Verify the two defects against the unchanged schema before applying the proposal locally.
 assert.equal(await as(3,()=>scalar('select public.daily_production_site_access($1) as v',[uid(10)])),true,'Baseline reproduces disabled Production access');
 await as(1,()=>db.query("insert into public.worker_food_periods(site_id,worker_id,start_date,end_date,payment_type) values ($1,$2,'2026-11-01','2026-11-02','company_paid')",[uid(10),uid(21)]));
 await db.exec(fs.readFileSync('database/proposals/access-hardening.sql','utf8'));
});
after(async()=>{await db?.close();});
test('Active Incharge can access only the assigned site',async()=>as(2,async()=>{
 assert.equal(await scalar('select public.can_access_site($1) as v',[uid(10)]),true);
 assert.equal(await scalar('select public.can_access_site($1) as v',[uid(11)]),false);
 const rows=(await db.query('select site_id from public.workers')).rows;
 assert.deepEqual(rows,[{site_id:uid(10)}]);
}));
test('Disabled Incharge loses Production access even with the old user claim',async()=>as(3,async()=>{
 assert.equal(await scalar('select public.daily_production_site_access($1) as v',[uid(10)]),false);
 assert.equal(await scalar('select count(*)::int as v from public.workers'),0);
}));
test('Disabled Master loses Master and billing authority',async()=>as(4,async()=>{
 assert.equal(await scalar('select public.is_master_admin() as v'),false);
 assert.equal(await scalar('select public.is_staff_master() as v'),false);
 await assert.rejects(()=>db.query("insert into public.aaw_billing_documents(document_type,document_number,created_by,updated_by) values ('invoice','DEMO', $1,$1)",[uid(4)]),/row-level security/);
}));
test('Food policy rejects a Worker from a different Site',async()=>as(1,async()=>{
 await assert.rejects(()=>db.query("insert into public.worker_food_periods(site_id,worker_id,start_date,end_date,payment_type) values ($1,$2,'2026-11-01','2026-11-02','company_paid')",[uid(10),uid(21)]),/row-level security/);
}));
test('Food policy permits valid own-site periods',async()=>as(2,async()=>{
 await db.query("insert into public.worker_food_periods(site_id,worker_id,start_date,end_date,payment_type) values ($1,$2,'2026-11-01','2026-11-02','company_paid')",[uid(10),uid(20)]);
}));
test('Incharge cannot read or create Billing documents',async()=>as(2,async()=>{
 assert.equal(await scalar('select count(*)::int as v from public.aaw_billing_documents'),0);
 await assert.rejects(()=>db.query("insert into public.aaw_billing_documents(document_type,document_number,created_by,updated_by) values ('invoice','DEMO', $1,$1)",[uid(2)]),/row-level security/);
}));
test('Public callers cannot execute the trigger-only salary function',async()=>{
 assert.equal(await scalar("select has_function_privilege('anon','public.v515_salary_payment_lock()','execute') as v"),false);
 assert.equal(await scalar("select has_function_privilege('authenticated','public.dp_audit_changes_v525()','execute') as v"),false);
});
test('Salary accepts partial payment through the unchanged arithmetic guard',async()=>as(1,async()=>{
 await db.query("insert into public.worker_salary_payments(worker_id,site_id,payment_date,period_start,period_end,amount) values ($1,$2,'2026-10-02','2026-10-01','2026-10-02',500)",[uid(20),uid(10)]);
 assert.equal(await scalar('select sum(amount)::text as v from public.worker_salary_payments'),'500.00');
}));
test('Salary rejects an overpayment instead of persisting it',async()=>as(1,async()=>{
 await assert.rejects(()=>db.query("insert into public.worker_salary_payments(worker_id,site_id,payment_date,period_start,period_end,amount) values ($1,$2,'2026-10-02','2026-10-01','2026-10-02',9999)",[uid(20),uid(10)]),/PAYMENT BLOCKED/);
}));
test('Food finalization allocates exact total and locks grocery edits',async()=>as(1,async()=>{
 const id=await scalar("select public.finalize_food_settlement($1,'2026-10-01','2026-10-03') as v",[uid(10)]);
 assert.equal(await scalar('select sum(share_amount)::text as v from public.food_settlement_workers where settlement_id=$1',[id]),'300.00');
 await assert.rejects(()=>db.query('update public.food_grocery set amount=400 where id=$1',[uid(40)]),/locked/);
}));
test('Disabled account cannot use the finalized-food definer RPC',async()=>as(3,async()=>{
 await assert.rejects(()=>db.query("select * from public.get_final_food_deductions($1,'2026-10-01','2026-10-03')",[uid(10)]),/Site access denied/);
}));
test('Backend invoice measurement/GST/payable rounds correctly',async()=>{
 const payload={rows:[{l:'2',w:'3',h:'',qty:99,rate:10},{qty:3,rate:0.1}],gst:18,billStage:'regular'};
 assert.equal(await scalar('select public.aaw_invoice_payable($1::jsonb)::text as v',[JSON.stringify(payload)]),'71.15');
});
test('Food paise rounding never creates a negative last-worker share',async()=>as(1,async()=>{
 await db.query('update public.food_grocery set amount=0.02 where id=$1',[uid(40)]);
 for(const n of [22,23,24]){
  await db.query('insert into public.workers(id,site_id,full_name,daily_wage,overtime_rate) values ($1,$2,$3,1000,100)',[uid(n),uid(10),'Demo Worker '+n]);
  await db.query("insert into public.worker_food_periods(site_id,worker_id,start_date,end_date,payment_type) values ($1,$2,'2026-10-01','2026-10-03','salary_deduction')",[uid(10),uid(n)]);
 }
 const id=await scalar("select public.finalize_food_settlement($1,'2026-10-01','2026-10-03') as v",[uid(10)]);
 assert.equal(await scalar('select sum(share_amount)::text as v from public.food_settlement_workers where settlement_id=$1',[id]),'0.02');
 assert.equal(await scalar('select min(share_amount)::text as v from public.food_settlement_workers where settlement_id=$1',[id]),'0.00');
}));
test('Manual FOOD with whitespace still prevents double deduction at finalization',async()=>as(1,async()=>{
 await db.query("insert into public.worker_advances(worker_id,site_id,advance_date,amount,notes) values ($1,$2,'2026-10-01',50,'  FOOD: demo')",[uid(20),uid(10)]);
 await assert.rejects(()=>db.query("select public.finalize_food_settlement($1,'2026-10-01','2026-10-03')",[uid(10)]),/manual FOOD advances/);
}));
test('Finalized Food rejects a later manual FOOD advance with leading spaces',async()=>as(1,async()=>{
 await db.query("select public.finalize_food_settlement($1,'2026-10-01','2026-10-03')",[uid(10)]);
 await assert.rejects(()=>db.query("insert into public.worker_advances(worker_id,site_id,advance_date,amount,notes) values ($1,$2,'2026-10-01',50,'  FOOD: demo')",[uid(20),uid(10)]),/conflicts with finalized/);
}));
