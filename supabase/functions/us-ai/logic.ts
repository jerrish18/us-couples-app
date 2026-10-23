export const tasks = ['reply','rewrite','together','summary','plans','search','date','expense','caption'] as const;
export type Task = typeof tasks[number];
export const historyTasks = new Set<Task>(['reply','together','summary','plans','search']);
export function parseInput(raw: any) {
  // A separate wire action makes private drafting fail closed on older servers.
  const action = raw?.task === 'ask' ? 'together' : raw?.task;
  if (!raw || !tasks.includes(action)) throw Error('Choose a supported AI action.');
  const task = action as Task;
  const prompt = typeof raw.prompt === 'string' ? raw.prompt.trim() : '';
  if (!prompt || new TextEncoder().encode(prompt).length > 1500) throw Error('Enter up to 1,500 bytes of text.');
  if (!['English','Tamil','Tanglish'].includes(raw.language)) throw Error('Choose a language.');
  const ids = Array.isArray(raw.message_ids) ? [...new Set(raw.message_ids)] : [];
  if (ids.length > 30 || ids.some(x => typeof x !== 'string' || !/^[a-f0-9-]{36}$/i.test(x))) throw Error('Select up to 30 saved messages.');
  if (['reply','plans'].includes(task) && ids.length === 0) throw Error('Select a saved message first.');
  let from: string | undefined, until: string | undefined;
  if (task === 'summary') {
    const start = Date.parse(raw.from), end = Date.parse(raw.until);
    if (!Number.isFinite(start) || !Number.isFinite(end) || end <= start || end-start > 31*86400000) throw Error('Choose a range of up to 31 days.');
    from = new Date(start).toISOString(); until = new Date(end).toISOString();
  }
  const budget=raw.budget ?? 1500, minutes=raw.minutes ?? 180;
  if(task==='date' && (!Number.isFinite(budget)||budget<1||budget>100000||!Number.isInteger(minutes)||minutes<30||minutes>1440)) throw Error('Choose a budget from INR 1 to 100,000 and 30 to 1,440 minutes.');
  if(raw.publish !== undefined && typeof raw.publish !== 'boolean') throw Error('Choose whether to share the answer.');
  // Older clients explicitly label together as Ask & share. New composers request a private draft.
  const publish = task === 'together' && raw.task !== 'ask' && raw.publish !== false;
  return {task,prompt,language:raw.language,ids,from,until,budget,minutes,publish};
}
export function textWithinBytes(text: string, maxBytes = 1200) {
  let result = '', bytes = 0;
  for (const character of text) {
    const size = new TextEncoder().encode(character).length;
    if (bytes + size > maxBytes) break;
    result += character; bytes += size;
  }
  return result;
}
export function boundedContext(rows: any[], maxBytes = 4500) {
  const result: any[] = [];
  for (const row of rows) {
    const item = {id:row.id, text:textWithinBytes(String(row.body ?? '')),at:row.created_at,speaker:row.speaker??'unknown'};
    if (new TextEncoder().encode(JSON.stringify([...result,item])).length > maxBytes) break;
    result.push(item);
  }
  return result;
}
export const schema = {
  type:'object', additionalProperties:false,
  required:['answer','suggestions','source_ids','draft','itinerary'],
  properties:{
    itinerary:{type:'array',items:{type:'object',additionalProperties:false,required:['activity','estimated_cost','minutes'],properties:{activity:{type:'string'},estimated_cost:{type:'number'},minutes:{type:'integer'}}}},
    answer:{type:'string'},suggestions:{type:'array',items:{type:'string'}},
    source_ids:{type:'array',items:{type:'string'}},
    draft:{type:'object',additionalProperties:false,
      required:['kind','title','starts_at','place','notes','amount','spent_on','category','outing'],
      properties:{kind:{type:'string',enum:['none','date','expense','todo']},title:{type:'string'},starts_at:{type:'string'},place:{type:'string'},notes:{type:'string'},amount:{type:'number'},spent_on:{type:'string'},category:{type:'string'},outing:{type:'string'}}}
  }
};
export function validateOutput(data: any, context: any[]) {
  if (!data || typeof data.answer !== 'string' || data.answer.length > 6000 || !Array.isArray(data.suggestions) || data.suggestions.length > 5 || data.suggestions.some((s:any)=>typeof s!=='string'||s.length>4000) || !Array.isArray(data.source_ids) || !data.draft) throw Error('AI returned an incomplete answer. Please try again.');
  const valid = new Set(context.map(m=>m.id));
  if (data.source_ids.some((id:any)=>!valid.has(id))) throw Error('AI cited a message outside the selected context.');
  const d=data.draft;
  if(!['none','date','expense','todo'].includes(d.kind) || typeof d.title!=='string' || d.title.length>120 || typeof d.notes!=='string' || d.notes.length>4000 || typeof d.place!=='string' || d.place.length>250 || !Number.isFinite(d.amount) || d.amount<0 || d.amount>9999999 || typeof d.spent_on!=='string' || typeof d.starts_at!=='string' || typeof d.category!=='string' || typeof d.outing!=='string') throw Error('AI returned an invalid draft.');
  if(d.kind!=='none' && !d.title.trim()) throw Error('AI draft needs a title.');
  if(d.kind==='expense') {
    const date=/^\d{4}-\d{2}-\d{2}$/.test(d.spent_on) ? new Date(d.spent_on+'T00:00:00Z') : null;
    if(!date || !Number.isFinite(date.getTime()) || date.toISOString().slice(0,10)!==d.spent_on || d.amount<=0 || d.notes.length>1000 || d.outing.length>100 || !['Food','Travel','Shopping','Stay','Entertainment','Bills','Gifts','Other'].includes(d.category)) throw Error('AI returned an invalid expense date, amount or category.');
  }
  if(d.kind==='date' && (!/^\d{4}-\d{2}-\d{2}T.*(?:Z|[+-]\d{2}:\d{2})$/.test(d.starts_at) || !Number.isFinite(Date.parse(d.starts_at)))) throw Error('AI date draft needs an explicit valid time zone and time.');
  return data;
}

export function dateBudget(data:any,budget:number,minutes:number) {
  if(!Array.isArray(data.itinerary)||!data.itinerary.length||data.itinerary.length>8)throw Error('Date planner needs a short itinerary.');
  let paise=0,totalMinutes=0;
  for(const item of data.itinerary){
    if(typeof item.activity!=='string'||!item.activity.trim()||item.activity.length>300||!Number.isFinite(item.estimated_cost)||item.estimated_cost<0||item.estimated_cost>100000||!Number.isInteger(item.minutes)||item.minutes<1||item.minutes>1440)throw Error('Date planner returned invalid costs or times.');
    paise+=Math.round(item.estimated_cost*100);totalMinutes+=item.minutes;
  }
  if(paise>Math.round(budget*100)||totalMinutes>minutes)throw Error('This itinerary exceeds your budget or time. Try generating a simpler plan.');
  return {total:paise/100,limit:budget,total_minutes:totalMinutes,minutes_limit:minutes};
}

export function searchTerms(prompt:string) {
 const stop=new Set(['which','what','where','when','did','do','we','our','ours','on','the','a','an','is','was','were','have','has','had','decide','decided','choose','chosen','tell','me','about','find','past','conversation','conversations','please','namma','enna','enga','endha','eppo','pannom','நாம்','நம்ம','எந்த','என்ன','எங்கே','எப்போது']);
 const all=prompt.match(/[\p{L}\p{M}\p{N}]+/gu)??[];
 return [...new Set(all.filter(t=>t.length>1&&!stop.has(t.toLowerCase())))].slice(0,6);
}
