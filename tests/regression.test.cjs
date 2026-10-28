const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const vm = require('node:vm');
const { chromium } = require('playwright');
const root = process.env.AAW_TEST_ROOT || path.resolve(__dirname, '..');
const read = p => fs.readFileSync(path.join(root, p), 'utf8');
let server, origin;
before(async () => {
  server = http.createServer((req, res) => {
    const file = path.resolve(root, '.' + new URL(req.url, 'http://localhost').pathname);
    if (!file.startsWith(root + path.sep)) { res.writeHead(403).end(); return; }
    try { res.setHeader('Content-Type', file.endsWith('.html') ? 'text/html' : file.endsWith('.js') ? 'application/javascript' : file.endsWith('.css') ? 'text/css' : 'application/octet-stream'); res.end(fs.readFileSync(file)); }
    catch { res.writeHead(404).end(); }
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  origin = `http://127.0.0.1:${server.address().port}`;

});
after(async () => { await new Promise(resolve => server?.close(resolve)); });

// All non-local requests are intercepted. The Supabase SDK itself is replaced,
// so tests cannot read or mutate production, even with a real browser session.
async function openPage(url, { role = 'master', sessionKey = 'aaw-portal-auth-master', width = 390, demoWorkers = [], operational = false, demoRows = {} } = {}) {
  const instance = await chromium.launch({ headless: true, ...(process.env.AAW_CHROMIUM_PATH ? { executablePath: process.env.AAW_CHROMIUM_PATH, args: ['--no-sandbox','--no-zygote','--single-process','--use-gl=angle','--use-angle=swiftshader','--in-process-gpu'] } : {}) });
  const context = await instance.newContext({ viewport: { width, height: 900 }, serviceWorkers: 'block' });
  const close = context.close.bind(context);
  context.close = async () => { await close(); await instance.close(); };
  const page = await context.newPage();
  page.setDefaultTimeout(5000);
  const external = [], errors = [];
  page.on('pageerror', e => errors.push(e.message));
  await context.addInitScript(({ role, sessionKey, demoWorkers, operational, demoRows }) => {
    window.mockCalls = [];
    window.mockMutations=[];window.mockRpc=[];
    window.mockSignOut = [];
    const user = { id: 'demo-user' };
    window.supabase = { createClient(_url, _key, options = {}) {
      const key = options.auth?.storageKey || 'supabase-default';
      window.mockAuthKey = key;
      let signedIn = key === sessionKey;
      return {
        auth: {
          getSession: async () => ({ data: { session: signedIn ? { user } : null }, error: null }),
          getUser: async () => ({ data: { user: signedIn ? user : null }, error: null }),
          signInWithPassword: async () => { signedIn = true; return { data: { user }, error: null }; },
          signOut: async options => { window.mockSignOut.push(options); signedIn = false; return { error: null }; }
        },
        from(table) {
          window.mockCalls.push(table);
          let data = table === 'staff_profiles' ? { role, full_name: 'Demo Staff' }
            : table === 'sites' ? [{ id: 'demo-site', site_name: 'Demo Site', is_active: true }] : table === 'site_assignments' ? [{site_id:'demo-site',user_id:'demo-user'}] : table === 'workers' ? demoWorkers : demoRows[table]||[];
          const q = new Proxy({}, { get(_target, method) {
            if (method === 'eq') return (key, value) => { if (table === 'staff_profiles' && key === 'role' && value === 'incharge') data = []; if(table==='aaw_billing_documents'&&key==='id'&&Array.isArray(data)&&data[0]?.id==='saved-row')data={id:value}; return q; };
            if (method === 'single' && table === 'aaw_billing_documents') return () => {if(Array.isArray(data)&&data.length===1&&data[0].id==='saved-row')data=data[0];return q;};
            if (method === 'then') return resolve => resolve({ data, error: null });
            if (['insert', 'update', 'delete', 'upsert'].includes(method)) {if(!operational)throw Error('Unexpected database mutation in regression test');return (...args)=>{window.mockMutations.push({table,method,args});data=[{id:'saved-row'}];return q;};}
            return () => q;
          }});
          return q;
        },
        rpc(name,args) {
          if(!operational)throw Error('Unexpected RPC in regression test');
          window.mockRpc.push({name,args});
          const answers={get_final_food_deductions:[],aaw_session_context:{user_id:'demo-user',role,full_name:'Demo Staff',enabled:true},aaw_incharge_choices:[{user_id:'demo-user',full_name:'Demo Incharge'}],aaw_food_preview:{grocery_total:300,total_food_days:3,can_finalize:true,entries:[{worker_id:'w1',full_name:'Worker One',food_days:3,payment_type:'salary_deduction',share_amount:300}]},aaw_site_financials:{billed:1000,collected:600,receivable:400,site_expenses:50,grocery_cash:100,salary_cash:300,advance_cash:50,earned_labour:500,company_food:100,cash_surplus:100,billed_operating_surplus:350}};
          const data=answers[name]||'saved-id';const query=new Proxy({},{get(_t,method){if(method==='then')return resolve=>resolve({data,error:null});return ()=>query}});return query;
        }
      };
    }};
  }, { role, sessionKey, demoWorkers, operational, demoRows });
  await context.route('**/*', route => {
    const requestUrl = route.request().url();
    if (requestUrl.startsWith(origin + '/')) return route.continue();
    external.push(requestUrl);
    // The SDK is supplied by addInitScript; never download remote code.
    if (/cdn\.jsdelivr\.net\/npm\/@supabase\//.test(requestUrl) || /supabase.*\.js/.test(requestUrl)) return route.fulfill({ contentType: 'application/javascript', body: '' });
    return route.abort();
  });
  await page.goto(origin + url);
  return { page, context, external, errors };
}

for (const role of ['master', 'incharge', 'direct']) {
  test(`Food reuses only the ${role} portal session`, async () => {
    const { page, context, external, errors } = await openPage(`/portal/food-v518-fixed.html?role=${role}`, {
      role: role === 'direct' ? 'master' : role, sessionKey: `aaw-portal-auth-${role}`
    });
    try {
      await page.waitForFunction(() => !document.getElementById('app').hidden);
      assert.equal(await page.evaluate(() => window.mockAuthKey), `aaw-portal-auth-${role}`);
      assert.equal(await page.locator('#login').isVisible(), false);
      assert.deepEqual(errors, []);
      assert.equal(external.some(u => u.includes('.supabase.co')), false);
    } finally { await context.close(); }
  });
}
test('Food rejects an account with the wrong staff role', async () => {
  const { page, context } = await openPage('/portal/food-v518-fixed.html?role=master', { role: 'incharge' });
  try {
    await page.waitForFunction(() => document.getElementById('msg').textContent.includes('Access denied'));
    assert.equal(await page.locator('#app').isVisible(), false);
    assert.deepEqual(await page.evaluate(() => window.mockSignOut), [{ scope: 'local' }]);
    assert.deepEqual(await page.evaluate(() => window.mockCalls), ['staff_profiles']);
  } finally { await context.close(); }
});
test('Food does not borrow a Master session for the Incharge page', async () => {
  const { page, context } = await openPage('/portal/food-v518-fixed.html?role=incharge');
  try {
    await page.locator('#login').waitFor({ state: 'visible' });
    assert.equal(await page.locator('#app').isVisible(), false);
    assert.deepEqual(await page.evaluate(() => window.mockCalls), []);
  } finally { await context.close(); }
});
for (const role of ['master', 'incharge']) {
  test(`Portal Food link preserves ${role} context and role tabs`, async () => {
    const { page, context } = await openPage(`/portal/index.html?role=${role}`, { role, sessionKey: `aaw-portal-auth-${role}` });
    try {
      await page.locator('#app').waitFor({ state: 'visible' }).catch(async e => { throw Error(e.message + JSON.stringify(await page.evaluate(() => ({msg:document.getElementById('loginMsg')?.textContent,errors:window.mockCalls,body:document.body.innerText.slice(-700)})))); });
      await page.locator('[data-tab="foodmanage"]').click();
      const href = await page.locator('#content a').getAttribute('href');
      assert.equal(new URL(href, origin).searchParams.get('role'), role);
      assert.equal(await page.locator('[data-tab="billing"]').count(), role === 'master' ? 1 : 0);
      assert.equal(await page.locator('[data-tab="summary"]').count(), role === 'master' ? 1 : 0);
    } finally { await context.close(); }
  });
}
test('Portal rejects a wrong-role login before loading site data', async () => {
  const { page, context } = await openPage('/portal/index.html?role=master', { role: 'incharge' });
  try {
    await page.waitForFunction(() => document.getElementById('loginMsg').textContent.includes('correct account'));
    assert.equal(await page.locator('#app').isVisible(), false);
    assert.deepEqual(await page.evaluate(() => window.mockCalls), ['staff_profiles']);
  } finally { await context.close(); }
});
for (const width of [320, 390, 768, 1440]) {
  test(`Billing has no page overflow at ${width}px; editor and print remain usable`, async () => {
    const { page, context, errors } = await openPage('/portal/AAW_Billing_Studio_Final.html', { width });
    try {
      await page.waitForFunction(() => !document.getElementById('aawGate'));
      await page.evaluate(() => {
        rows = [{ description: 'Demo fabrication item', unit: 'KG', l: '', w: '', h: '', qty: 10, rate: 25 }];
        drawRows(); render();
      });
      assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1));
      assert.equal(await page.locator('#items input[aria-label="Description"]').count(), 1);
      await page.emulateMedia({ media: 'print' });
      assert.equal(await page.locator('aside').isVisible(), false);
      assert.equal(await page.locator('#preview').isVisible(), true);
      assert.deepEqual(errors, []);
    } finally { await context.close(); }
  });
}
test('Billing denies Incharge access before querying bills', async () => {
  const { page, context } = await openPage('/portal/AAW_Billing_Studio_Final.html', { role: 'incharge' });
  try {
    await page.waitForFunction(() => document.getElementById('aawGate').textContent.includes('Access denied'));
    assert.equal(await page.locator('#aawSaveButton').isEnabled(), false);
    assert.deepEqual(await page.evaluate(() => window.mockCalls), ['staff_profiles']);
  } finally { await context.close(); }
});
test('Billing measurement, GST and decimal rounding', async () => {
  const { page, context } = await openPage('/portal/AAW_Billing_Studio_Final.html');
  try {
    const result = await page.evaluate(() => {
      rows = [{ l: '2', w: '3', h: '', qty: 99, rate: 10 }, { l: '', w: '', h: '', qty: 3, rate: 0.1 }];
      document.getElementById('gst').value = '18';
      return { line: calc(rows[0]), ...totals() };
    });
    assert.deepEqual(result, { line: { qty: 6, amount: 60 }, subtotal: 60.3, gst: 10.85, grand: 71.15 });
  } finally { await context.close(); }
});
test('Salary counts half days, OT, separate advances/food and partial payments per worker', () => {
  const source = read('portal/index.html');
  const fn = source.slice(source.indexOf('function calculateWorker('), source.indexOf('async function fullWorkers('));
  const calculate = vm.runInNewContext(fn + '; calculateWorker');
  const result = calculate({ id: 'w1', daily_wage: 1000, overtime_rate: 100 }, {
    attendance: [{ worker_id: 'w1', status: 'present', overtime_hours: 2 }, { worker_id: 'w1', status: 'half_day' }, { worker_id: 'w2', status: 'present', overtime_hours: 99 }],
    advances: [{ worker_id: 'w1', amount: 100 }, { worker_id: 'w1', amount: 50, notes: ' food: test' }],
    payments: [{ worker_id: 'w1', amount: 500 }, { worker_id: 'w2', amount: 9000 }],
    finalFood: [{ worker_id: 'w1', deduction_amount: 25 }]
  });
  assert.deepEqual(JSON.parse(JSON.stringify(result)), { days: 1.5, ot: 2, wage: 1500, otPay: 200, manualFood: 50, finalFood: 25, food: 75, advance: 100, paid: 500, gross: 1700, due: 1025 });
});
test('APK launcher references the existing approved AAW logo resource', () => {
  assert.match(read('android-app/app/src/main/AndroidManifest.xml'), /android:icon="@drawable\/aaw_logo"/);
  assert.ok(fs.statSync(path.join(root, 'android-app/app/src/main/res/drawable/aaw_logo.png')).size > 0);
});

test('Food allocates grocery costs by inclusive eligible days and payer type', async () => {
  const { page, context } = await openPage('/portal/food-v518-fixed.html?role=master');
  try {
    await page.waitForFunction(() => !document.getElementById('app').hidden);
    await page.evaluate(() => {
      $('from').value='2026-10-01';$('to').value='2026-10-03';
      workerRows=[{id:'w1',full_name:'Demo Salary'},{id:'w2',full_name:'Demo Company'}];
      groceryRows=[{purchase_date:'2026-10-02',amount:400},{purchase_date:'2026-09-30',amount:999}];
      periodRows=[{worker_id:'w1',start_date:'2026-09-30',end_date:'2026-10-03',payment_type:'salary_deduction'},
        {worker_id:'w2',start_date:'2026-10-03',end_date:'2026-10-05',payment_type:'company_paid'}];
      calculate();
    });
    const text=await page.locator('#result').innerText();
    assert.match(text,/Total Food-Days: 4/);
    assert.match(text,/Salary Share \(Preview\): ₹300\.00/);
    assert.match(text,/Company Share: ₹100\.00/);
  } finally { await context.close(); }
});
test('Food blocks misleading amounts when imported periods overlap', async () => {
  const { page, context } = await openPage('/portal/food-v518-fixed.html?role=master');
  try {
    await page.waitForFunction(() => !document.getElementById('app').hidden);
    await page.evaluate(() => {
      $('from').value='2026-10-01';$('to').value='2026-10-03';
      groceryRows=[{purchase_date:'2026-10-02',amount:400}];
      periodRows=[{worker_id:'w1',start_date:'2026-10-01',end_date:'2026-10-02',payment_type:'salary_deduction'},
        {worker_id:'w1',start_date:'2026-10-02',end_date:'2026-10-03',payment_type:'company_paid'}];
      calculate();
    });
    assert.match(await page.locator('#result').innerText(),/Calculation blocked/);
    assert.equal(await page.locator('#result table').count(),0);
  } finally { await context.close(); }
});
test('Active entry pages contain valid JavaScript', () => {
  for (const file of ['index.html','portal/index.html','portal/food-v518-fixed.html','portal/AAW_Billing_Studio_Final.html','portal/AAW_Daily_Production_V526_Restore_Test.html','portal/incharge-test-fixed.html','portal/site-assignment-test.html','portal/incharge-access-test.html','portal/salary-test.html','portal/AAW_Site_Backup_Master.html','portal/v519-guard-check.html']) {
    for (const match of read(file).matchAll(/<script[^>]*>([\s\S]*?)<\/script>/gi)) new vm.Script(match[1], {filename:file});
  }
});

test('Native splash and Android 12+ startup use AAW branding, with no Android placeholder resources', () => {
  const splash=read('android-app/app/src/main/res/layout/activity_splash.xml');
  assert.match(splash,/android:src="@drawable\/aaw_logo"/);
  assert.match(read('android-app/app/src/main/res/values-v31/styles.xml'),/windowSplashScreenAnimatedIcon">@drawable\/aaw_logo/);
  const dir=path.join(root,'android-app/app/src/main');
  for(const file of fs.readdirSync(dir,{recursive:true}).filter(f=>/\.(xml|java)$/.test(f))) {
    assert.doesNotMatch(fs.readFileSync(path.join(dir,file),'utf8'),/sym_def_app_icon/,file);
  }
  assert.match(read('android-app/app/build.gradle'),/versionCode 5/);
});
test('Android viewport handles system bars and cutouts on current and older Android', () => {
  const java=read('android-app/app/src/main/java/com/arifagroworks/combined/MainActivity.java');
  assert.match(java,/WindowInsets.Type.systemBars\(\)/);
  assert.match(java,/WindowInsets.Type.displayCutout\(\)/);
  assert.match(java,/getSystemWindowInsetTop/);
  assert.match(java,/protectInsets\(viewport\)/);
});
for(const role of ['master','incharge']) {
  test(`Daily Production shares ${role} session and preserves authorized site`, async () => {
    const {page,context,errors}=await openPage(`/portal/AAW_Daily_Production_V526_Restore_Test.html?role=${role}&site_id=demo-site`,{role,sessionKey:`aaw-portal-auth-${role}`});
    try {
      await page.locator('#f').waitFor({state:'visible'});
      assert.equal(await page.evaluate(()=>window.mockAuthKey),`aaw-portal-auth-${role}`);
      assert.equal(await page.locator('#site').inputValue(),'demo-site');
      assert.equal(await page.locator('#site').isDisabled(),true);
      assert.deepEqual(errors,[]);
    }finally{await context.close();}
  });
}
test('Daily Production refuses a wrong-role session before querying sites',async()=>{
  const {page,context}=await openPage('/portal/AAW_Daily_Production_V526_Restore_Test.html?role=master',{role:'incharge'});
  try{
    await page.waitForFunction(()=>document.getElementById('authError').textContent.includes('Access denied'));
    assert.equal(await page.locator('#f').isVisible(),false);
    assert.deepEqual(await page.evaluate(()=>window.mockCalls),['staff_profiles']);
  }finally{await context.close();}
});
const masterPages=[
 ['incharge-test-fixed.html','#dashboard'],['site-assignment-test.html','#app'],
 ['incharge-access-test.html',null],['salary-test.html','#app'],
 ['AAW_Site_Backup_Master.html','#tools'],['v519-guard-check.html','#run']
];
for(const [file,ready] of masterPages){
  test(`${file} reuses Master session`,async()=>{
    const {page,context,errors}=await openPage('/portal/'+file+'?role=master');
    try{
      await page.waitForFunction(()=>window.mockCalls.includes('staff_profiles'));
      if(ready)await page.locator(ready).waitFor({state:'visible'});
      if(file==='v519-guard-check.html')assert.equal(await page.locator('#run').isEnabled(),true);
      assert.equal(await page.evaluate(()=>window.mockAuthKey),'aaw-portal-auth-master');
      assert.deepEqual(errors,[]);
    }finally{await context.close();}
  });
  test(`${file} refuses Incharge profile before loading sensitive records`,async()=>{
    const {page,context}=await openPage('/portal/'+file+'?role=incharge',{role:'incharge',sessionKey:'aaw-portal-auth-incharge'});
    try{
      await page.waitForFunction(()=>window.mockCalls.includes('staff_profiles'));
      assert.deepEqual(await page.evaluate(()=>window.mockCalls),['staff_profiles']);
      if(ready&&file!=='v519-guard-check.html')assert.equal(await page.locator(ready).isVisible(),false);
      if(file==='v519-guard-check.html')assert.equal(await page.locator('#run').isEnabled(),false);
    }finally{await context.close();}
  });
}
test('Billing supports a direct portal Master session without borrowing another key',async()=>{
 const {page,context}=await openPage('/portal/AAW_Billing_Studio_Final.html?role=direct',{sessionKey:'aaw-portal-auth-direct'});
 try{await page.waitForFunction(()=>!document.getElementById('aawGate'));assert.equal(await page.evaluate(()=>window.mockAuthKey),'aaw-portal-auth-direct');}
 finally{await context.close();}
});

const portalSource=read('portal/index.html');
const overtime=vm.runInNewContext(portalSource.slice(portalSource.indexOf('function calculateOvertime('),portalSource.indexOf('function readAttendanceRow('))+'; calculateOvertime');
for(const [start,end,nextDay,expected] of [['09:00','17:00',false,0],['09:00','19:30',false,2.5],['09:00','13:00',false,0],['22:00','08:00',true,2]]) {
 test(`Automatic OT ${start} to ${end} (next day=${nextDay}) equals ${expected}`,()=>assert.equal(overtime(start,end,nextDay),expected));
}
test('Automatic OT rejects missing, invalid and reversed times',()=>{
 for(const [start,end] of [['','18:00'],['29:00','18:00'],['18:00','09:00']])assert.throws(()=>overtime(start,end));
});
test('Bulk attendance supports manual and timed rows without creating database records',async()=>{
 const {page,context}=await openPage('/portal/index.html?role=master',{demoWorkers:[{id:'demo-worker',full_name:'Demo Worker',is_active:true,is_deleted:false,daily_wage:1000,overtime_rate:100}]});
 try{
  await page.locator('#app').waitFor({state:'visible'});await page.locator('[data-tab="attendance"]').click();
  await page.locator('.amode').selectOption('time');
  await page.locator('.ain').fill('09:00');await page.locator('.ain').dispatchEvent('change');
  await page.locator('.aout').fill('19:30');await page.locator('.aout').dispatchEvent('change');
  assert.equal(await page.locator('.ao').inputValue(),'2.5');
  const value=await page.evaluate(()=>readAttendanceRow(document.querySelector('.att')));
  assert.deepEqual(value,{status:'present',overtime_hours:2.5,check_in:'09:00',check_out:'19:30'});
  await page.locator('.as').selectOption('absent');
  assert.deepEqual(await page.evaluate(()=>readAttendanceRow(document.querySelector('.att'))),{status:'absent',overtime_hours:0,check_in:null,check_out:null});
 }finally{await context.close();}
});
test('Payable preview uses all prior earnings and payment dates through the server cutoff',async()=>{
 const {page,context}=await openPage('/portal/index.html?role=master');
 try{
  await page.locator('#app').waitFor({state:'visible'});
  const trace=await page.evaluate(async()=>{
   const filters=[];
   db={from(table){const q=new Proxy({},{get(_t,m){if(m==='then')return resolve=>resolve({data:[],error:null});return (...args)=>{filters.push({table,method:m,args});return q}}});return q},rpc(name,args){filters.push({name,args});const q=new Proxy({},{get(_t,m){if(m==='then')return resolve=>resolve({data:[],error:null});return ()=>q}});return q}};
   await salaryCutoffData('demo-site','2026-10-03','demo-worker');return filters;
  });
  assert.ok(trace.some(x=>x.table==='worker_salary_payments'&&x.method==='lte'&&x.args[0]==='payment_date'&&x.args[1]==='2026-10-03'));
  assert.equal(trace.some(x=>x.table==='worker_salary_payments'&&x.args[0]==='period_start'),false);
  assert.ok(trace.some(x=>x.table==='worker_advances'&&x.method==='gte'&&x.args[1]==='0001-01-01'));
 }finally{await context.close();}
});

test('Salary data pagination reads beyond the API row cap and propagates failures',async()=>{
 const source=read('portal/index.html');const fn=vm.runInNewContext(source.slice(source.indexOf('async function allSalaryRows('),source.indexOf('async function salaryData('))+';allSalaryRows');
 const demo=Array.from({length:1203},(_,i)=>({id:i})),ranges=[];
 const rows=await fn({range:async(a,b)=>{ranges.push([a,b]);return {data:demo.slice(a,b+1),error:null}}});
 assert.equal(rows.length,1203);assert.deepEqual(ranges,[[0,499],[500,999],[1000,1499]]);
 await assert.rejects(()=>fn({range:async()=>({data:null,error:new Error('demo permission failure')})}),/permission failure/);
});
test('Food preview distributes paise exactly without a negative share',async()=>{
 const {page,context}=await openPage('/portal/food-v518-fixed.html?role=master');
 try{
  await page.waitForFunction(()=>!document.getElementById('app').hidden);
  await page.evaluate(()=>{
   $('from').value='2026-10-01';$('to').value='2026-10-01';
   groceryRows=[{purchase_date:'2026-10-01',amount:0.02}];
   periodRows=['w1','w2','w3','w4'].map(worker_id=>({worker_id,start_date:'2026-10-01',end_date:'2026-10-01',payment_type:'salary_deduction'}));calculate();
  });
  const shares=await page.locator('#result tr').evaluateAll(rows=>rows.slice(1).map(r=>Number(r.cells[2].textContent.replace(/[^0-9.-]/g,''))));
  assert.equal(shares.reduce((a,b)=>a+Math.round(b*100),0),2);assert.equal(Math.min(...shares),0);
 }finally{await context.close();}
});

for(const width of [320,360,768,1440]) {
 test(`Approved Classic public design at ${width}px keeps contact and login links usable`,async()=>{
  const {page,context,errors}=await openPage('/index.html',{width});
  try {
   await page.waitForFunction(()=>getComputedStyle(document.body).backgroundColor==='rgb(245, 240, 223)');
   assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));
   assert.equal(await page.locator('.hero h1').innerText(),'FABRICATION\nSOLUTIONS');
   assert.ok((await page.locator('a[href*="role=master"]').count())>0);
   assert.ok((await page.locator('a[href*="role=incharge"]').count())>0);
   assert.ok((await page.locator('a[href^="tel:"]').count())>0);
   assert.equal(await page.locator('.aaw-wordmark').innerText(),'ARIF AGRO WORKS');
   assert.ok(await page.locator('.aaw-wordmark').evaluate(el=>parseFloat(getComputedStyle(el).fontSize)>=20));
   assert.match(await page.locator('.aaw-gstin').innerText(),/09BWRPA6362F2ZA/);
   assert.match(await page.locator('.aaw-business-details').innerText(),/09BWRPA6362F2ZA/);
   assert.equal(await page.locator('.gallery .photo-card').count(),6);
   await page.locator('.gallery').scrollIntoViewIfNeeded();
   await page.waitForFunction(()=>Array.from(document.querySelectorAll('.gallery img')).every(img=>img.complete&&img.naturalWidth===1536&&img.naturalHeight===1024));
   assert.equal(await page.locator('.aaw-about-visual figcaption').innerText(),'INDUSTRIAL SOLUTIONS');
   if(process.env.AAW_SCREENSHOTS){await page.evaluate(async()=>{await document.fonts.ready;await Promise.all(Array.from(document.images).map(img=>img.decode().catch(()=>{})));scrollTo(0,0);await new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)));});await page.screenshot({path:`/tmp/aaw-public-en-${width}.png`,fullPage:true});await page.screenshot({path:`/tmp/aaw-public-top-${width}.png`});}

   await page.locator('.aaw-lang-btn[data-lang="hi"]').click();
   assert.match(await page.locator('.hero h1').innerText(),/फैब्रिकेशन/);
   assert.equal(await page.locator('.aaw-about-visual figcaption').innerText(),'औद्योगिक समाधान');
   assert.ok((await page.locator('#work .heading em').count())===1);
   assert.match(await page.locator('#about .heading').innerText(),/गुणवत्ता/);
   assert.equal(await page.locator('html').getAttribute('lang'),'hi');
   if(process.env.AAW_SCREENSHOTS){await page.evaluate(async()=>{await document.fonts.ready;scrollTo(0,0);await new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)));});await page.screenshot({path:`/tmp/aaw-public-${width}.png`,fullPage:true});}
   assert.deepEqual(errors,[]);
  }finally{await context.close()}
 });
 for(const role of ['master','incharge'])test(`Classic ${role} dashboard and navigation fit ${width}px`,async()=>{
  const {page,context,errors}=await openPage(`/portal/index.html?role=${role}`,{width,role,sessionKey:`aaw-portal-auth-${role}`,demoWorkers:[{id:'w1',full_name:'Worker One',is_active:true},{id:'w2',full_name:'Inactive',is_active:false}]});
  try{
   await page.locator('.aaw-dashboard-stats').waitFor();
   assert.equal(await page.locator('.aaw-dashboard-stats b').first().innerText(),'1');
   assert.equal(await page.locator('[data-tab="dashboard"]').getAttribute('aria-current'),'page');
   assert.equal(await page.locator('[data-tab="billing"]').count(),role==='master'?1:0);
   assert.equal(await page.evaluate(()=>getComputedStyle(document.body).backgroundColor),'rgb(245, 240, 223)');
   assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));
   if(process.env.AAW_SCREENSHOTS)await page.screenshot({path:`/tmp/aaw-${role}-${width}.png`,fullPage:true});
   await page.locator('[data-open="attendance"]').click();
   await page.locator('#content h2').filter({hasText:'Attendance'}).waitFor();
   assert.equal(await page.locator('[data-tab="attendance"]').getAttribute('aria-current'),'page');
   await page.locator('[data-tab="workers"]').click();
   await page.locator('#form').waitFor();
   assert.deepEqual(errors,[]);
  }finally{await context.close()}
 });
}
test('Username normalization preserves existing email accounts and supports incharge usernames',()=>{
 const source=read('portal/index.html');
 const fn=source.match(/function loginEmail\(value\)\{[\s\S]*?\n\}/)[0];
 const ctx=vm.createContext({});vm.runInContext(fn,ctx);
 assert.equal(vm.runInContext("loginEmail('  SITE01  ')",ctx),'site01@incharge.arifagroworks.local');
 assert.equal(vm.runInContext("loginEmail('admin@example.com')",ctx),'admin@example.com');
});
test('Classic branding matches native splash, Android 12 launch and WebView background',()=>{
 assert.match(read('android-app/app/src/main/res/layout/activity_splash.xml'),/android:background="#F5F0DF"/);
 assert.match(read('android-app/app/src/main/res/values-v31/styles.xml'),/windowSplashScreenBackground">#F5F0DF/);
 assert.match(read('android-app/app/src/main/java/com/arifagroworks/combined/MainActivity.java'),/web.setBackgroundColor\(Color.rgb\(245, 240, 223\)\)/);
 for(const name of ['index.html','food-v518-fixed.html','AAW_Billing_Studio_Final.html','AAW_Daily_Production_V526_Restore_Test.html','incharge-test-fixed.html','site-assignment-test.html','incharge-access-test.html','salary-test.html','AAW_Site_Backup_Master.html','v519-guard-check.html'])assert.match(read('portal/'+name),/aaw-design.css\?v=20261027A/,name);
});

test('Monthly salary uses date-effective rates without daily rounding and keeps old wage history',()=>{
 const source=read('portal/index.html');const fn=source.slice(source.indexOf('function calculateWorker('),source.indexOf('async function fullWorkers('));const ctx=vm.createContext({});vm.runInContext(fn,ctx);
 const data={attendance:[1,2,3].map(day=>({worker_id:'w1',attendance_date:'2026-10-0'+day,status:'present',overtime_hours:0})),advances:[],payments:[],rates:[{worker_id:'w1',effective_from:'2026-10-01',salary_basis:'monthly',monthly_salary:10000,overtime_hourly_rate:0}]};ctx.data=data;const actual=vm.runInContext("calculateWorker({id:'w1',daily_wage:1000},data)",ctx);assert.equal(actual.gross,1000);assert.equal(actual.due,1000);
 ctx.data.attendance.unshift({worker_id:'w1',attendance_date:'2026-09-30',status:'present',overtime_hours:0});assert.equal(vm.runInContext("calculateWorker({id:'w1',daily_wage:1000},data).gross",ctx),2000);
});
for(const role of ['master','incharge'])test(`Operations ${role} can navigate Food, rates, cash and history while financials stay Master-only`,async()=>{
 const {page,context,errors,external}=await openPage(`/portal/operations.html?role=${role}&section=rates`,{role,sessionKey:`aaw-portal-auth-${role}`,operational:true,demoWorkers:[{id:'w1',full_name:'Worker One',is_active:true}]});
 try{await page.locator('#workspace').waitFor({state:'visible'});for(const section of ['rates','daily','periods','grocery','settlement','transfer','ledger','audit']){await page.locator(`[data-section="${section}"]`).click();await page.locator('#operationForm').waitFor();assert.equal(await page.locator('#modules [aria-current="page"]').getAttribute('data-section'),section)}assert.equal(await page.locator('[data-section="financials"]').count(),role==='master'?1:0);assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));assert.deepEqual(errors,[]);assert.equal(external.some(u=>u.includes('.supabase.co')),false)}finally{await context.close()}
});
test('Operations saves monthly rate, daily Food and a manual owner-scoped cash entry with checked payloads',async()=>{
 const {page,context}=await openPage('/portal/operations.html?role=incharge&section=rates',{role:'incharge',sessionKey:'aaw-portal-auth-incharge',operational:true,demoWorkers:[{id:'w1',full_name:'Worker One',is_active:true}]});
 try{await page.locator('#operationForm').waitFor();await page.selectOption('[name=p_worker]','w1');await page.selectOption('[name=p_basis]','monthly');await page.fill('[name=p_monthly]','10000');await page.locator('#operationForm button[type=submit]').click();await page.waitForFunction(()=>window.mockRpc.some(x=>x.name==='aaw_set_worker_rate'));assert.equal((await page.evaluate(()=>window.mockRpc.find(x=>x.name==='aaw_set_worker_rate'))).args.p_monthly,10000);
 await page.locator('[data-section=daily]').click();await page.selectOption('[name=worker_id]','w1');await page.selectOption('[name=eligible]','false');await page.locator('#operationForm button[type=submit]').click();await page.waitForFunction(()=>window.mockMutations.length>0);let calls=await page.evaluate(()=>window.mockMutations);assert.equal(calls[0].args[0].eligible,false);assert.equal(calls[0].args[0].site_id,'demo-site');
 await page.locator('[data-section=ledger]').click();await page.fill('[name=amount]','250');await page.locator('#operationForm button[type=submit]').click();await page.waitForFunction(()=>window.mockMutations.some(x=>x.table==='site_cash_ledger'));calls=await page.evaluate(()=>window.mockMutations);const cash=calls.find(x=>x.table==='site_cash_ledger');assert.equal(cash.args[0].incharge_id,'demo-user');assert.equal(cash.args[0].amount,250);assert.equal(cash.args[0].is_archived,false);
 }finally{await context.close()}
});
test('Food preview stays visible and only deliberate Master confirmation finalizes',async()=>{
 const {page,context,errors}=await openPage('/portal/operations.html?role=master&section=settlement',{operational:true,demoWorkers:[{id:'w1',full_name:'Worker One'}]});
 try{await page.locator('#operationForm').waitFor();await page.locator('#operationForm button[type=submit]').click();await page.locator('#finalize').waitFor();assert.match(await page.locator('#report').innerText(),/Worker One/);assert.equal(await page.evaluate(()=>window.mockRpc.filter(x=>x.name==='finalize_food_settlement').length),0);page.once('dialog',dialog=>dialog.accept());await page.locator('#finalize').click();await page.waitForFunction(()=>window.mockRpc.some(x=>x.name==='finalize_food_settlement'));assert.deepEqual(errors,[])}finally{await context.close()}
});
test('Master financial report remains visible after generation and supports Hindi controls',async()=>{
 const {page,context,errors}=await openPage('/portal/operations.html?role=master&section=financials',{operational:true});
 try{await page.locator('#operationForm').waitFor();await page.locator('#operationForm button[type=submit]').click();await page.locator('#exportFinancial').waitFor();assert.match(await page.locator('#report').innerText(),/Receivables/);await page.selectOption('#language','hi');await page.locator('#operationForm button[type=submit]').filter({hasText:'रिपोर्ट बनाएँ'}).waitFor();assert.deepEqual(errors,[])}finally{await context.close()}
});
test('Expense Edit updates the existing entry rather than inserting a duplicate',async()=>{
 const {page,context}=await openPage('/portal/index.html?role=incharge',{role:'incharge',sessionKey:'aaw-portal-auth-incharge',operational:true,demoRows:{site_expenses:[{id:'expense1',site_id:'demo-site',expense_date:'2026-10-01',category:'Tools',amount:100,description:'Receipt 1'}]}});
 try{await page.locator('#app').waitFor({state:'visible'});await page.locator('[data-tab=expenses]').click();await page.locator('[data-edit=expense1]').click();await page.fill('[name=amount]','125');await page.locator('#save').click();await page.waitForFunction(()=>window.mockMutations.length>0);const change=(await page.evaluate(()=>window.mockMutations))[0];assert.equal(change.method,'update');assert.equal(change.table,'site_expenses');assert.equal(change.args[0].amount,125);assert.equal(change.args[0].site_id,'demo-site')}finally{await context.close()}
});

for(const [file,expected] of [['index.html','डैशबोर्ड'],['incharge-test-fixed.html','इंचार्ज'],['site-assignment-test.html','इंचार्ज को साइट दें'],['incharge-access-test.html','प्रवेश नियंत्रण'],['salary-test.html','वेतन'],['AAW_Site_Backup_Master.html','साइट'],['v519-guard-check.html','जाँच के परिणाम'],['food-v518-fixed.html','राशन खरीद'],['AAW_Billing_Studio_Final.html','बिलिंग'],['AAW_Daily_Production_V526_Restore_Test.html','उत्पादन']])test(`Hindi UI toggle works and reverses on ${file}`,async()=>{
 const {page,context,errors}=await openPage('/portal/'+file+'?role=master');
 try{await page.locator('[data-aaw-language-controls]').waitFor();await page.locator('[data-aaw-language-controls] [data-lang=hi]').click();await page.waitForFunction(()=>document.documentElement.lang==='hi');assert.match(await page.locator('body').innerText(),new RegExp(expected));assert.equal(await page.evaluate(()=>localStorage.getItem('aaw-public-language')),'hi');await page.locator('[data-aaw-language-controls] [data-lang=en]').click();assert.equal(await page.locator('html').getAttribute('lang'),'en');assert.deepEqual(errors,[])}finally{await context.close()}
});
test('Hindi UI preserves user-entered values, worker names and literal invoice content',async()=>{
 const {page,context}=await openPage('/portal/index.html?role=master',{demoWorkers:[{id:'w1',full_name:'Workers',is_active:true}]});
 try{await page.locator('#app').waitFor({state:'visible'});await page.locator('[data-tab=workers]').click();await page.fill('[name=full_name]','Workers');await page.fill('[name=daily_wage]','1234.56');await page.locator('[data-aaw-language-controls] [data-lang=hi]').click();assert.equal(await page.inputValue('[name=full_name]'),'Workers');assert.equal(await page.inputValue('[name=daily_wage]'),'1234.56');assert.match(await page.locator('#rows').innerText(),/Workers/);assert.equal(await page.locator('#save').innerText(),'एंट्री सहेजें');await page.locator('[data-aaw-language-controls] [data-lang=en]').click();assert.equal(await page.locator('#save').innerText(),'Save Entry')}finally{await context.close()}
});
test('Salary slip sends its actual generated document to native print without a blank popup',async()=>{
 const {page,context}=await openPage('/portal/index.html?role=master',{operational:true,demoWorkers:[{id:'w1',full_name:'Synthetic Worker',daily_wage:1000,overtime_rate:100,is_active:true}]});
 try{await page.locator('#app').waitFor({state:'visible'});await page.evaluate(()=>{window.nativeDocuments=[];window.AAWNativeSupport={printHtml:(html,title)=>nativeDocuments.push({html,title})};window.open=()=>{throw Error('Native print must not open a blank popup')}});await page.locator('[data-tab=slip]').click();await page.selectOption('#slw','w1');await page.locator('#makeSlip').click();await page.locator('#printSlip').waitFor({state:'visible'});await page.locator('#printSlip').click();const document=await page.evaluate(()=>nativeDocuments[0]);assert.equal(document.title,'AAW Salary Slip');assert.match(document.html,/Synthetic Worker/);assert.match(document.html,/WORKER SALARY SLIP/)}finally{await context.close()}
});

for(const width of [320,390,1440])test(`Public FAQ chat and enquiry draft work without private access at ${width}px`,async()=>{
 const {page,context,errors,external}=await openPage('/index.html',{width});try{
  await page.locator('.aaw-help-launch').click();const dialog=page.locator('#aaw-public-help');await dialog.waitFor({state:'visible'});
  assert.equal(await dialog.evaluate(e=>e.scrollWidth<=e.clientWidth),true);
  await dialog.getByRole('button',{name:'GST',exact:true}).click();assert.match(await dialog.locator('[role=status]').textContent(),/09BWRPA6362F2ZA/);
  await dialog.locator('[name=question]').fill('worker salary password');await dialog.getByRole('button',{name:'Ask',exact:true}).click();assert.match(await dialog.locator('[role=status]').textContent(),/private/);
  await dialog.locator('[name=question]').fill('shed price delivery');await dialog.getByRole('button',{name:'Ask',exact:true}).click();assert.match(await dialog.locator('[role=status]').textContent(),/team will confirm price/);
  await dialog.locator('summary').click();await dialog.locator('[name=project]').fill('<img src=x onerror=alert(1)> Welding 20 x 10');await dialog.locator('[name=location]').fill('Synthetic site');await dialog.getByRole('button',{name:'Review enquiry draft',exact:true}).click();
  const link=dialog.getByRole('link',{name:'Review in WhatsApp'});assert.match(await link.getAttribute('href'),/^https:\/\/wa.me\/919717758967\?text=/);assert.equal(await dialog.locator('img').count(),0);assert.equal(external.some(x=>x.includes('wa.me')),false);
  await dialog.locator('[name=project]').fill('Changed request');assert.equal(await link.isVisible(),false);
  await page.keyboard.press('Escape');assert.equal(await dialog.isVisible(),false);assert.equal(await page.locator('.aaw-help-launch').evaluate(e=>e===document.activeElement),true);
  assert.deepEqual(await page.evaluate(()=>window.mockCalls),[]);assert.deepEqual(errors,[]);
 }finally{await context.close()}
});
test('Public chat switches Hindi without losing enquiry fields',async()=>{
 const {page,context}=await openPage('/index.html');try{
  await page.locator('.aaw-help-launch').click();await page.locator('#aaw-public-help summary').click();await page.locator('#aaw-public-help [name=project]').fill('Original worker-entered project');
  await page.evaluate(()=>document.documentElement.lang='hi');await page.getByRole('button',{name:'AAW से पूछें',exact:true}).waitFor({state:'attached'});
  assert.equal(await page.locator('#aaw-public-help [name=project]').inputValue(),'Original worker-entered project');await page.getByRole('button',{name:'संपर्क',exact:true}).click();assert.match(await page.locator('#aaw-public-help [role=status]').textContent(),/9717758967/);
 }finally{await context.close()}
});
test('Master guided commands recheck role and read the selected site report without writes',async()=>{
 const {page,context,errors}=await openPage('/portal/index.html?role=master',{operational:true,demoWorkers:[{id:'w1',full_name:'Synthetic <Worker>',is_active:true,is_deleted:false}]});try{
  await page.locator('[data-tab=assistant]').click();await page.getByRole('button',{name:'Client receivables',exact:true}).click();await page.waitForFunction(()=>document.getElementById('aaw-command-status').textContent.includes('Report loaded'));
  assert.match(await page.locator('#aaw-command-output').textContent(),/400.00/);
  const command=await page.locator('#aaw-command').inputValue();await page.evaluate(()=>AAWLanguage.setLanguage('hi'));assert.match(await page.locator('#aaw-command-output').textContent(),/अंत तारीख तक बकाया/);assert.match(await page.locator('#aaw-command-output').textContent(),/400.00/);assert.equal(await page.locator('#aaw-command').inputValue(),command);await page.evaluate(()=>AAWLanguage.setLanguage('en'));
  const calls=await page.evaluate(()=>mockRpc);assert.equal(calls.at(-1).name,'aaw_site_financials');assert.equal(calls.at(-1).args.p_site,'demo-site');assert.equal(calls.at(-2).name,'aaw_session_context');
  await page.getByRole('button',{name:'Worker list',exact:true}).click();await page.waitForFunction(()=>document.getElementById('aaw-command-status').textContent.includes('Worker list loaded'));assert.match(await page.locator('#aaw-command-output').textContent(),/Synthetic <Worker>/);assert.equal(await page.locator('#aaw-command-output img').count(),0);
  await page.locator('#aaw-command').fill('Pay everyone 5000 and disable admin');await page.getByRole('button',{name:'Run command',exact:true}).click();await page.waitForFunction(()=>document.getElementById('aaw-command-status').textContent.includes('No change made'));assert.deepEqual(await page.evaluate(()=>mockMutations),[]);assert.deepEqual(errors,[]);
 }finally{await context.close()}
});
test('Master command desk is absent for Incharge and denies an expired Master context',async()=>{
 const incharge=await openPage('/portal/index.html?role=incharge',{role:'incharge',sessionKey:'aaw-portal-auth-incharge',operational:true});try{await incharge.page.locator('[data-tab=workers]').waitFor();assert.equal(await incharge.page.locator('[data-tab=assistant]').count(),0)}finally{await incharge.context.close()}
 const {page,context}=await openPage('/portal/index.html?role=master',{operational:true});try{
  await page.locator('[data-tab=assistant]').click();await page.evaluate(()=>{db.rpc=async()=>({data:{role:'incharge',enabled:true},error:null})});await page.getByRole('button',{name:'Client receivables',exact:true}).click();await page.waitForFunction(()=>document.getElementById('aaw-command-status').textContent.includes('Active Master Admin access required'));assert.equal(await page.locator('#aaw-command-output').textContent(),'');assert.deepEqual(await page.evaluate(()=>mockMutations),[]);
 }finally{await context.close()}
});

for(const width of [360,1440])test(`Professional Billing workspace: real editing, letter tables, PDF at ${width}px`,async()=>{
 const {page,context,errors}=await openPage('/portal/AAW_Billing_Studio_Final.html',{width});
 try{
  await page.waitForFunction(()=>!document.getElementById('aawGate')).catch(async e=>{throw Error(JSON.stringify({errors,gate:await page.locator('#aawGate').textContent()}))});
  assert.equal(await page.locator('#letterbody').isVisible(),false);
  await page.locator('[data-step=items]').click();
  await page.locator('#items input[aria-label=Description]').fill('Custom fabrication');
  await page.locator('#items input[aria-label=Quantity]').fill('12.5');await page.locator('#items input[aria-label=Quantity]').press('Tab');
  await page.locator('#items input[aria-label="Rate ₹"]').fill('100');await page.locator('#items input[aria-label="Rate ₹"]').press('Tab');
  assert.equal(await page.locator('#grand').textContent(),'₹1,475.00');
  assert.match(await page.locator('#billingDirtyStatus').textContent(),/Unsaved/);
  assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));
  if(width===360)assert.equal(await page.locator('#items tr').evaluate(e=>getComputedStyle(e).display),'grid');
  await page.locator('[data-step=details]').click();await page.locator('#type').selectOption('letterhead');await page.locator('[data-step=items]').click();
  await page.locator('#letterbody').fill('Professional Hindi letter — नमस्ते');
  await page.locator('#letterbody').selectText();await page.getByRole('button',{name:'Bold',exact:true}).click();
  assert.match(await page.locator('#letterbody').innerHTML(),/bold|<b>|<strong>/);
  await page.getByRole('combobox',{name:'Font',exact:true}).selectOption('Georgia');
  assert.match(await page.locator('#letterbody').innerHTML(),/Georgia/i);
  await page.locator('#letterbody').click();await page.keyboard.press('Control+End');
  await page.locator('#letterInsertTable').click();assert.equal(await page.locator('#letterbody td').count(),9);
  await page.locator('#letterbody td').first().click();await page.keyboard.type('Work details');
  await page.getByRole('button',{name:'Add row',exact:true}).click();assert.equal(await page.locator('#letterbody tr').count(),4);
  await page.locator('#letterbody td').first().click();await page.getByRole('button',{name:'Add column',exact:true}).click();assert.equal(await page.locator('#letterbody td').count(),16);
  await page.locator('#letterbody td').first().click();await page.getByRole('button',{name:'Delete column',exact:true}).click();assert.equal(await page.locator('#letterbody td').count(),12);
  await page.evaluate(()=>render());
  assert.equal(await page.locator('#preview td').count(),12);
  await page.locator('[data-step=preview]').click();assert.equal(await page.locator('#preview').isVisible(),true);
  if(process.env.AAW_QA_DIR)await page.screenshot({path:path.join(process.env.AAW_QA_DIR,`billing-review-${width}.png`),fullPage:true});
  await page.emulateMedia({media:'print'});assert.equal(await page.locator('#preview').isVisible(),true);assert.equal(await page.locator('.letter-ribbon').isVisible(),false);
  const pdf=await page.pdf({format:'A4',printBackground:true});assert.ok(pdf.length>5000);if(process.env.AAW_QA_DIR)fs.writeFileSync(path.join(process.env.AAW_QA_DIR,`billing-letter-${width}.pdf`),pdf);
  assert.deepEqual(errors,[]);
 }finally{await context.close();}
});
test('Letter sanitizer preserves allowed formatting and tables while rejecting active content and CSS',async()=>{
 const {page,context}=await openPage('/portal/AAW_Billing_Studio_Final.html');
 try{
 await page.waitForFunction(()=>!document.getElementById('aawGate'));
 const result=await page.evaluate(()=>safeBody('<p style="color:#123456;text-align:center;position:fixed;background-image:url(https://evil.invalid/x);font-family:Georgia" onclick="alert(1)">Hello <b>World</b></p><table><tr><td colspan="2" style="line-height:1.5">Cell</td></tr></table><script>window.pwned=true</script><img src=x onerror="alert(2)"><a href="javascript:alert(3)">Link text</a><svg onload="alert(4)"></svg>'));
 assert.match(result,/color:rgb\(18, 52, 86\)/);assert.match(result,/text-align:center/);assert.match(result,/font-family:Georgia/);assert.match(result,/colspan="2"/);assert.match(result,/Link text/);assert.doesNotMatch(result,/onclick|onerror|script|img|svg|href|position|url\(/);
 }finally{await context.close();}
});
test('Billing save persists rich letters; failed save keeps unsaved changes and document search filters safely',async()=>{
 const payload={type:'letterhead',docno:'LT-2026-001',company:'ARIF AGRO WORKS',rows:[],letterbody:'<p style="text-align:center;color:#123456">Saved letter</p>'};
 const docs=[{id:'d1',site_id:'demo-site',document_type:'letterhead',document_number:'LT-2026-001',client_name:'Alpha Client',document_date:'2026-10-28',payload},{id:'d2',site_id:'demo-site',document_type:'quotation',document_number:'QT-2026-001',client_name:'Beta Client',payload:{type:'quotation',rows:[]}}];
 const {page,context}=await openPage('/portal/AAW_Billing_Studio_Final.html',{width:1440,operational:true,demoRows:{aaw_billing_documents:docs}});
 try{
 page.on('dialog',dialog=>dialog.accept());await page.waitForFunction(()=>!document.getElementById('aawGate')&&cloudDocs.length===2);
 await page.locator('#billingSearch').fill('Alpha');assert.equal(await page.locator('#saved .savedrow:visible').count(),1);
 await page.locator('#billingSearch').fill('');await page.locator('#billingFilter').selectOption('quotation');assert.equal(await page.locator('#saved .savedrow:visible').count(),1);
 await page.locator('#billingFilter').selectOption('');await page.locator('[data-cloud-load=d1]').click();
 assert.match(await page.locator('#letterbody').innerHTML(),/text-align:center/);
 await page.locator('#letterbody').fill('Changed letter');assert.match(await page.locator('#billingDirtyStatus').textContent(),/Unsaved/);
 await page.locator('#aawSaveButton').click();await page.waitForFunction(()=>document.getElementById('billingDirtyStatus').textContent.startsWith('Saved online'));
 const m=await page.evaluate(()=>window.mockMutations);assert.equal(m.length,1);assert.match(m[0].args[0].payload.letterbody,/Changed letter/);
 await page.locator('#letterbody').fill('Not saved');await page.evaluate(()=>{aawDb.from=()=>{throw Error('Synthetic offline failure')};});
 await page.locator('#aawSaveButton').click();await page.waitForFunction(()=>document.getElementById('aawCloudStatus').textContent.includes('Save failed'));
 assert.match(await page.locator('#billingDirtyStatus').textContent(),/Unsaved/);
 }finally{await context.close();}
});
test('Billing payment entry keeps RA and retention balance guard after workspace changes',async()=>{
 const {page,context,errors}=await openPage('/portal/AAW_Billing_Studio_Final.html',{width:1440,operational:true});
 try{
 await page.waitForFunction(()=>!document.getElementById('aawGate'));
 const messages=[];page.on('dialog',async d=>{messages.push(d.message());await d.dismiss();});
 await page.evaluate(()=>{cloudEditing='demo-invoice';aawPaymentDoc=cloudEditing;aawPayments=[{amount:100}];window.aawLedgerLoaded=true;rows=[{description:'Demo',unit:'KG',l:'',w:'',h:'',qty:10,rate:100}];document.getElementById('aawBillStage').value='running';document.getElementById('aawPrevious').value=200;document.getElementById('aawRetention').value=50;document.getElementById('aawPayAmount').value=900;document.getElementById('aawPayRef').value='DEMO-ONLY';document.getElementById('aawPayDate').value='2026-10-28';render();});
 await page.evaluate(()=>aawAddPayment());assert.match(messages.pop(),/exceeds outstanding/);
 await page.locator('#aawPayAmount').fill('100');await page.evaluate(()=>aawAddPayment());assert.match(messages.pop(),/Record payment of ₹100.00/);
 assert.deepEqual(await page.evaluate(()=>window.mockMutations),[]);assert.deepEqual(errors,[]);
 }finally{await context.close();}
});

for(const width of [360,1440])test(`RA text import creates a reviewed GST draft without saving or double-deducting previous bills at ${width}px`,async()=>{
 const {page,context,errors}=await openPage('/portal/AAW_Billing_Studio_Final.html',{width,operational:true});
 try{
 page.on('dialog',d=>d.accept());await page.waitForFunction(()=>!document.getElementById('aawGate'));
 await page.locator('#raImportDetails').evaluate(e=>e.open=true);
 const text='Client Name: Demo Client\nProject Name: Demo Project\nR/A Bill No.: RA-DEMO\nQuantities up to last This Bill up to date\nSynthetic fabrication KG 30000 32 960000 8168.550 6183.453 14352.003 261394 197870 459264\nSynthetic fixing PCS 10000 60 600000 361 1168 1529 21660 70080 91740\nAdd tax @ 18%';
 await page.locator('#raSourceText').evaluate(e=>e.closest('details').open=true);await page.locator('#raSourceText').fill(text);await page.locator('#raParse').click();assert.equal(await page.locator('#raRows tr').count(),2);
 await page.locator('#raTaxMode').selectOption('igst');await page.locator('#raReviewed').check();await page.locator('#raPrepare').click();
 assert.equal(await page.locator('#grand').textContent(),'₹3,16,181.59');assert.equal(await page.locator('#aawPrevious').inputValue(),'0');assert.equal(await page.locator('#aawBillStage').inputValue(),'regular');
 assert.deepEqual(await page.evaluate(()=>window.mockMutations),[]);
 assert.match(await page.evaluate(()=>AAWRAImport.issueError()),/Select the site/);
 await page.locator('#aawBillSite').selectOption('demo-site');await page.locator('.billing-branding:not(.ra-invoice-fields) summary').click();await page.locator('#address').fill('Demo company address');
 await page.locator('#clientgst').fill('06AAAAA0000A1Z5');await page.locator('#raBillTo').fill('Demo recipient address');await page.locator('#raShipTo').fill('Demo work site address');await page.locator('#raPlace').fill('Demo state 06');await page.locator('#raSac').fill('123456');
 await page.locator('[data-step=preview]').click();await page.locator('#raIssueReviewed').check();assert.equal(await page.evaluate(()=>AAWRAImport.issueError()),'');
 assert.match(await page.locator('#preview').innerText(),/IGST @ 18%/);assert.match(await page.locator('#preview').innerText(),/Three Lakh Sixteen Thousand One Hundred Eighty One/);
 await page.locator('#aawSaveButton').click();await page.waitForFunction(()=>window.mockMutations.length===1&&window.aawLedgerLoaded);const saved=await page.evaluate(()=>window.mockMutations[0].args[0]);assert.equal(saved.payload.raImport.quantityBasis,'this_bill');assert.equal(saved.payload.invoiceParticulars.raInvoiceTax,'igst');assert.equal(saved.payload.previousCertified,0);assert.equal(saved.payload.rows[0].qty,'6183.453');
 await page.evaluate(()=>{window.raExports=[];downloadBlob=async(blob,name)=>raExports.push({name,text:await blob.text()});downloadExcel();});await page.waitForFunction(()=>window.raExports.length===1);const exported=await page.evaluate(()=>raExports[0]);assert.match(exported.text,/IGST 18%/);assert.match(exported.text,/316181.59/);assert.match(exported.text,/Demo recipient address/);assert.match(exported.text,/RA-DEMO/);if(process.env.AAW_QA_DIR){await page.screenshot({path:path.join(process.env.AAW_QA_DIR,`ra-invoice-review-${width}.png`),fullPage:true});const pdf=await page.pdf({format:'A4',printBackground:true});fs.writeFileSync(path.join(process.env.AAW_QA_DIR,`ra-invoice-review-${width}.pdf`),pdf);}
 assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));
 await page.evaluate(()=>{document.getElementById('gst').value='12';render();});assert.match(await page.evaluate(()=>AAWRAImport.issueError()),/Review the current draft/);assert.equal(await page.locator('#raIssueReviewed').isChecked(),false);
 assert.deepEqual(errors,[]);
 }finally{await context.close();}
});
test('RA file reading fails safely and cancelling a new draft preserves an existing letter',async()=>{
 const {page,context,errors}=await openPage('/portal/AAW_Billing_Studio_Final.html',{width:1440});
 try{await page.waitForFunction(()=>!document.getElementById('aawGate'));await page.locator('#raImportDetails').evaluate(e=>e.open=true);
 await page.locator('#raFile').setInputFiles({name:'demo.png',mimeType:'image/png',buffer:Buffer.from('not an image')});await page.locator('#raRead').click();await page.waitForFunction(()=>!document.getElementById('raRead').disabled);assert.match(await page.locator('#raReadStatus').textContent(),/Could not map file/);assert.equal(await page.locator('#raRows tr').count(),0);assert.deepEqual(await page.evaluate(()=>window.mockMutations),[]);
 await page.locator('#type').selectOption('letterhead');await page.locator('#letterbody').fill('Keep my unsaved letter');
 page.on('dialog',d=>d.dismiss());await page.locator('.toolbar button').filter({hasText:'+ New Document'}).click();assert.equal(await page.locator('#letterbody').textContent(),'Keep my unsaved letter');assert.equal(await page.locator('#type').inputValue(),'letterhead');assert.deepEqual(errors,[]);
 }finally{await context.close();}
});
