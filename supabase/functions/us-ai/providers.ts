/** Server-only provider routing. No URLs or credentials are accepted from clients. */
export type AiMessage = {role: string; content: string};
export type ProviderConfig = {
  localUrl?: string; localKey?: string; localModel?: string;
  groqKey?: string; groqModel?: string;
};
export class ProviderUnavailable extends Error {
  readonly configured: boolean;
  constructor(configured: boolean) {
    super(configured ? 'AI services are busy or offline. Your draft is safe. Please retry later.' :
      'Configure local ECHO inference or an optional free Groq key.');
    this.configured = configured;
  }
}
const circuits = new Map<string, {until: number; failures: number}>();
export function resetCircuits() { circuits.clear(); }
function cooldown(response: Response): number {
  const raw = response.headers.get('retry-after') ?? '';
  const seconds = Number(raw);
  const ms = raw && Number.isFinite(seconds) ? seconds * 1000 : Date.parse(raw) - Date.now();
  return Math.max(1000, Math.min(300000, Number.isFinite(ms) ? ms : 60000));
}
export async function generateStructured<T>(
  config: ProviderConfig, messages: AiMessage[], schema: unknown,
  validate: (value: unknown) => T, allowCloud: boolean | (() => Promise<boolean>) = true,
  request: typeof fetch = fetch,
): Promise<{result: T; model: string; provider: string}> {
  const providers: {name: string; url: string; key: string; model: string; local: boolean}[] = [];
  if (config.localUrl && config.localKey) {
    const url = new URL(config.localUrl);
    // TLS is mandatory outside loopback. Prevent redirect-based credential leakage.
    if (url.protocol !== 'https:' && !(url.protocol === 'http:' && ['127.0.0.1', '[::1]', 'localhost'].includes(url.hostname))) {
      throw Error('Local inference gateway requires HTTPS.');
    }
    providers.push({name:'local', url:url.href.replace(/\/$/, '') + '/v1/chat/completions', key:config.localKey, model:config.localModel ?? 'qwen3:4b', local:true});
  }
  if (config.groqKey && allowCloud) providers.push({name:'groq', url:'https://api.groq.com/openai/v1/chat/completions', key:config.groqKey, model:config.groqModel ?? 'openai/gpt-oss-120b', local:false});
  for (const p of providers) {
    if (!p.local && !(typeof allowCloud === 'function' ? await allowCloud() : allowCloud)) continue;
    const circuitKey = p.url + ':' + p.model;
    if ((circuits.get(circuitKey)?.until ?? 0) > Date.now()) continue;
    for (let attempt = 0; attempt < 2; attempt++) {
      try {
        const response = await request(p.url, {
          method:'POST', redirect:'error', headers:{Authorization:`Bearer ${p.key}`, 'Content-Type':'application/json'},
          body:JSON.stringify({model:p.model,messages,max_completion_tokens:2000,
            ...(p.local ? {} : {reasoning_effort:'medium'}),
            response_format:{type:'json_schema',json_schema:{name:'us_answer',strict:true,schema}}}),
          signal:AbortSignal.timeout(p.local ? 18000 : 10000),
        });
        if (!response.ok) {
          if (response.status === 429) {
            circuits.set(circuitKey,{until:Date.now()+cooldown(response), failures:1});
            break; // Switch immediately; do not spend the call waiting on quota.
          }
          if (response.status < 500 || attempt === 1) throw Error('Provider rejected request');
          await response.body?.cancel();
          continue;
        }
        const data = await response.json();
        if (data.choices?.[0]?.finish_reason !== 'stop') throw Error('Incomplete answer');
        const result = validate(JSON.parse(data.choices[0].message.content));
        circuits.delete(circuitKey);
        return {result, model:p.model, provider:p.name};
      } catch {
        // Includes timeouts, malformed output and validation failures. Retrying
        // only 5xx above bounds total latency and avoids duplicate generation.
        const failures = (circuits.get(circuitKey)?.failures ?? 0) + 1;
        circuits.set(circuitKey,{until:Date.now()+Math.min(300000, 15000*failures),failures});
        break;
      }
    }
  }
  throw new ProviderUnavailable(Boolean(config.localUrl && config.localKey || config.groqKey));
}
