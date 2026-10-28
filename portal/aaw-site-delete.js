/* Master-only site-record maintenance; the server owns authorization, archive equality and both delays. */
(function(){
'use strict';
const id=x=>document.getElementById(x),site=id('site'),buttons=['deletePrepare','deleteDownload','deleteConfirm1','deleteConfirm2'];
let plan=null,archiveText='',phase=0,readyAt=0,timer=null,busy=false,generation=0;
const message=text=>{id('deleteStatus').textContent=text;};
function controls(){
 const valid=!!plan&&archiveText&&id('deletePhrase').value==='DELETE '+plan.site_name&&id('deleteReason').value.trim().length>=5;
 const ready=Date.now()>=readyAt;
 id('deletePrepare').disabled=busy||!site.value;
 id('deleteDownload').disabled=busy||!plan;
 id('deleteFile').disabled=busy||!plan;
 id('deletePhrase').disabled=busy||!plan;id('deleteReason').disabled=busy||!plan;
 id('deleteConfirm1').disabled=busy||phase!==1||!valid||!ready;
 id('deleteConfirm2').disabled=busy||phase!==2||!valid||!ready;
 const seconds=Math.max(0,Math.ceil((readyAt-Date.now())/1000));
 id('deleteClock1').textContent=phase===1&&seconds?' · '+seconds+'s':'';
 id('deleteClock2').textContent=phase===2&&seconds?' · '+seconds+'s':'';
 site.disabled=busy;
}
function reset(text=''){
 generation++;plan=null;archiveText='';phase=0;readyAt=0;clearInterval(timer);timer=null;
 id('deleteFile').value='';id('deletePhrase').value='';id('deleteReason').value='';id('deletePreview').replaceChildren();id('deleteExpected').textContent='';
 message(text);controls();
}
async function rpc(name,args){const r=await db.rpc(name,args);if(r.error)throw Error(r.error.message);return r.data;}
function countdown(seconds){readyAt=Date.now()+Math.max(8,Number(seconds)||8)*1000;clearInterval(timer);timer=setInterval(controls,250);controls();}
const labels={workers:'Workers',worker_attendance:'Attendance',worker_advances:'Advances',worker_salary_payments:'Salary payments',worker_salary_rates:'Salary rate history',worker_food_periods:'Food periods',food_grocery:'Food groceries',food_settlements:'Food settlements',food_settlement_workers:'Food shares',site_expenses:'Site expenses',site_cash_ledger:'Cash ledger',daily_production_entries:'Daily production',food_daily_attendance:'Daily Food entries',aaw_billing_documents:'Billing documents',aaw_billing_document_history:'Bill edit history',aaw_client_payments:'Client payments'};
id('deletePrepare').onclick=async()=>{
 if(busy||!site.value)return;
 reset();const current=++generation,selected=site.value;busy=true;controls();message('Preparing recovery archive and checking site dependencies…');
 try{
  const data=await rpc('aaw_prepare_site_delete',{p_site:selected});if(current!==generation)return;
  if(!data||data.site_id!==selected||!data.request_id||!data.archive_text||!data.digest||!data.counts)throw Error('Invalid server preview. No records deleted.');
  plan=data;phase=1;const total=Object.values(data.counts).reduce((a,b)=>a+Number(b),0);
  id('deletePreview').innerHTML='<h3>'+esc(data.site_name)+' · '+esc(total)+' records</h3><table><thead><tr><th>Records to delete</th><th>Rows</th></tr></thead><tbody>'+Object.entries(data.counts).map(([key,count])=>'<tr><td>'+esc(labels[key]||key)+'</td><td>'+esc(count)+'</td></tr>').join('')+'</tbody></table><p>SHA-256: <code>'+esc(data.digest)+'</code></p>';
  id('deleteExpected').textContent='DELETE '+data.site_name;
  countdown(data.wait_seconds);message('Preview ready. Save the recovery JSON, then select that saved file below. Nothing has been deleted.');
 }catch(e){message('Preparation blocked: '+e.message)}finally{busy=false;controls()}
};
id('deleteDownload').onclick=()=>{if(plan&&window.AAWNativeSupport&&new Blob([plan.archive_text]).size>12*1024*1024){message('Recovery file exceeds the APK 12 MB export limit. Open the portal in a browser to save this file.');return;}if(plan)downloadBlob('AAW_'+plan.site_name.replace(/[^a-z0-9_-]/gi,'_')+'_RECOVERY_'+plan.request_id+'.json',plan.archive_text,'application/json');};
id('deleteFile').onchange=async()=>{
 archiveText='';controls();const current=generation,file=id('deleteFile').files[0];if(!file)return;
 try{if(file.size>20*1024*1024)throw Error('Recovery file exceeds 20 MB');const text=(await file.text()).replace(/^\uFEFF/,'');if(current!==generation)return;
  if(!plan||text.trim()!==plan.archive_text.trim())throw Error('Select the matching recovery JSON downloaded for this preview');
  archiveText=text;message('Recovery file verified. Enter the exact confirmation text and a reason.');
 }catch(e){message(e.message)}finally{controls()}
};
id('deletePhrase').oninput=controls;id('deleteReason').oninput=controls;
id('deleteConfirm1').onclick=async()=>{
 if(id('deleteConfirm1').disabled||busy)return;busy=true;controls();
 try{const result=await rpc('aaw_confirm_site_delete',{p_request:plan.request_id,p_phrase:id('deletePhrase').value,p_reason:id('deleteReason').value.trim()});phase=2;countdown(result.wait_seconds);message('First confirmation accepted. Wait for the final confirmation. No records deleted yet.');}
 catch(e){message('Confirmation blocked: '+e.message)}finally{busy=false;controls()}
};
id('deleteConfirm2').onclick=async()=>{
 if(id('deleteConfirm2').disabled||busy)return;
 const total=Object.values(plan.counts).reduce((a,b)=>a+Number(b),0);
 if(!confirm('HARD DELETE '+total+' records from '+plan.site_name+'?\n\nWorkers, attendance, salary, Food, production, bills and payments for this site will be removed. Site, logins, assignments and audit remain. There is no app Undo.'))return;
 busy=true;controls();message('Deleting the confirmed site records. Please wait…');
 try{
  const result=await rpc('aaw_execute_site_delete',{p_request:plan.request_id,p_phrase:id('deletePhrase').value,p_digest:plan.digest,p_archive_text:archiveText});
  if(!result?.deleted)throw Error('Server did not confirm deletion');
  snap=null;['excel','pdf','json'].forEach(x=>id(x).disabled=true);id('results').replaceChildren();id('validation').hidden=true;
  id('status').textContent='Site records deleted. Load records again to refresh the export.';
  reset('Hard Delete complete for '+result.site_name+'. Audit and recovery archive retained.');
 }catch(e){message('Deletion not confirmed: '+e.message+'. Check site records and audit before preparing again.');}
 finally{busy=false;controls()}
};
window.addEventListener('aaw-site-ready',controls);
site.addEventListener('change',()=>reset('Site changed. Prepare a fresh preview for this site.'));
window.addEventListener('pagehide',()=>clearInterval(timer));
reset();
})();
