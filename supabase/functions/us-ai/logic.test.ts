import {test} from 'node:test';
import assert from 'node:assert/strict';
import {parseInput,boundedContext,validateOutput} from './logic.ts';
const id='10000000-0000-4000-8000-000000000001';
const draft={kind:'none',title:'',starts_at:'',place:'',notes:'',amount:0,spent_on:'',category:'',outing:''};
test('validates supported actions, consent context selections and language',()=>{
 for(const language of ['English','Tamil','Tanglish'])assert.equal(parseInput({task:'reply',prompt:'Help me reply',language,message_ids:[id,id]}).ids.length,1);
 assert.throws(()=>parseInput({task:'steal',prompt:'x',language:'English'}));
 assert.throws(()=>parseInput({task:'reply',prompt:'x',language:'English'}));
 assert.throws(()=>parseInput({task:'rewrite',prompt:'x',language:'Unknown'}));
});
test('Tamil UTF-8 requests and context have byte bounds',()=>{
 assert.throws(()=>parseInput({task:'rewrite',prompt:'அ'.repeat(501),language:'Tamil'}));
 const rows=Array.from({length:30},(_,i)=>({id:`${i}`,body:'அ'.repeat(1000),created_at:'2026-10-21'}));
 const context=boundedContext(rows);
 assert.ok(Buffer.byteLength(JSON.stringify(context))<=4500);assert.ok(context.length<30);
});
test('summary range must be valid and bounded',()=>{
 for(const until of ['bad','2026-09-01','2026-12-01'])assert.throws(()=>parseInput({task:'summary',prompt:'Summarise',language:'English',from:'2026-10-01',until}));
 assert.equal(parseInput({task:'summary',prompt:'Summarise',language:'Tanglish',from:'2026-10-01',until:'2026-10-02'}).from,'2026-10-01T00:00:00.000Z');
});
test('rejects fabricated message citations and bad expense drafts',()=>{
 assert.throws(()=>validateOutput({answer:'A',suggestions:[],source_ids:['forged'],draft},[{id}]));
 assert.throws(()=>validateOutput({answer:'A',suggestions:[],source_ids:[],draft:{...draft,amount:-4}},[]));
 assert.throws(()=>validateOutput({answer:'A',suggestions:[],source_ids:[],draft:{...draft,title:'x'.repeat(121)}},[]));
 assert.equal(validateOutput({answer:'A',suggestions:['Hello'],source_ids:[id],draft},[{id}]).answer,'A');
});
