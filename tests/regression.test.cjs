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
    try { res.setHeader('Content-Type', file.endsWith('.html') ? 'text/html' : file.endsWith('.js') ? 'application/javascript' : 'application/octet-stream'); res.end(fs.readFileSync(file)); }
    catch { res.writeHead(404).end(); }
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  origin = `http://127.0.0.1:${server.address().port}`;

});
after(async () => { await new Promise(resolve => server?.close(resolve)); });

// All non-local requests are intercepted. The Supabase SDK itself is replaced,
// so tests cannot read or mutate production, even with a real browser session.
async function openPage(url, { role = 'master', sessionKey = 'aaw-portal-auth-master', width = 390 } = {}) {
  const instance = await chromium.launch({ headless: true, ...(process.env.AAW_CHROMIUM_PATH ? { executablePath: process.env.AAW_CHROMIUM_PATH, args: ['--no-sandbox','--no-zygote','--single-process','--use-gl=angle','--use-angle=swiftshader','--in-process-gpu'] } : {}) });
  const context = await instance.newContext({ viewport: { width, height: 900 }, serviceWorkers: 'block' });
  const close = context.close.bind(context);
  context.close = async () => { await close(); await instance.close(); };
  const page = await context.newPage();
  page.setDefaultTimeout(5000);
  const external = [], errors = [];
  page.on('pageerror', e => errors.push(e.message));
  await context.addInitScript(({ role, sessionKey }) => {
    window.mockCalls = [];
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
            : table === 'sites' ? [{ id: 'demo-site', site_name: 'Demo Site', is_active: true }] : table === 'site_assignments' ? [{site_id:'demo-site',user_id:'demo-user'}] : [];
          const q = new Proxy({}, { get(_target, method) {
            if (method === 'eq') return (key, value) => { if (table === 'staff_profiles' && key === 'role' && value === 'incharge') data = []; return q; };
            if (method === 'then') return resolve => resolve({ data, error: null });
            if (['insert', 'update', 'delete', 'upsert'].includes(method)) throw Error('Unexpected database mutation in regression test');
            return () => q;
          }});
          return q;
        },
        rpc() { throw Error('Unexpected RPC in regression test'); }
      };
    }};
  }, { role, sessionKey });
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
  assert.match(read('android-app/app/build.gradle'),/versionCode 3/);
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
