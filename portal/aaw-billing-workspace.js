/* Billing workspace. No database/schema changes; existing billing and payment guards remain authoritative. */
(function(){
'use strict';
const byId=id=>document.getElementById(id);
// Keep formatting only. No links, images, external fetches, active content or arbitrary CSS.
const allowed=new Set('P DIV SPAN BR B STRONG I EM U S STRIKE SUB SUP UL OL LI BLOCKQUOTE H1 H2 H3 H4 TABLE THEAD TBODY TFOOT TR TD TH HR FONT'.split(' '));
function sanitize(html){
 const t=document.createElement('template');t.innerHTML=String(html||'');
 t.content.querySelectorAll('script,style,iframe,object,embed,form,input,button,textarea,select,svg,math,link,meta,base,img,video,audio,source').forEach(e=>e.remove());
 for(const el of [...t.content.querySelectorAll('*')]){
  if(!allowed.has(el.tagName)){el.replaceWith(...el.childNodes);continue;}
  const style=el.style;const clean=[];
  for(const key of ['color','background-color']){const val=style.getPropertyValue(key);if(/^(#[\da-f]{3,8}|rgba?\([\d\s.,%]+\)|[a-z]+)$/i.test(val))clean.push(key+':'+val+'!important');}
  const rules={'text-align':/^(left|right|center|justify)$/,'font-family':/^(Arial|Georgia|Verdana|Tahoma|Times New Roman|Courier New)(,\s*(serif|sans-serif|monospace))?$/i,'font-size':/^(\d{1,2}(px|pt)|(?:small|medium|large|x-large|xx-large))$/,'font-weight':/^(bold|normal|[1-9]00)$/,'font-style':/^(italic|normal)$/,'text-decoration-line':/^(underline|line-through|none|underline line-through)$/,'line-height':/^(1|1\.15|1\.5|1\.8|2)$/,'padding-left':/^(\d{1,2}px)$/,'margin-left':/^(\d{1,2}px)$/};
  for(const [key,re] of Object.entries(rules)){const val=key==='font-family'?style.getPropertyValue(key).replace(/["']/g,''):style.getPropertyValue(key);if(re.test(val))clean.push(key+':'+val);}
  const attrs={};
  if(el.tagName==='FONT'){
   if(/^[1-7]$/.test(el.getAttribute('size')||''))attrs.size=el.getAttribute('size');
   if(/^(#[\da-f]{3,8}|[a-z]+)$/i.test(el.getAttribute('color')||''))attrs.color=el.getAttribute('color');
   if(/^(Arial|Georgia|Verdana|Tahoma|Times New Roman|Courier New)$/i.test(el.getAttribute('face')||''))attrs.face=el.getAttribute('face');
  }
  if(['TD','TH'].includes(el.tagName))for(const name of ['colspan','rowspan']){const n=Number(el.getAttribute(name));if(Number.isInteger(n)&&n>=1&&n<=12)attrs[name]=String(n);}
  for(const a of [...el.attributes])el.removeAttribute(a.name);
  for(const [k,val]of Object.entries(attrs))el.setAttribute(k,val);
  if(clean.length)el.setAttribute('style',clean.join(';'));
 }
 return t.innerHTML;
}
window.AAWLetterTools={sanitize};
const main=document.querySelector('main'),editor=byId('letterbody');if(!main||!editor)return;
document.body.classList.add('billing-workspace');
const top=document.querySelector('.top');top.querySelector('h1').textContent='Billing Studio';
const back=document.createElement('a');back.className='billing-back';back.href='index.html'+location.search;back.textContent='← Back to Portal';top.prepend(back);
const tools=top.querySelector('.toolbar');
const more=document.createElement('details');more.className='billing-more';more.innerHTML='<summary>More tools</summary><div></div>';tools.append(more);
for(const button of [...tools.querySelectorAll(':scope > button')]){
 if(/Excel|Backup|Restore/.test(button.textContent))more.lastElementChild.append(button);
}
const reconnect=document.createElement('button');reconnect.type='button';reconnect.textContent='Refresh cloud';reconnect.onclick=async()=>{try{await cloudList();}catch(e){aawStatus('Cloud unavailable: '+e.message,'error');}};more.lastElementChild.append(reconnect);
document.querySelector('.cards').classList.add('billing-template-cards');
const intro=document.querySelector('.notice.controls');intro.textContent='Choose a document, enter details, then review and save online. PDF and Excel use the existing invoice payment checks.';
const tabs=document.createElement('nav');tabs.className='billing-tabs nonprint';tabs.setAttribute('aria-label','Billing steps');
tabs.innerHTML='<button type="button" data-step="details">1 · Details</button><button type="button" data-step="items">2 · Items / Letter</button><button type="button" data-step="preview">3 · Preview & Payments</button><button type="button" data-step="saved">Saved documents</button>';
top.after(tabs);
const workspace=document.createElement('div');workspace.className='billing-grid';const form=document.createElement('div');form.className='billing-form';workspace.append(form);
const details=document.querySelector('section.panel.controls');details.classList.add('billing-details');details.dataset.stage='details';
// Move the letter editor out of invoice details; company identity is a compact optional section.
const letterField=editor.closest('.field');letterField.classList.add('billing-letter');letterField.dataset.stage='items';
const letterPanel=document.createElement('section');letterPanel.className='panel controls billing-letter-panel';letterPanel.dataset.stage='items';letterPanel.innerHTML='<h2>Letterhead editor</h2><p class="muted">Format text and create editable tables. Table cells contain text; spreadsheet formulas are not calculated.</p>';letterPanel.append(letterField);
const branding=document.createElement('details');branding.className='billing-branding';branding.innerHTML='<summary>Company branding & contact details</summary>';
for(const id of ['gst','clientgst','project','location','notes'])byId(id).closest('.field').classList.add('billing-nonletter-field');
const companyRow=byId('company').closest('.row'),addressField=byId('address').closest('.field');branding.append(companyRow,addressField);details.querySelector('h2').textContent='Document & client details';details.append(branding);
const split=document.querySelector('.split');const itemsPanel=split.firstElementChild,previewPanel=split.lastElementChild;
itemsPanel.dataset.stage='items';itemsPanel.classList.add('billing-items-panel');
const saved=document.querySelector('.savedpanel');saved.classList.add('panel');saved.dataset.stage='saved';
const options=document.querySelector('.aaw-bill-options');options.dataset.stage='items';
const ledger=byId('aawLedgerPanel');ledger.dataset.stage='preview';
previewPanel.classList.add('billing-preview');previewPanel.dataset.stage='preview';
form.append(details,itemsPanel,letterPanel,options,ledger);workspace.append(previewPanel);main.append(workspace,saved);split.remove();
// Site selector is created after cloud authorization, alongside the existing details anchor.
const observer=new MutationObserver(()=>{const site=byId('aawBillSite');if(site){site.closest('section').dataset.stage='details';observer.disconnect();}});observer.observe(form,{childList:true,subtree:true});
const search=document.createElement('div');search.className='billing-search';search.innerHTML='<label>Search documents<input id="billingSearch" type="search" placeholder="Number, client, site or date"></label><label>Document type<select id="billingFilter"><option value="">All types</option><option value="invoice">Invoice</option><option value="quotation">Quotation</option><option value="proforma">Proforma</option><option value="measurement">Measurement</option><option value="letterhead">Letterhead</option></select></label><p id="billingSearchCount" role="status"></p>';saved.querySelector('h2').after(search);
function filterSaved(){const q=byId('billingSearch').value.toLowerCase().trim(),type=byId('billingFilter').value;let shown=0;for(const row of byId('saved').querySelectorAll('.savedrow')){const doc=cloudDocs.find(d=>d.id===row.querySelector('[data-cloud-load]')?.dataset.cloudLoad);row.hidden=!(row.textContent.toLowerCase().includes(q)&&(!type||doc?.document_type===type));if(!row.hidden)shown++;}byId('billingSearchCount').textContent=shown+' documents shown · latest '+cloudDocs.length+' loaded';}
search.addEventListener('input',filterSaved);new MutationObserver(filterSaved).observe(byId('saved'),{childList:true});
let stage='details';function setStage(next){stage=next;document.body.dataset.billingStep=next;tabs.querySelectorAll('button').forEach(b=>{b.setAttribute('aria-current',String(b.dataset.step===next));});if(matchMedia('(max-width:700px)').matches)tabs.scrollIntoView({block:'start',behavior:'smooth'});}
tabs.addEventListener('click',e=>{const b=e.target.closest('[data-step]');if(b){setStage(b.dataset.step);if(!matchMedia('(max-width:700px)').matches){const target=b.dataset.step==='saved'?saved:b.dataset.step==='preview'?previewPanel:b.dataset.step==='items'?(v('type')==='letterhead'?letterPanel:itemsPanel):details;target.scrollIntoView({block:'start',behavior:'smooth'});}}});setStage('details');
const dock=document.createElement('div');dock.className='billing-dock nonprint';dock.innerHTML='<div><small>Total</small><strong id="billingDockTotal">₹0.00</strong></div><button type="button" id="billingDockSave">Save online</button><button type="button" id="billingDockPreview">Preview</button>';main.append(dock);
byId('billingDockSave').onclick=()=>cloudSave();byId('billingDockPreview').onclick=()=>setStage('preview');
// Do not bypass invoice payment-loading rules when printing from any button.
function printBill(){if(v('type')==='invoice'&&!window.aawLedgerLoaded)return alert('Open a saved invoice and wait for cloud payments before printing.');window.print();}
for(const b of main.querySelectorAll('button'))if(/Print \/ Save PDF/.test(b.textContent))b.onclick=printBill;
// Responsive item cards share the original inputs/model; no second copy of values.
const drawBase=drawRows;drawRows=function(){drawBase();const labels=['Description','Unit','Length','Width','Height','Quantity','Rate ₹','Amount ₹','Remove'];byId('items').querySelectorAll('tr').forEach((tr,i)=>{tr.querySelectorAll('td').forEach((td,n)=>{td.dataset.label=labels[n];const input=td.querySelector('input');if(input){input.setAttribute('aria-label',labels[n]);if(input.type==='number')input.inputMode='decimal';const live=input.cloneNode(true);input.replaceWith(live);live.addEventListener('input',()=>{rows[i][live.dataset.k]=live.value;tr.cells[7].lastChild.textContent=money(calc(rows[i]).amount);render();});}});const remove=tr.querySelector('button');remove.setAttribute('aria-label','Remove item '+(i+1));});};drawRows();
const dirtyStatus=document.createElement('span');dirtyStatus.id='billingDirtyStatus';dirtyStatus.setAttribute('role','status');dirtyStatus.textContent='No unsaved changes';tools.append(dirtyStatus);
let cleanSnapshot='';const snapshot=()=>JSON.stringify({...collect(),id:null,updated:null,site:byId('aawBillSite')?.value||''});
let dirty=false;function updateDirty(){dirty=cleanSnapshot!==snapshot();dirtyStatus.textContent=dirty?'Unsaved changes':'No unsaved changes';dirtyStatus.dataset.dirty=String(dirty);}
const baseRender=render;render=function(){baseRender();const letter=v('type')==='letterhead';document.body.classList.toggle('billing-is-letter',letter);byId('billingDockTotal').textContent=letter?'Letterhead':byId('grand').textContent;byId('billingDockSave').disabled=!aawCloudReady;if(cleanSnapshot)updateDirty();};
const statusBase=aawStatus;aawStatus=function(message,state){statusBase(message,state);byId('billingDockSave').disabled=!aawCloudReady;};
const baseNew=newDoc;newDoc=function(){if(dirty&&!confirm('Discard unsaved changes and start a new document?'))return false; baseNew();byId('date').value=new Date().toLocaleDateString('en-CA');cleanSnapshot=snapshot();updateDirty();setStage('details');return true;};
const baseLoad=cloudLoad;cloudLoad=function(id){if(dirty&&!confirm('Discard unsaved changes and open this document?'))return false;baseLoad(id);cleanSnapshot=snapshot();updateDirty();setStage('details');return true;};
const baseSave=cloudSave;cloudSave=async function(){const before=snapshot();const ok=await baseSave();if(ok&&snapshot()===before){cleanSnapshot=snapshot();updateDirty();dirtyStatus.textContent='Saved online · '+new Date().toLocaleTimeString('en-IN',{hour:'2-digit',minute:'2-digit'});}return ok;};
form.addEventListener('input',()=>updateDirty());form.addEventListener('change',()=>updateDirty());window.addEventListener('beforeunload',e=>{if(dirty){e.preventDefault();e.returnValue='';}});
// Preserve selected text when interacting with toolbar controls.
let selection=null;function remember(){const s=getSelection();if(s.rangeCount&&editor.contains(s.anchorNode))selection=s.getRangeAt(0).cloneRange();}
document.addEventListener('selectionchange',remember);
function restore(){editor.focus();if(selection&&editor.contains(selection.commonAncestorContainer)){const s=getSelection();s.removeAllRanges();s.addRange(selection);}}
function changed(){remember();render();updateDirty();}
function command(name,value=null){restore();document.execCommand('styleWithCSS',false,true);document.execCommand(name,false,value);changed();}
const oldActions=letterField.querySelector('.actions');oldActions.remove();
const ribbon=document.createElement('div');ribbon.className='letter-ribbon';ribbon.setAttribute('role','toolbar');ribbon.setAttribute('aria-label','Letter formatting');
function tool(label,cmd,value){const b=document.createElement('button');b.type='button';b.textContent=label;b.title=label;b.addEventListener('mousedown',e=>e.preventDefault());b.onclick=()=>command(cmd,value);ribbon.append(b);return b;}
for(const [label,cmd,val] of [['Undo','undo'],['Redo','redo'],['Bold','bold'],['Italic','italic'],['Underline','underline'],['Strike','strikeThrough'],['Left','justifyLeft'],['Center','justifyCenter'],['Right','justifyRight'],['Justify','justifyFull'],['Bullets','insertUnorderedList'],['Numbering','insertOrderedList'],['Indent','indent'],['Outdent','outdent'],['Clear format','removeFormat'],['Rule','insertHorizontalRule']])tool(label,cmd,val);
function selectTool(label,values,fn){const wrap=document.createElement('label');wrap.textContent=label;const select=document.createElement('select');select.setAttribute('aria-label',label);for(const [text,val]of values){const o=document.createElement('option');o.textContent=text;o.value=val;select.append(o);}select.onchange=()=>fn(select.value);wrap.append(select);ribbon.append(wrap);return select;}
selectTool('Font',[['Arial','Arial'],['Georgia','Georgia'],['Times New Roman','Times New Roman'],['Verdana','Verdana'],['Courier New','Courier New']],val=>command('fontName',val));
selectTool('Size',[['10','2'],['12','3'],['14','4'],['18','5'],['24','6'],['32','7']],val=>command('fontSize',val)).value='3';
selectTool('Paragraph',[['Normal','p'],['Heading 1','h1'],['Heading 2','h2'],['Heading 3','h3']],val=>command('formatBlock',val));
selectTool('Line spacing',[['1.5','1.5'],['1','1'],['1.15','1.15'],['1.8','1.8'],['2','2']],val=>{restore();const s=getSelection();let el=s.anchorNode?.nodeType===1?s.anchorNode:s.anchorNode?.parentElement;while(el&&el.parentElement!==editor&&!['P','DIV','LI','TD','TH','H1','H2','H3'].includes(el.tagName))el=el.parentElement;if(el&&editor.contains(el)&&el!==editor)el.style.lineHeight=val;else {for(const child of editor.children)child.style.lineHeight=val;}changed();});
for(const [label,cmd,value]of [['Text colour','foreColor','#30391f'],['Highlight','hiliteColor','#f2eed5']]){const l=document.createElement('label');l.textContent=label;const input=document.createElement('input');input.type='color';input.value=value;input.setAttribute('aria-label',label);input.oninput=()=>command(cmd,input.value);l.append(input);ribbon.append(l);}
// Small spreadsheet-style table controls, without pretending to run Excel formulas.
const tableTools=document.createElement('div');tableTools.className='letter-table-tools';tableTools.innerHTML='<label>Rows<input id="letterTableRows" type="number" min="1" max="12" value="3"></label><label>Columns<input id="letterTableCols" type="number" min="1" max="8" value="3"></label><button type="button" id="letterInsertTable">Insert table</button>';
function tableContext(){restore();let n=getSelection().anchorNode;n=n?.nodeType===1?n:n?.parentElement;const cell=n?.closest('td,th');return cell&&editor.contains(cell)?cell:null;}
byId('letterbody').before(ribbon,tableTools);
byId('letterInsertTable').addEventListener('mousedown',e=>e.preventDefault());byId('letterInsertTable').onclick=()=>{const r=Number(byId('letterTableRows').value),c=Number(byId('letterTableCols').value);if(!Number.isInteger(r)||!Number.isInteger(c)||r<1||r>12||c<1||c>8)return alert('Choose 1–12 rows and 1–8 columns.');command('insertHTML','<table><tbody>'+Array.from({length:r},()=>'<tr>'+Array.from({length:c},()=>'<td><br></td>').join('')+'</tr>').join('')+'</tbody></table><p><br></p>');};
for(const label of ['Add row','Add column','Delete row','Delete column','Delete table']){const b=document.createElement('button');b.type='button';b.textContent=label;b.onmousedown=e=>e.preventDefault();b.onclick=()=>{const cell=tableContext();if(!cell)return alert('Tap a table cell first.');const table=cell.closest('table'),tr=cell.parentElement,index=[...tr.cells].indexOf(cell);if(table.querySelector('[colspan],[rowspan]')&&label!=='Delete table')return alert('This imported table has merged cells. Edit its text or insert a new simple table.');if(label==='Add row'){if(table.rows.length>=30)return alert('Maximum 30 rows per table.');const row=table.insertRow(tr.rowIndex+1);for(let i=0;i<tr.cells.length;i++)row.insertCell().innerHTML='<br>';}if(label==='Add column'){if(tr.cells.length>=12)return alert('Maximum 12 columns per table.');for(const row of table.rows)row.insertCell(Math.min(index+1,row.cells.length)).innerHTML='<br>';}if(label==='Delete row'){tr.remove();if(!table.rows.length)table.remove();}if(label==='Delete column'){for(const row of [...table.rows])if(row.cells[index])row.deleteCell(index);if(!table.rows[0]?.cells.length)table.remove();}if(label==='Delete table'){if(!confirm('Remove this table and its contents?'))return;table.remove();}selection=null;changed();};tableTools.append(b);}
editor.setAttribute('role','textbox');editor.setAttribute('aria-label','Letter body');editor.setAttribute('aria-multiline','true');editor.spellcheck=true;
editor.addEventListener('paste',e=>{e.preventDefault();const data=e.clipboardData,html=data?.getData('text/html'),plain=data?.getData('text/plain')||'';restore();if(html)document.execCommand('insertHTML',false,sanitize(html));else document.execCommand('insertText',false,plain);changed();});
editor.addEventListener('drop',e=>e.preventDefault());editor.addEventListener('input',changed);
const words=document.createElement('p');words.className='muted';words.id='letterWordCount';editor.after(words);new MutationObserver(()=>{words.textContent=(editor.textContent.trim().match(/\S+/g)||[]).length+' words';}).observe(editor,{subtree:true,childList:true,characterData:true});
// Keep printable formatting sanitized, including browser-local restored documents.
const renderSafe=render;render=function(){renderSafe();if(v('type')==='letterhead'){const content=byId('preview').querySelector('[style*="min-height:420px"]');if(content)content.innerHTML=sanitize(editor.innerHTML);}};
const initialList=cloudList;let initialized=false;cloudList=async function(){await initialList();if(!initialized){initialized=true;cleanSnapshot=snapshot();updateDirty();}render();};
document.addEventListener('keydown',e=>{if((e.ctrlKey||e.metaKey)&&e.key.toLowerCase()==='s'){e.preventDefault();if(aawCloudReady)cloudSave();}});
window.AAWBillingWorkspace={setBaseline(){cleanSnapshot=snapshot();updateDirty();}};
cleanSnapshot=snapshot();render();
})();
