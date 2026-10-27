/* Guided Master commands. No external AI or database writes in this first stage. */
(function(){
 'use strict';
 const translations=new Map();let active=null;
 const hi=()=>document.documentElement.lang==='hi',T=(en,hindi)=>{translations.set(en,hindi);return hi()?hindi:en};
 function translateActive(){
  if(!active?.heading.isConnected)return;
  const root=active.container,walker=document.createTreeWalker(root,NodeFilter.SHOW_TEXT);let node;
  while(node=walker.nextNode()){
   if(node.parentElement.closest('li'))continue;
   for(const [en,hindi] of translations){const from=hi()?en:hindi,to=hi()?hindi:en;if(node.nodeValue===from){node.nodeValue=to;break}if((from.endsWith(' ')&&node.nodeValue.startsWith(from))||node.nodeValue.startsWith(from+':')){node.nodeValue=to+node.nodeValue.slice(from.length);break}}
  }
  for(const input of root.querySelectorAll('input[placeholder]'))for(const [en,hindi]of translations){if(input.placeholder===(hi()?en:hindi)){input.placeholder=hi()?hindi:en;break}}
 }
 window.addEventListener('aaw-languagechange',translateActive);
 const e=(tag,text)=>{const node=document.createElement(tag);if(text)node.textContent=text;return node};
 const intent=q=>{
  if(/pay|payment|finaliz|delete|disable|enable|reset|transfer|rate|salary.*change|भुगतान|पैसे|अंतिम|डिलीट|हटाओ|बंद|चालू|पासवर्ड|स्थानांतरण|दर|वेतन.*बदल/i.test(q))return 'review';
  if(/profit|loss|financial|receivable|client|income|बकाया|लाभ|नुकसान|आय|क्लाइंट/i.test(q))return 'financial';
  if(/salary|payroll|slip|वेतन|सैलरी|पर्ची/i.test(q))return 'salary';
  if(/attendance|हाजिरी|अटेंडेंस/i.test(q))return 'attendance';
  if(/worker|staff|कर्मचारी|मजदूर/i.test(q))return 'workers';
  if(/food|grocery|भोजन|राशन/i.test(q))return 'food';
  if(/cash|ledger|नकद|कैश|खाता/i.test(q))return 'ledger';
  if(/production|progress|उत्पादन|प्रगति/i.test(q))return 'production';
  if(/bill|invoice|quotation|बिल|कोटेशन/i.test(q))return 'billing';
  return 'help';
 };
 async function mount({db,role,container,site,siteName,open}){
  container.replaceChildren();
  if(role!=='master'){container.textContent=T('Master Admin only','केवल मास्टर एडमिन');return}
  const heading=e('h2',T('Master command assistant','मास्टर कमांड सहायक'));container.append(heading);active={container,heading};
  const note=e('p',T('Guided mode · No external AI connected. Read reports or open the right tool using the commands below. Payments and record changes stay in their reviewed forms.','Guided mode · बाहरी AI अभी जुड़ा नहीं है। नीचे दिए कमांड से रिपोर्ट देखें या सही टूल खोलें। भुगतान और रिकॉर्ड बदलाव उनके जाँच वाले फॉर्म में होंगे।'));note.className='muted';container.append(note);
  container.append(e('p',T('Selected site: ','चुनी साइट: ')+siteName));
  const form=e('form');form.className='grid';const label=e('label',T('Command','कमांड')),input=e('input');input.id='aaw-command';input.name='command';input.maxLength=400;input.required=true;input.placeholder=T('Show client receivables','क्लाइंट बकाया दिखाओ');label.append(input);form.append(label);
  const now=new Date(),ymd=d=>new Date(d.getTime()-d.getTimezoneOffset()*60000).toISOString().slice(0,10),dates={};
  for(const [key,en,hindi,value] of [['start','From','से',ymd(new Date(now.getFullYear(),now.getMonth(),1))],['end','To','तक',ymd(now)]]){const l=e('label',T(en,hindi)),i=e('input');i.type='date';i.name=key;i.required=true;i.value=value;i.max=ymd(now);dates[key]=i;l.append(i);form.append(l)}
  const run=e('button',T('Run command','कमांड चलाएँ'));run.type='submit';form.append(run);container.append(form);
  const choices=e('div');choices.className='actions';for(const [en,hindi] of [['Client receivables','क्लाइंट बकाया'],['Worker list','कर्मचारी सूची'],['Salary report','सैलरी रिपोर्ट'],['Food report','भोजन रिपोर्ट'],['Cash ledger','नकद खाता']]){const b=e('button',T(en,hindi));b.className='alt';b.type='button';b.onclick=()=>{input.value=T(en,hindi);form.requestSubmit()};choices.append(b)}container.append(choices);
  const status=e('p');status.id='aaw-command-status';status.setAttribute('role','status');const output=e('div');output.id='aaw-command-output';container.append(status,output);
  function action(label,key){const b=e('button',label);b.type='button';b.onclick=()=>open(key);output.append(b)}
  async function authorized(){const r=await db.rpc('aaw_session_context');if(r.error)throw r.error;if(r.data?.role!=='master'||r.data?.enabled!==true)throw Error(T('Active Master Admin access required.','सक्रिय मास्टर एडमिन अधिकार जरूरी हैं।'))}
  form.onsubmit=async event=>{
   event.preventDefault();if(run.disabled)return;
   run.disabled=true;status.textContent=T('Checking access…','अधिकार जाँच रहे हैं…');output.replaceChildren();
   try{
    if(!dates.start.value||!dates.end.value||dates.start.value>dates.end.value)throw Error(T('Choose a valid date range.','सही तारीख अवधि चुनें।'));
    await authorized();
    const kind=intent(input.value);
    if(kind==='financial'){
     const r=await db.rpc('aaw_site_financials',{p_site:site,p_start:dates.start.value,p_end:dates.end.value});if(r.error)throw r.error;
     const labels={billed:['Invoices (tax inclusive)','बिल (कर सहित)'],collected:['Collections','प्राप्ति'],receivable:['Receivables through end date','अंत तारीख तक बकाया'],cash_surplus:['Cash surplus','नकद अधिशेष'],billed_operating_surplus:['Billed operating surplus','बिल आधारित परिचालन अधिशेष']};
     output.append(e('p',siteName+' · '+dates.start.value+' → '+dates.end.value));
     for(const [key,label] of Object.entries(labels)){const value=Number(r.data?.[key]);if(!Number.isFinite(value))throw Error(T('Incomplete report received.','अधूरी रिपोर्ट मिली।'));output.append(e('p',T(...label)+': ₹'+value.toLocaleString('en-IN',{minimumFractionDigits:2,maximumFractionDigits:2})))}
     output.append(e('p',T('Operating surplus is not statutory net profit. Receivables are cumulative through the end date.','परिचालन अधिशेष वैधानिक शुद्ध लाभ नहीं है। बकाया अंत तारीख तक कुल है।')));
     status.textContent=T('Report loaded from the portal. No records changed.','पोर्टल से रिपोर्ट मिली। कोई रिकॉर्ड नहीं बदला।');
    }else if(kind==='workers'){
     const r=await db.from('workers').select('full_name,is_active,is_deleted').eq('site_id',site).order('full_name').limit(1001);if(r.error)throw r.error;
     const all=r.data||[];if(all.length>1000)throw Error(T('Use the Workers screen for this large list.','इस बड़ी सूची के लिए Workers स्क्रीन खोलें।'));
     const rows=all.filter(w=>w.is_deleted!==true);output.append(e('p',T('Workers: ','कर्मचारी: ')+rows.length));const list=e('ul');for(const w of rows)list.append(e('li',w.full_name+(w.is_active===false?T(' (Inactive)',' (निष्क्रिय)'):'')));output.append(list);status.textContent=T('Worker list loaded. No records changed.','कर्मचारी सूची मिली। कोई रिकॉर्ड नहीं बदला।');
    }else if(kind==='review'){
     status.textContent=T('No change made. Specify the exact person/site, amount and date in the appropriate form, review the result, then save. Free-text financial/access execution is not enabled.','कोई बदलाव नहीं किया। सही फॉर्म में व्यक्ति/साइट, रकम और तारीख चुनें, जाँचें और सहेजें। Free-text से वित्तीय या access बदलाव अभी सक्रिय नहीं है।');
     for(const [en,hindi,key] of [['Payments','भुगतान','salary'],['Rates / transfers','दर / स्थानांतरण','operations'],['Account controls','खाता नियंत्रण','mastertools']])action(T(en,hindi),key);
    }else if(kind==='help')status.textContent=T('Try worker list, client receivables, salary report, attendance, Food, cash ledger, production or billing. Guided commands use the selected site; change the site selector first when needed.','कर्मचारी सूची, क्लाइंट बकाया, सैलरी रिपोर्ट, हाजिरी, भोजन, नकद खाता, उत्पादन या बिलिंग लिखें। कमांड चुनी साइट के लिए है; दूसरी साइट के लिए पहले साइट बदलें।');
    else {const targets={salary:'summary',attendance:'attendance',food:'foodmanage',ledger:'ledger',production:'production',billing:'billing'};status.textContent=T('Open the checked portal tool to choose exact dates/workers and calculate or review. No records have changed.','सही तारीख/कर्मचारी चुनकर गणना या जाँच के लिए पोर्टल टूल खोलें। कोई रिकॉर्ड नहीं बदला।');action(T('Open tool →','टूल खोलें →'),targets[kind])}
   }catch(error){output.replaceChildren();status.textContent=T('Unable to complete: ','काम पूरा नहीं हुआ: ')+(error.message||String(error))}finally{run.disabled=false}
  };
 }
 window.AAWCommandDesk=Object.freeze({mount});
})();
