# Validation status

Backend project: Uss, Mumbai, Supabase Free organization. Application name remains Us.

## Passed on the deployed database

Rollback-only SQL tests use three temporary auth.users rows and switch to the authenticated database role with distinct JWT subjects. Tests leave no users or content behind.

- Six-character invitation and owner retrieval.
- Second member join and read access; duplicate couple creation rejected.
- Third-account joining, reading, and editing rejected; direct membership insertion blocked.
- Partner slot cannot be cleared by a client; used invitation consumed.
- Invitation guessing limited per authenticated account.
- Partner chat/media reads and shared-list edits permitted.
- Private journal hidden from the partner; partner cannot mark it shared.
- Third-account reads blocked across all twelve couple content tables.
- Third-account chat write, miss-me call, media read/upload rejected.
- Second miss-me within five minutes rejected; direct insertion cannot bypass the RPC.

Storage tests exercise metadata and RLS, not real image bytes or signed URL delivery. A Storage policy qualification bug caught by the tests was fixed in storage_policy_fix.sql; the full content test then passed.

Security advisor returned two informational notices for private.invites and private.join_attempts: RLS is enabled without policies. This is intentional deny-by-default protection; direct table access is revoked and only authenticated private functions access them. Reference: https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy

## Not yet implemented or verified

Flutter app, Auth UI/real signup, Google OAuth, Drift cache/sync, widget, scheduled reminders, Edge Function push delivery, notification preferences enforcement, Realtime subscriptions, complete data deletion, export, signing secret storage, Actions build, APK install/launch, and release publishing remain pending. Schema/RLS checks are not end-to-end app tests.

No signed APK or release exists yet.
