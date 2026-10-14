// Internal integration tests. All accounts and their space are synthetic and removed.
const base=Deno.env.get('SUPABASE_URL')!,key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const headers=(token=key)=>({apikey:key,Authorization:'Bearer '+token,'Content-Type':'application/json'});
async function call(path:string,body?:unknown,token=key,method='POST',allowFailure=false){
 const r=await fetch(base+path,{method,headers:headers(token),body:body===undefined?undefined:JSON.stringify(body),signal:AbortSignal.timeout(15000)});
 const text=await r.text();let data;try{data=text?JSON.parse(text):null;}catch{data=null;}
 if(!r.ok&&!allowFailure)throw Error('API request failed: '+path.split('?')[0]+' status '+r.status);
 return {ok:r.ok,data,status:r.status};
}
const rpc=async(name:string,body:unknown,token=key)=>(await call('/rest/v1/rpc/'+name,body,token)).data;
function check(value:unknown,message:string){if(!value)throw Error(message);}
async function room(cid:string,ownerId:string,token:string){
 const socket=new WebSocket(base.replace('https:','wss:')+'/realtime/v1/websocket?apikey=sb_publishable_aXy3MxGnAEatvNG2qSBchg_Qerr7OKH&vsn=1.0.0');
 const topic='realtime:couple:'+cid+':user:'+ownerId,events:any[]=[];
 const reply=await new Promise<any>((resolve,reject)=>{
  const timer=setTimeout(()=>{socket.close();reject(Error('Realtime join timed out'));},12000);
  socket.onopen=()=>socket.send(JSON.stringify({topic,event:'phx_join',payload:{config:{private:true,broadcast:{ack:true,self:false},presence:{enabled:true,key:'validation'},postgres_changes:[]},access_token:token},ref:'1',join_ref:'1'}));
  socket.onmessage=e=>{try{const message=JSON.parse(e.data);events.push(message);if(message.event==='phx_reply'&&message.ref==='1'){clearTimeout(timer);resolve(message.payload);}}catch{}};
  socket.onerror=()=>{clearTimeout(timer);socket.close();reject(Error('Realtime connection failed'));};
 });
 return {socket,topic,events,reply};
}
async function waitFor(test:()=>boolean){
 const until=Date.now()+10000;while(Date.now()<until){if(test())return;await new Promise(resolve=>setTimeout(resolve,100));}
 throw Error('Realtime event did not arrive');
}
Deno.serve(async(req)=>{
 if(req.method!=='POST')return Response.json({error:'Unauthorized'},{status:401});
 const config=await rpc('push_config',{}),provided=req.headers.get('x-worker-key')??'';
 const hash=async(s:string)=>new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(s)));
 const [a,b]=await Promise.all([hash(provided),hash(config.worker_key??'')]);let mismatch=0;
 for(let i=0;i<a.length;i++)mismatch|=a[i]^b[i];
 if(provided.length!==64||mismatch)return Response.json({error:'Unauthorized'},{status:401});
 const users:{id:string,token:string}[]=[],spaces:string[]=[],report:string[]=[];
 let photo:string|undefined;
 try{
  for(let i=0;i<3;i++){
   const email='us-validation-'+crypto.randomUUID()+'@example.invalid',password=crypto.randomUUID()+crypto.randomUUID();
   const created=(await call('/auth/v1/admin/users',{email,password,email_confirm:true})).data;
   const id=created.id??created.user?.id;check(id,'Test account creation');users.push({id,token:''});
   const signed=(await call('/auth/v1/token?grant_type=password',{email,password})).data;
   check(signed.access_token,'Email/password login');users[i].token=signed.access_token;
  }
  const owner=users[0];
  const created=await rpc('create_couple',{p_name:'Disposable integration test',p_since:'2026-01-01'},owner.token);
  const cid=created.couple_id;check(cid&&created.invite_code?.length===6,'Create space and six-character invite');spaces.push(cid);
  const race=await Promise.all(users.slice(1).map(user=>rpc('join_couple',{p_code:created.invite_code},user.token)));
  check(race.filter(result=>!result.error).length===1,'Exactly one simultaneous join succeeds');
  const partner=race[0].error?users[2]:users[1],third=race[0].error?users[1]:users[2];
  const refused=await rpc('join_couple',{p_code:created.invite_code},third.token);check(refused.error,'Third user must not join');
  check((await call('/rest/v1/couples?select=id&id=eq.'+cid,undefined,third.token,'GET')).data.length===0,'Third-user read lockout');
  report.push('Email/password login, simultaneous pairing race and third-user lockout');
  const sockets:WebSocket[]=[];
  try{
   const own=await room(cid,owner.id,owner.token);sockets.push(own.socket);check(own.reply.status==='ok','Owner private channel: '+String(own.reply.response?.reason??own.reply.response?.message??'permission rejected').slice(0,300));
   const other=await room(cid,owner.id,partner.token);sockets.push(other.socket);check(other.reply.status==='ok','Partner private channel');
   const rejected=await room(cid,owner.id,third.token);sockets.push(rejected.socket);check(rejected.reply.status==='error','Third account must not join private realtime');
   own.socket.send(JSON.stringify({topic:own.topic,event:'presence',payload:{type:'presence',event:'track',payload:{online:true}},ref:'2',join_ref:'1'}));
   await waitFor(()=>other.events.some(e=>e.event==='presence_diff'&&Object.keys(e.payload.joins??{}).length>0));
   own.socket.send(JSON.stringify({topic:own.topic,event:'broadcast',payload:{type:'broadcast',event:'typing',payload:{typing:true}},ref:'3',join_ref:'1'}));
   await waitFor(()=>other.events.some(e=>e.event==='broadcast'&&e.payload.event==='typing'&&e.payload.payload.typing));
   report.push('Private realtime presence/typing delivered; third account channel subscription rejected');
  }finally{for(const socket of sockets)socket.close();}
  const mid=crypto.randomUUID();
  await call('/rest/v1/messages',{id:mid,couple_id:cid,sender_id:owner.id,body:'Integration test'},owner.token);
  check((await call('/rest/v1/messages?id=eq.'+mid+'&select=id',undefined,partner.token,'GET')).data.length===1,'Partner reads chat');
  check((await call('/rest/v1/messages?id=eq.'+mid+'&select=id',undefined,third.token,'GET')).data.length===0,'Third cannot read chat');
  check(!(await call('/rest/v1/messages',{id:crypto.randomUUID(),couple_id:cid,sender_id:third.id,body:'Blocked'},third.token,'POST',true)).ok,'Third cannot send chat');
  await call('/rest/v1/message_states',{message_id:mid,couple_id:cid,user_id:partner.id,read_at:new Date().toISOString()},partner.token);
  const first=await rpc('send_miss_me',{p_couple:cid},owner.token),second=await rpc('send_miss_me',{p_couple:cid},owner.token);
  check(first.id&&second.error==='cooldown','Miss-me server cooldown');
  report.push('Chat delivery/read receipt and server-enforced Miss Me cooldown');
  const did=crypto.randomUUID();
  await call('/rest/v1/dates',{id:did,couple_id:cid,author_id:owner.id,title:'Private date',starts_at:new Date(Date.now()+172800000).toISOString()},owner.token);
  await call('/rest/v1/date_responses',{date_id:did,couple_id:cid,user_id:partner.id,status:'accepted'},partner.token);
  check((await call('/rest/v1/date_responses?date_id=eq.'+did,undefined,owner.token,'GET')).data[0]?.status==='accepted','Date invitation acceptance');
  report.push('Date invitation and partner acceptance');
  photo=cid+'/'+owner.id+'/validation.png';
  const pixels=Uint8Array.from(atob('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg=='),c=>c.charCodeAt(0));
  const upload=await fetch(base+'/storage/v1/object/couple-media/'+photo,{method:'POST',headers:{...headers(owner.token),'Content-Type':'image/png'},body:pixels});
  check(upload.ok,'Private photo upload');
  const signed=(await call('/storage/v1/object/sign/couple-media/'+photo,{expiresIn:60},partner.token)).data;
  const downloaded=await fetch(base+'/storage/v1'+signed.signedURL);check(downloaded.ok&&(await downloaded.arrayBuffer()).byteLength===pixels.length,'Partner signed photo download');
  check(!(await call('/storage/v1/object/sign/couple-media/'+photo,{expiresIn:60},third.token,'POST',true)).ok,'Outsider cannot sign photo URL');
  report.push('Real private photo bytes uploaded/downloaded and third-user access rejected');
  const blocked=await call('/functions/v1/delete-space',{couple_id:cid},third.token,'POST',true);check(!blocked.ok,'Outsider cannot delete space');
  const deleted=await call('/functions/v1/delete-space',{couple_id:cid},partner.token);check(deleted.status===200&&deleted.data.completed,'Partner deletes rows and photo');
  check((await call('/rest/v1/couples?id=eq.'+cid,undefined,key,'GET')).data.length===0,'Deleted couple removed');
  check((await call('/rest/v1/messages?couple_id=eq.'+cid,undefined,key,'GET')).data.length===0,'Deleted chat removed');
  const listing=await call('/storage/v1/object/list/couple-media',{prefix:cid,limit:10});check(listing.data.length===0,'Deleted photos removed through Storage API');
  photo=undefined;report.push('Complete space deletion removes database rows and real Storage objects');
  return Response.json({passed:true,report,real_device_push_tested:false,google_sign_in_tested:false});
 }catch(e){return Response.json({passed:false,report,error:e instanceof Error?e.message:'Integration test failed'},{status:500});}
 finally{
  if(photo)await call('/storage/v1/object/couple-media',{prefixes:[photo]},key,'DELETE',true).catch(()=>{});
  for(const id of spaces)await call('/rest/v1/couples?id=eq.'+id,undefined,key,'DELETE',true).catch(()=>{});
  for(const user of users)await call('/auth/v1/admin/users/'+user.id,undefined,key,'DELETE',true).catch(()=>{});
 }
});
