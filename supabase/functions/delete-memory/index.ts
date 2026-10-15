// All data and Storage operations run with the caller's verified identity and RLS.
// Keep the row until object removal succeeds so a failed request can be retried.
const base = Deno.env.get('SUPABASE_URL')!;
const key = Deno.env.get('SUPABASE_ANON_KEY')!;
Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return Response.json({error: 'Method not allowed'}, {status: 405});
  const authorization = req.headers.get('Authorization') ?? '';
  if (!authorization.startsWith('Bearer ')) return Response.json({error: 'Sign in first'}, {status: 401});
  const headers = {apikey: key, Authorization: authorization, 'Content-Type': 'application/json'};
  async function api(path: string, method = 'GET', body?: unknown) {
    const res = await fetch(base + path, {method, headers,
      body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.timeout(15000)});
    if (!res.ok) throw new Error('Request failed');
    const text = await res.text(); return text ? JSON.parse(text) : null;
  }
  try {
    const userResponse = await fetch(base + '/auth/v1/user', {headers, signal: AbortSignal.timeout(10000)});
    if (!userResponse.ok) return Response.json({error: 'Unauthorized'}, {status: 401});
    const user = await userResponse.json();
    const data = await req.json();
    if (typeof data.memory_id !== 'string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(data.memory_id))
      return Response.json({error: 'Invalid memory'}, {status: 400});
    const rows = await api('/rest/v1/memories?id=eq.' + data.memory_id + '&select=id,author_id,couple_id,media_path');
    if (!rows.length) return Response.json({error: 'Memory unavailable'}, {status: 404});
    const memory = rows[0];
    if (memory.author_id !== user.id || !memory.media_path.startsWith(memory.couple_id + '/' + user.id + '/'))
      return Response.json({error: 'Only the uploader can delete this memory'}, {status: 403});
    // Storage DELETE removes real bytes. SQL deletion of storage.objects would not.
    await api('/storage/v1/object/couple-media', 'DELETE', {prefixes: [memory.media_path]});
    await api('/rest/v1/memories?id=eq.' + data.memory_id + '&author_id=eq.' + user.id, 'DELETE');
    return Response.json({deleted: true});
  } catch { return Response.json({error: 'Could not finish deleting. Please retry.'}, {status: 503}); }
});
