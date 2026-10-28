/* Exact decimal RA calculations and conservative table extraction; also tested in Node. */
(function(root,factory){const api=factory();if(typeof module==='object'&&module.exports)module.exports=api;else root.AAWRAEngine=api;})(typeof window==='object'?window:globalThis,function(){
'use strict';
function decimal(value,places=6){const s=String(value??'').trim().replace(/^₹\s*/,'');if(!/^(?:\d+|\d{1,3}(?:,\d{3})+|\d{1,2}(?:,\d{2})*,\d{3})(?:\.\d+)?$/.test(s))throw Error('Invalid non-negative number: '+s);const [whole,fraction='']=s.replace(/,/g,'').split('.');if(fraction.length>places)throw Error('Too many decimal places: '+s);const n=BigInt(whole)*10n**BigInt(places)+BigInt(fraction.padEnd(places,'0')||'0');if(n>900000000000000000n)throw Error('Number exceeds supported limit');return n;}
const round=(n,d)=>(n+d/2n)/d;
function asNumber(n){if(n>BigInt(Number.MAX_SAFE_INTEGER))throw Error('Amount exceeds supported limit');return Number(n)/100;}
function calculate(items,gstRate,taxMode='igst'){
 if(!Array.isArray(items)||!items.length||items.length>200)throw Error('Enter 1–200 work items.');
 const percent=decimal(gstRate,4);if(percent>1000000n)throw Error('GST rate must be between 0 and 100.');if(!['igst','split'].includes(taxMode))throw Error('Choose IGST or CGST + SGST.');
 const lines=items.map(row=>{if(!String(row.description||'').trim()||!String(row.unit||'').trim())throw Error('Every item needs a description and unit.');const measured=['l','w','h'].some(k=>row[k]!==''&&row[k]!=null);const qty=measured?['l','w','h'].reduce((p,k)=>p*(row[k]!==''&&row[k]!=null?decimal(row[k],6):1000000n),1n):decimal(row.qty,6),rate=decimal(row.rate,4),scale=measured?1000000000000000000n:1000000n;if(qty===0n||rate===0n)throw Error('Quantity and rate must be greater than zero.');const paise=round(qty*rate,scale*100n);return {...row,qty:((qty/scale).toString()+'.'+(qty%scale).toString().padStart(measured?18:6,'0')).replace(/0+$/,'').replace(/\.$/,''),rate:String(row.rate).replace(/,/g,''),amount:asNumber(paise),paise:paise.toString()};});
 const base=lines.reduce((n,r)=>n+BigInt(r.paise),0n),igst=taxMode==='igst'?round(base*percent,1000000n):0n,cgst=taxMode==='split'?round(base*percent,2000000n):0n,sgst=cgst;
 return {lines,taxable:asNumber(base),igst:asNumber(igst),cgst:asNumber(cgst),sgst:asNumber(sgst),tax:asNumber(igst+cgst+sgst),total:asNumber(base+igst+cgst+sgst),taxablePaise:base.toString(),totalPaise:(base+igst+cgst+sgst).toString()};
}
function normalize(text){return String(text||'').replace(/[₹]/g,'').replace(/\u00a0/g,' ').trim();}
function numeric(s){try{decimal(s);return true;}catch{return false;}}
// Group OCR/PDF words by physical baseline, preserving source column order.
function groupWords(words){const lines=[];for(const w of [...words].sort((a,b)=>a.y-b.y||a.x-b.x)){if(!String(w.text||'').trim())continue;const cy=w.y+(w.h||12)/2;let line=lines.find(l=>Math.abs(l.cy-cy)<=Math.max(5,(w.h||12)*.65));if(!line){line={cy,words:[]};lines.push(line);}line.words.push(w);}return lines.sort((a,b)=>a.cy-b.cy).map(l=>l.words.sort((a,b)=>a.x-b.x).map(w=>w.text).join(' '));}
function parse(text,words=[]){
 const source=normalize(text),physical=source.split(/\r?\n/),candidates=[],warnings=[];
 // Only recognize the explicit nine-number WO / Previous / This Bill / Cumulative layout.
 const abstract=/quantit(?:y|ies)/i.test(source)&&/this\s*bill/i.test(source)&&/(?:up\s*to|upto)\s*(?:date|last)/i.test(source);
 if(abstract){
  let pending='';for(let lineIndex=0;lineIndex<physical.length;lineIndex++){let line=normalize(physical[lineIndex]);const m=line.match(/\b(KGS?|NOS?|PCS?|MT|TON|MTR|RMT|SQM|SQFT|M2|M3)\b/i);if(!m){if(/labou?r|fabricat|fixing|work|charges/i.test(line))pending=line;continue;}
   const nums=line.slice(m.index+m[0].length).trim().split(/\s+/).filter(n=>n&&!/^[=|—–]+$/.test(n));
   while(nums.length<9&&lineIndex+1<physical.length&&/^[\d,\s.=|]+$/.test(physical[lineIndex+1])){const continuation=normalize(physical[++lineIndex]);nums.push(...continuation.split(/\s+/).filter(n=>n&&!/^[=|]+$/.test(n)));line+=' '+continuation;}
   if(nums.length!==9){continue;}
   let description=line.slice(0,m.index).replace(/^\d+[.)]?\s*/,'').trim()||pending.replace(/^\d+[.)]?\s*/,'');
   if(!/[a-z]{3}/i.test(description))description=pending.replace(/^\d+[.)]?\s*/,'')||'Review work description';
   let qty=nums[4];
   // Restore a missing decimal only with three independent agreeing source columns.
   if(!qty.includes('.')||!numeric(qty))try{const delta=decimal(nums[5],3)-decimal(nums[3],3);const digits=qty.replace(/,/g,'');const expected=delta.toString();const rowPaise=round(delta*decimal(nums[1],4),100000n);const printed=decimal(nums[7],2);const gap=rowPaise>printed?rowPaise-printed:printed-rowPaise;
    if(delta>0n&&digits===expected&&gap<=50n){qty=(delta/1000n).toString()+'.'+(delta%1000n).toString().padStart(3,'0');warnings.push('A quantity decimal was restored using previous + current = cumulative and the source line amount. Verify this against the original.');}
   }catch{}
   candidates.push({description,unit:m[0].toUpperCase(),qty,rate:nums[1],sourceAmount:nums[7],sourceLine:line});pending='';
  }
 }
 // Header-driven tab / pipe / CSV extracts support other RA layouts without guessing numeric columns.
 if(!candidates.length){
  const lines=source.split(/\r?\n/);const index=lines.findIndex(l=>/description|particulars/i.test(l)&&/this\s*bill|current\s*(?:qty|quantity)/i.test(l)&&/rate/i.test(l));
  if(index>=0){const sep=lines[index].includes('\t')?'\t':lines[index].includes('|')?'|':',';const heads=lines[index].split(sep).map(s=>s.trim().toLowerCase());const di=heads.findIndex(s=>/description|particulars/.test(s)),qi=heads.findIndex(s=>/this\s*bill|current\s*(qty|quantity)/.test(s)&&! /amount/.test(s)),ri=heads.findIndex(s=>/rate/.test(s)),ui=heads.findIndex(s=>/^unit$/.test(s));
   if([di,qi,ri,ui].every(i=>i>=0))for(const raw of lines.slice(index+1)){const cols=raw.split(sep).map(s=>s.trim());if(cols.length!==heads.length||!numeric(cols[qi])||!numeric(cols[ri]))continue;candidates.push({description:cols[di],unit:cols[ui],qty:cols[qi],rate:cols[ri],sourceAmount:'',sourceLine:raw});}
  }
 }
 const rate=source.match(/(?:add\s*tax|GST|IGST)\s*(?:@|rate|\()?\s*(\d{1,2}(?:\.\d{1,2})?)\s*%/i)?.[1]||'';
 const client=source.match(/client\s*name\s*[:\-]\s*([^\n]+)/i)?.[1]?.split(/R\/A\s*Bill|Period\s*:/i)[0].trim()||'';
 const project=source.match(/project\s*name\s*[:\-]\s*([^\n]+)/i)?.[1]?.split(/R\/A\s*Bill/i)[0].trim()||'';
 const reference=source.match(/(?:R\s*\/\s*A|RA)\s*Bill\s*(?:No\.?\s*)?[:\-]\s*([A-Za-z0-9/\-]+)/i)?.[1]||'';
 if(!candidates.length)warnings.push('No work rows were mapped confidently. Add rows below using the This Bill quantity and work-order rate from the original.');
 const summary={};for(const line of physical){const values=line.split(/\s+/).filter(numeric);if(values.length>=3){if(/^\s*Total\b/i.test(line))summary.taxable=values.at(-2);if(/Add\s*tax|GST\s*@/i.test(line)&&/%/.test(line))summary.tax=values.at(-2);if(/Grand\s*Total/i.test(line))summary.gross=values.at(-2);}}
 const period=source.match(/\bPeriod\s*:\s*([^\n]+)/i)?.[1]?.trim()||'';const workOrder=source.match(/Work\s*Order\s*No\s*[:.]*\s*([^\n]+)/i)?.[1]?.split(/GST\s*:/i)[0].trim()||'';
 return {rows:candidates,client,project,reference,gstRate:rate,warnings,summary,period,workOrder};
}
return Object.freeze({decimal,calculate,parse,groupWords});
});
