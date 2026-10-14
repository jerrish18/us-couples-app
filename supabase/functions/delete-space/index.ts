const base=Deno.env.get('SUPABASE_URL')!;
const key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
async function api(path:string,body?:unknown,authorization='Bearer '+key,method='POST'){
 const response=await fetch(base+path,{method,headers:{apikey:key,Authorization:authorization,'Content-Type':'application/json'},
  body:body===undefined?undefined:JSON.stringify(body),signal:AbortSignal.timeout(15000)});
 if(!response.ok)throw new Error('Backend request failed');
 const text=await response.text();return text?JSON.parse(text):null;
}
async function equalSecret(a:string,b:string){
 const hash=async(s:string)=>new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(s)));
 const [aa,bb]=await Promise.all([hash(a),hash(b)]);let different=0;
 for(let i=0;i<aa.length;i++)different|=aa[i]^bb[i];return different===0&&a.length>0;
}
async function removeSpace(id:string){
 for(let batch=0;batch<20;batch++){
  const files:string[]=await api('/rest/v1/rpc/deletion_files',{p_couple:id});
  if(!files.length)return await api('/rest/v1/rpc/finish_space_delete',{p_couple:id});
  await api('/storage/v1/object/couple-media',{prefixes:files},undefined,'DELETE');
 }
 return false; // Free Edge runtime stays bounded. Cron resumes remaining batches.
}
Deno.serve(async(req)=>{
 if(req.method!=='POST')return Response.json({error:'Method not allowed'},{status:405});
 try{
  const worker=req.headers.get('x-worker-key');
  if(worker){
   const cfg=await api('/rest/v1/rpc/push_config',{});
   if(!await equalSecret(worker,cfg.worker_key??''))return Response.json({error:'Unauthorized'},{status:401});
   const pending:string[]=await api('/rest/v1/rpc/pending_deletions',{});let completed=0;
   for(const id of pending)if(await removeSpace(id))completed++;
   return Response.json({completed});
  }
  const auth=req.headers.get('Authorization')??'';
  if(!auth.startsWith('Bearer '))return Response.json({error:'Sign in first'},{status:401});
  // Validate the caller's JWT with Auth; never trust an unverified token payload.
  const user=await api('/auth/v1/user',undefined,auth,'GET');
  if(!user?.id)return Response.json({error:'Unauthorized'},{status:401});
  const data=await req.json();
  if(typeof data.couple_id!=='string'||! /^[0-9a-f-]{36}$/i.test(data.couple_id))return Response.json({error:'Invalid space'},{status:400});
  // The authenticated RPC checks actual membership and locks the space atomically.
  const id=await api('/rest/v1/rpc/begin_space_delete',{p_couple:data.couple_id},auth);
  const completed=await removeSpace(id);
  return Response.json({completed},{status:completed?200:202});
 }catch{return Response.json({error:'Deletion could not finish now. It will resume automatically if already requested.'},{status:503});}
});
