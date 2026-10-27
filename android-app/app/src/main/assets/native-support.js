/* Loaded only into the AAW WebView. The Android object is restricted by origin. */
(function(){
 'use strict';
 if(window.AAWNativeSupport||!window.AAWNative?.postMessage)return;
 const prefix='https://arifagroworks.github.io/arif-agro-works-website/';
 if(!location.href.startsWith(prefix))return;
 const limit=12*1024*1024;
 const post=data=>window.AAWNative.postMessage(JSON.stringify(data));
 const fail=error=>alert('AAW: '+(error?.message||error));
 let exporting=false;
 async function saveUrl(url,name){
  if(exporting)throw Error('Finish the current file export first.');
  const resolved=new URL(url,location.href);
  if(!['blob:','data:'].includes(resolved.protocol)&&!resolved.href.startsWith(prefix))throw Error('Open this download in your browser.');
  exporting=true;
  try{
   const response=await fetch(resolved.href);if(!response.ok)throw Error('Download failed.');
   const blob=await response.blob();if(blob.size>limit)throw Error('Export exceeds 12 MB. Choose a smaller date range.');
   const reader=new FileReader();
   const data=await new Promise((resolve,reject)=>{reader.onload=()=>resolve(reader.result);reader.onerror=()=>reject(Error('Unable to read the export.'));reader.readAsDataURL(blob)});
   post({action:'save',name:name||'AAW-export.bin',mime:blob.type||'application/octet-stream',data:String(data).split(',')[1]});
  }finally{exporting=false}
 }
 function printable(){
  const root=document.documentElement.cloneNode(true);
  root.querySelectorAll('script,iframe,object,embed').forEach(el=>el.remove());
  const live=document.querySelectorAll('input,textarea,select'),copies=root.querySelectorAll('input,textarea,select');
  live.forEach((input,i)=>{const copy=copies[i];if(!copy)return;if(input.tagName==='TEXTAREA')copy.textContent=input.value;else if(input.tagName==='SELECT')Array.from(copy.options).forEach((o,n)=>{if(input.options[n].selected)o.setAttribute('selected','');else o.removeAttribute('selected')});else{copy.setAttribute('value',input.value);if(input.checked)copy.setAttribute('checked','');else copy.removeAttribute('checked')}});
  root.querySelectorAll('base').forEach(el=>el.remove());
  return '<!doctype html>'+root.outerHTML;
 }
 window.print=function(){try{const html=printable();if(new Blob([html]).size>limit)throw Error('Print document exceeds 12 MB. Narrow the report.');post({action:'print',html,base:location.href,title:document.title||'AAW Document'})}catch(error){fail(error)}};
 const original=HTMLAnchorElement.prototype.click;
 HTMLAnchorElement.prototype.click=function(){if(this.hasAttribute('download')&&this.href){saveUrl(this.href,this.download).catch(fail);return}return original.call(this)};
 document.addEventListener('click',event=>{const link=event.target.closest?.('a');if(!link)return;if(link.hasAttribute('download')){event.preventDefault();saveUrl(link.href,link.download).catch(fail)}else if(link.target==='_blank'&&link.href.startsWith(prefix)){link.target='_self'}},true);
 window.AAWNativeSupport=Object.freeze({saveUrl,printable});
})();
