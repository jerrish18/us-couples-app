// Synthetic-only quality probe. Never reads real couple data or prints the API key.
import fs from 'node:fs';
const key=process.env.GROQ_API_KEY;
if(!key)throw Error('Configure GROQ_API_KEY securely before running this probe.');
const cases=[
 ['English','Rewrite gently, preserving meaning: I felt sad when our plan changed. Can we choose another day?'],
 ['Tamil','அர்த்தத்தை மாற்றாமல் மென்மையாக எழுது: இன்று உன்னுடன் பேச முடியாததால் வருத்தமாக இருக்கிறது. நாளை பேசலாமா?'],
 ['Tanglish','Meaning change pannama gentle ah rewrite pannu: Innaiku unna miss panren. Nee free aana pesalama?'],
 ['English','Suggest a date plan in Chennai for two under INR 1500, 3 hours. Label all prices as estimates.'],
 ['Tamil','சென்னையில் இருவருக்கு 1500 ரூபாய்க்குள் மூன்று மணி நேர டேட் திட்டம் பரிந்துரை செய். விலைகள் உத்தேசம் என்று குறிப்பிடு.'],
 ['Tanglish','Chennai la rendu peruku 1500 budget, 3 hours date plan sollu. Prices estimate nu clear ah sollu.'],
];
const report=[];
for(const [language,prompt] of cases){
 const started=Date.now();
 const response=await fetch('https://api.groq.com/openai/v1/chat/completions',{method:'POST',headers:{Authorization:`Bearer ${key}`,'Content-Type':'application/json'},body:JSON.stringify({model:'openai/gpt-oss-120b',messages:[{role:'system',content:`Respond naturally in ${language}. Never add claims about hidden feelings. Never invent verified prices or places. Return just the answer.`},{role:'user',content:prompt}],max_completion_tokens:1200,reasoning_effort:'low'}),signal:AbortSignal.timeout(40000)});
 if(!response.ok)throw Error(`Groq returned ${response.status}; no private data used.`);
 const value=await response.json();report.push({language,prompt,answer:value.choices?.[0]?.message?.content,finish:value.choices?.[0]?.finish_reason,latency_ms:Date.now()-started,human_review:'pending: meaning, grammar, naturalness, unsupported claims'});
 await new Promise(resolve=>setTimeout(resolve,10000));
}
fs.writeFileSync('docs/ai-quality-results.json',JSON.stringify(report,null,2)+'\n');
console.log('Synthetic outputs saved. Human review required; this is not a quality pass.');
