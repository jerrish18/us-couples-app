"""User-scoped Supabase client. The bridge never needs a service-role key."""
import asyncio
import json
import os
import time
from pathlib import Path
import httpx

class Account:
    def __init__(self, config, uid, refresh_token, http):
        self.config, self.uid, self.refresh_token, self.http = config, uid, refresh_token, http
        self.access_token = ''
        self.expires = 0
        self.lock = asyncio.Lock()
        self.path = config.state_dir / f'{uid}.json'

    def save(self):
        self.config.state_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
        self.config.state_dir.chmod(0o700)
        if self.path.is_symlink():
            raise ValueError('Refusing symlink session storage')
        temp = self.path.with_suffix('.tmp')
        fd = os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, 'w') as file:
            json.dump({'uid':self.uid, 'refresh_token':self.refresh_token}, file)
        os.replace(temp, self.path)

    async def token(self):
        async with self.lock:
            if self.expires < time.time() + 90:
                response = await self.http.post(self.config.supabase_url+'/auth/v1/token?grant_type=refresh_token',
                    headers={'apikey':self.config.supabase_key}, json={'refresh_token':self.refresh_token})
                response.raise_for_status()
                data = response.json()
                if data['user']['id'] != self.uid:
                    raise ValueError('Account changed')
                self.access_token = data['access_token']
                self.refresh_token = data['refresh_token']
                self.expires = time.time() + data['expires_in']
                self.save()
            return self.access_token

    async def request(self, method, path, *, params=None, body=None):
        response = await self.http.request(method, self.config.supabase_url+'/rest/v1/'+path,
            params=params, json=body, headers={'apikey':self.config.supabase_key,
            'Authorization':'Bearer '+await self.token(), 'Prefer':'return=representation,resolution=merge-duplicates'})
        response.raise_for_status()
        return response.json() if response.content else None

    async def select(self, table, **params):
        return await self.request('GET', table, params=params)

    async def patch(self, table, values, **params):
        return await self.request('PATCH', table, params=params, body=values)

    async def put(self, table, values):
        return await self.request('POST', table, body=values)

    async def ice(self):
        servers = [{'urls':'stun:stun.l.google.com:19302'}]
        try:
            response = await self.http.post(self.config.supabase_url+'/functions/v1/call-relay',
                headers={'apikey':self.config.supabase_key,'Authorization':'Bearer '+await self.token()}, json={})
            if response.is_success:
                servers.extend(response.json().get('iceServers', []))
        except (httpx.HTTPError, ValueError):
            pass
        return servers


def load_accounts(config, http):
    accounts = {}
    config.state_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    for path in config.state_dir.glob('*.json'):
        if path.is_symlink() or path.stat().st_mode & 0o077:
            raise ValueError('Bridge session files must be private (chmod 600)')
        data = json.loads(path.read_text())
        account = Account(config, data['uid'], data['refresh_token'], http)
        accounts[account.uid] = account
    return accounts
