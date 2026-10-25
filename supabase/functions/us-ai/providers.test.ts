import {test, beforeEach} from 'node:test';
import assert from 'node:assert/strict';
import {generateStructured,resetCircuits,ProviderUnavailable} from './providers.ts';
beforeEach(resetCircuits);
const config={localUrl:'http://127.0.0.1:8787',localKey:'test',groqKey:'test'};
const ok=(value:any)=>Response.json({choices:[{finish_reason:'stop',message:{content:JSON.stringify(value)}}]});
test('local first and exact context preserved when switching',async()=>{
 const requests:any[]=[]; const messages=[{role:'user',content:'Tamil context'}];
 const request=async(url:any,options:any)=>{requests.push({url,body:JSON.parse(options.body)}); return requests.length===1?new Response('',{status:429,headers:{'retry-after':'120'}}):ok({answer:'hello'});};
 const result=await generateStructured(config,messages,{},x=>x,true,request as typeof fetch);
 assert.equal(result.provider,'groq'); assert.deepEqual(requests[0].body.messages,requests[1].body.messages);
 await generateStructured(config,messages,{},x=>x,true,request as typeof fetch);
 assert.equal(requests.length,3); assert.match(requests[2].url,/groq/);
});
test('cloud quota does not prevent local inference',async()=>{
 const result=await generateStructured(config,[],{},x=>x,false,(async()=>ok({answer:'local'})) as typeof fetch);
 assert.equal(result.provider,'local');
});
test('invalid structured output switches provider',async()=>{
 let n=0;
 const result=await generateStructured(config,[],{},(x:any)=>{if(!x.answer)throw Error();return x;},true,(async()=>ok(++n===1?{}:{answer:'valid'})) as typeof fetch);
 assert.equal(n,2);assert.equal(result.provider,'groq');
});
test('5xx retry is bounded and open circuits fail fast',async()=>{
 let n=0;const request=(async()=>{n++;return new Response('',{status:503});}) as typeof fetch;
 await assert.rejects(generateStructured(config,[],{},x=>x,true,request),ProviderUnavailable);assert.equal(n,4);
 await assert.rejects(generateStructured(config,[],{},x=>x,true,request),ProviderUnavailable);assert.equal(n,4);
});
test('rejects public plaintext gateway and does not fetch',async()=>{
 await assert.rejects(generateStructured({...config,localUrl:'http://unsafe.example'},[],{},x=>x),/HTTPS/);
});
