
const base = Deno.env.get("SUPABASE_URL")!;
const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const encoder = new TextEncoder();
async function api(path: string, body?: unknown, method = "POST") {
  const r = await fetch(base + "/rest/v1/" + path, {
    method, headers: { apikey: key, Authorization: "Bearer " + key, "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.timeout(15000),
  });
  if (!r.ok) throw new Error("Database request failed");
  const text = await r.text();
  return text ? JSON.parse(text) : null;
}
function b64(bytes: Uint8Array) {
  return btoa(String.fromCharCode(...bytes)).replaceAll("+","-").replaceAll("/","_").replaceAll("=","");
}
let cachedToken: {value: string; until: number} | null = null;
async function oauth(account: Record<string,string>) {
  if(cachedToken && cachedToken.until > Date.now() + 60000) return cachedToken.value;
  const now = Math.floor(Date.now()/1000);
  const header = b64(encoder.encode(JSON.stringify({alg:"RS256",typ:"JWT"})));
  const payload = b64(encoder.encode(JSON.stringify({
    iss:account.client_email,scope:"https://www.googleapis.com/auth/firebase.messaging",
    aud:"https://oauth2.googleapis.com/token",iat:now,exp:now+3600,
  })));
  const pem = account.private_key.replace(/-----[A-Z ]+-----/g,"").replace(/\s/g,"");
  const bytes = Uint8Array.from(atob(pem), c => c.charCodeAt(0));
  const privateKey = await crypto.subtle.importKey("pkcs8",bytes,
    {name:"RSASSA-PKCS1-v1_5",hash:"SHA-256"},false,["sign"]);
  const input = header+"."+payload;
  const signature = new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5",privateKey,encoder.encode(input)));
  const response = await fetch("https://oauth2.googleapis.com/token",{
    method:"POST",headers:{"Content-Type":"application/x-www-form-urlencoded"},
    body:new URLSearchParams({grant_type:"urn:ietf:params:oauth:grant-type:jwt-bearer",assertion:input+"."+b64(signature)}),
    signal:AbortSignal.timeout(15000),
  });
  if(!response.ok) throw new Error("FCM authorization failed");
  const result = await response.json();
  cachedToken = {value:result.access_token,until:Date.now()+result.expires_in*1000};
  return cachedToken.value;
}
async function equalSecret(a: string,b: string) {
  const da = new Uint8Array(await crypto.subtle.digest("SHA-256",encoder.encode(a)));
  const db = new Uint8Array(await crypto.subtle.digest("SHA-256",encoder.encode(b)));
  let different=0; for(let i=0;i<da.length;i++)different|=da[i]^db[i];
  return different===0;
}
function quietDelay(pref: any) {
  if(!pref?.quiet_start || !pref.quiet_end || pref.quiet_start===pref.quiet_end) return 0;
  let parts;
  try { parts=new Intl.DateTimeFormat("en-GB",{timeZone:pref.timezone,hour:"2-digit",minute:"2-digit",hourCycle:"h23"}).formatToParts(new Date()); }
  catch { return 0; }
  const current=Number(parts.find(p=>p.type==="hour")?.value)*60+Number(parts.find(p=>p.type==="minute")?.value);
  const minutes=(v:string)=>Number(v.slice(0,2))*60+Number(v.slice(3,5));
  const start=minutes(pref.quiet_start),end=minutes(pref.quiet_end);
  const quiet=start<end ? current>=start && current<end : current>=start || current<end;
  return quiet ? (end-current+1440)%1440 || 1440 : 0;
}
Deno.serve(async req => {
  if(req.method!=="POST")return new Response("Method not allowed",{status:405});
  try {
    const supplied=req.headers.get("x-worker-key")??"";
    if(supplied.length!==64)return new Response("Unauthorized",{status:401});
    const config=await api("rpc/push_config",{});
    if(!config?.worker_key || !await equalSecret(supplied,config.worker_key))return new Response("Unauthorized",{status:401});
    const body=await req.json().catch(()=>({}));
    const token=await oauth(config.account);
    const endpoint="https://fcm.googleapis.com/v1/projects/"+config.account.project_id+"/messages:send";
    if(body.health===true){
      const r=await fetch(endpoint,{method:"POST",headers:{Authorization:"Bearer "+token,"Content-Type":"application/json"},
        body:JSON.stringify({validate_only:true,message:{token:"not-a-real-device-token",data:{kind:"health"}}}),signal:AbortSignal.timeout(15000)});
      const details=await r.json();
      return Response.json({oauth_ok:true,fcm_status:r.status,fcm_error:details.error?.status??null});
    }
    const pending=await api("rpc/claim_pushes",{});
    let delivered=0,failed=0;
    for(const item of pending){
      try{
        const prefs=await api("notification_preferences?user_id=eq."+item.recipient_id+"&select=*",undefined,"GET");
        const pref=prefs[0];
        const toggle=item.kind==="message"?"messages":item.kind==="miss_me"?"miss_me"
          :item.kind==="date_invite"||item.kind==="date_response"?"dates":item.kind==="nudge"?"nudges":"reminders";
        if(pref?.[toggle]===false || (toggle==="nudges" && pref?.nudges!==true)){
          await api("rpc/finish_push",{p_id:item.id,p_success:true});continue;
        }
        const delay=quietDelay(pref);
        if(delay){ await api("rpc/defer_push",{p_id:item.id,p_until:new Date(Date.now()+delay*60000).toISOString()});continue; }
        const tokens=await api("device_tokens?user_id=eq."+item.recipient_id+"&select=token",undefined,"GET");
        if(!tokens.length){await api("rpc/defer_push",{p_id:item.id,p_until:new Date(Date.now()+30*60000).toISOString()});continue;}
        let success=true;
        for(const device of tokens){
          const data=Object.fromEntries(Object.entries(item.payload).map(([k,v])=>[k,String(v)]));
          data.event_id=item.id;
          const r=await fetch(endpoint,{method:"POST",
            headers:{Authorization:"Bearer "+token,"Content-Type":"application/json"},
            body:JSON.stringify({message:{token:device.token,data,android:{priority:"high",ttl:"86400s"}}}),
            signal:AbortSignal.timeout(15000)});
          if(!r.ok){
            const response=await r.json();
            if(response.error?.details?.some((d:any)=>d.errorCode==="UNREGISTERED")){
              await api("device_tokens?token=eq."+encodeURIComponent(device.token),undefined,"DELETE");
            } else success=false;
          }
        }
        await api("rpc/finish_push",{p_id:item.id,p_success:success});
        success?delivered++:failed++;
      }catch{failed++;await api("rpc/finish_push",{p_id:item.id,p_success:false}).catch(()=>{});}
    }
    return Response.json({delivered,failed});
  }catch{return Response.json({error:"Push worker could not complete this request"},{status:503});}
});
