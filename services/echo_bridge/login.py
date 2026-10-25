"""Create a separate Supabase session on the trusted Mac, never copy app tokens."""
import asyncio
import getpass
import sys
import time
from urllib.parse import urlparse, parse_qs
from uuid import UUID
import httpx
from .config import Config
from .store import Account

async def login(password=False):
    config=Config()
    email=input('Your existing Us account email: ').strip()
    async with httpx.AsyncClient(timeout=20,follow_redirects=False) as http:
        headers={'apikey':config.supabase_key}
        if password:
            secret=getpass.getpass('Us password (not stored): ')
            response=await http.post(config.supabase_url+'/auth/v1/token?grant_type=password',headers=headers,json={'email':email,'password':secret})
        else:
            response=await http.post(config.supabase_url+'/auth/v1/otp',headers=headers,json={'email':email,'create_user':False})
            if not response.is_success:
                raise RuntimeError('Could not send login email. Check email auth settings and free email limits.')
            print('Copy the sign-in link from the email without opening it. This creates a separate bridge session.')
            link=getpass.getpass('Sign-in link (hidden, not stored): ')
            parsed=urlparse(link)
            if parsed.scheme!='https' or parsed.netloc!=urlparse(config.supabase_url).netloc or parsed.path!='/auth/v1/verify':
                raise ValueError('Use the verification link from your configured Supabase project')
            query=parse_qs(parsed.query)
            token=query.get('token',query.get('token_hash',['']))[0]
            kind=query.get('type',['magiclink'])[0]
            if not token or kind not in ('magiclink','email'):
                raise ValueError('Invalid sign-in link')
            response=await http.post(config.supabase_url+'/auth/v1/verify',headers=headers,json={'token_hash':token,'type':kind})
        if not response.is_success:
            raise RuntimeError('Sign-in failed. The link may be expired or already used.')
        data=response.json()
        uid=str(UUID(data['user']['id']))
        account=Account(config,uid,data['refresh_token'],http)
        account.save()
        print('Bridge authorized with a separate session. Start the bridge; enable ECHO in Us settings when ready.')

def main():
    try:
        asyncio.run(login('--password' in sys.argv))
    except Exception as error:
        # Server responses can contain private auth details. Keep errors bounded.
        print(str(error) if isinstance(error,(RuntimeError,ValueError)) else 'Bridge sign-in could not finish.',file=sys.stderr)
        raise SystemExit(1)
