// Optional standard coturn REST authentication. Configure TURN_URL and
// TURN_SHARED_SECRET in Edge Function secrets; credentials expire in 10 minutes.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.95.3";
Deno.serve(async(req:Request)=>{
  const auth=req.headers.get('Authorization');
  if(!auth)return new Response('Unauthorized',{status:401});
  const client=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_ANON_KEY')!,{global:{headers:{Authorization:auth}}});
  const {data:{user},error}=await client.auth.getUser();
  if(error||!user)return new Response('Unauthorized',{status:401});
  const {data:couple}=await client.from('couples').select('id').or(`owner_id.eq.${user.id},partner_id.eq.${user.id}`).is('deleting_at',null).limit(1).maybeSingle();
  if(!couple)return new Response('Pair first',{status:403});
  const secret=Deno.env.get('TURN_SHARED_SECRET'),urls=(Deno.env.get('TURN_URL')??'').split(',').filter(x=>/^turns?:/.test(x));
  if(!secret||!urls.length)return Response.json({iceServers:[],relayConfigured:false});
  const username=`${Math.floor(Date.now()/1000)+600}:${user.id}`;
  const key=await crypto.subtle.importKey('raw',new TextEncoder().encode(secret),{name:'HMAC',hash:'SHA-1'},false,['sign']);
  const signed=new Uint8Array(await crypto.subtle.sign('HMAC',key,new TextEncoder().encode(username)));
  const credential=btoa(String.fromCharCode(...signed));
  return Response.json({iceServers:[{urls,username,credential}],relayConfigured:true},{headers:{'Cache-Control':'no-store'}});
});
