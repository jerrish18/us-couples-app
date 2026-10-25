"""Verify ECHO against disposable local PostgreSQL, never a deployed database."""

import os
import subprocess
from pathlib import Path
from urllib.parse import urlparse

dsn = os.environ.get(
    "ECHO_TEST_DATABASE_URL", "postgresql://postgres@127.0.0.1:5432/postgres"
)
if urlparse(dsn).hostname not in ("127.0.0.1", "localhost", "::1"):
    raise SystemExit("ECHO database tests require a disposable loopback database")


def sql(text):
    subprocess.run(
        ["psql", dsn, "-X", "-q", "-v", "ON_ERROR_STOP=1"],
        input=text,
        text=True,
        check=True,
    )


existing = Path("supabase/migrations/20261020165344_us_v1_6.sql").read_text()
start = existing.index("create table public.calls(")
end = existing.index(
    "alter publication supabase_realtime add table public.calls,public.call_candidates;"
)
sql(
    """create schema auth; create schema private;
create role anon; create role authenticated; create role service_role;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create table auth.users(id uuid primary key);
grant usage on schema auth,private,public to authenticated;
create table public.couples(id uuid primary key,owner_id uuid,partner_id uuid,deleting_at timestamptz);
grant select on public.couples to authenticated;
create table private.push_outbox(couple_id uuid,recipient_id uuid,kind text,payload jsonb,unique_key text unique);
create function private.kick_push() returns bigint language sql as $$select 1::bigint$$;
"""
    + existing[start:end]
)
sql(Path("supabase/migrations/20261025082647_echo_receptionist.sql").read_text())
sql(Path("supabase/tests/echo.sql").read_text())
print(
    "PASS: ECHO permissions, atomic claiming, caller isolation and transcript erasure"
)
