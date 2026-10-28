// Public, write-only endpoint. Public API key is not a user secret; quotas and RLS protect the inbox.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.57.4';
const origin='https://arifagroworks.github.io';
const publicKey='sb_publishable_s7zc99g86_YZJeN0vbCzwA_gCrkdavn';
Deno.serve(async(req:Request)=>{
 const headers={'Access-Control-Allow-Origin':origin,'Access-Control-Allow-Headers':'apikey,content-type','Access-Control-Allow-Methods':'POST,OPTIONS','Content-Type':'application/json','Vary':'Origin','Cache-Control':'no-store'};
 const reply=(code:number,body:Record<string,unknown>)=>new Response(JSON.stringify(body),{status:code,headers});
 if(req.headers.get('origin')!==origin)return reply(403,{error:'Origin denied'});
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
 if(req.method!=='POST')return reply(405,{error:'POST required'});
 if(req.headers.get('apikey')!==publicKey&&req.headers.get('apikey')!==Deno.env.get('SUPABASE_ANON_KEY'))return reply(401,{error:'API key required'});
 try{
 if(Number(req.headers.get('content-length')||0)>8192)return reply(413,{error:'Request too large'});
 const raw=await req.text();if(new TextEncoder().encode(raw).length>8192)return reply(413,{error:'Request too large'});
 const b=JSON.parse(raw);if(!b||Array.isArray(b)||typeof b!=='object')return reply(422,{error:'Invalid enquiry'});
 if(b.website)return reply(200,{accepted:true});
 if(b.consent!==true||!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(b.id||''))return reply(422,{error:'Consent and request ID required'});
 const values:Record<string,string>={};for(const [key,min,max]of [['name',2,100],['contact',6,150],['type',1,100],['location',2,200],['description',10,2000]] as const){if(typeof b[key]!=='string')return reply(422,{error:'Please complete all fields'});const v=b[key].trim();if(v.length<min||v.length>max||/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/.test(v))return reply(422,{error:'Invalid '+key});values[key]=v;}
 if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(values.contact)&&!/^\+?[\d ()-]{8,20}$/.test(values.contact))return reply(422,{error:'Enter a valid phone number or email'});
 const secret=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY'),url=Deno.env.get('SUPABASE_URL');if(!secret||!url)return reply(503,{error:'Enquiry service unavailable'});
 // Gateway-forwarded address; never store the raw address. Global daily cap remains even if addresses rotate.
 const ip=(req.headers.get('x-forwarded-for')||req.headers.get('cf-connecting-ip')||'unknown').split(',')[0].trim();
 const digest=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(secret+'|'+ip));const hash=Array.from(new Uint8Array(digest),x=>x.toString(16).padStart(2,'0')).join('');
 const db=createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false}});
 const r=await db.rpc('aaw_submit_enquiry',{p_id:b.id,p_name:values.name,p_contact:values.contact,p_type:values.type,p_location:values.location,p_description:values.description,p_ip_hash:hash});
 if(r.error){if(r.error.message.includes('Rate limit'))return reply(429,{error:'Too many enquiries. Please try later or contact us by phone.'});if(r.error.message.includes('conflict'))return reply(409,{error:'This request changed. Please start a new enquiry.'});return reply(503,{error:'Could not save enquiry. Please retry.'});}
 return reply(200,{accepted:true,reference:r.data});
 }catch{return reply(422,{error:'Please check the enquiry details'});}
});
