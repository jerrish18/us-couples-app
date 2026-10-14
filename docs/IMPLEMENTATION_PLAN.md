# Us — implementation plan

Status: account setup in progress. No application or APK has been built yet.

## Delivery constraints

- Flutter Android application, Riverpod, go_router, Material 3.
- Android 7.0+ universal release APK supporting ARMv7 and ARM64.
- GitHub Actions standard runners only; no paid services, billing account, or converting trials.
- Supabase Free for Auth, Postgres/RLS, Realtime, private media, Edge Functions, and scheduled jobs.
- Firebase Spark Cloud Messaging only; no Analytics, Firebase Storage, or Firebase Cloud Functions.
- Release signing material stored in GitHub Secrets, never in the public repository or logs.
- Backend publishable client configuration embedded at build time; privileged credentials kept server side.

## Stages

1. Verify repository, workflow, secret-management, Supabase, and Firebase access and zero-cost plans.
2. Implement transactional six-character invitation pairing, permanent two-member lock, scoped RLS and Storage policies, atomic miss-me cooldown, notifications, and data deletion.
3. Implement authenticated Flutter navigation and warm rose/cream theme; pairing, home, chat, calendar, memories, and More.
4. Implement Drift cache and durable idempotent sync queue, private compressed photo/voice sharing, typing/presence, receipts, replies, per-user message hiding, and heart reactions.
5. Implement dates and responses, reminders, anniversaries/milestones, shared lists, love notes, moods, timezone clock, journal, app lock, quiet hours, widget, backup export, and opt-in nudges.
6. Test pairing including concurrent joins, third-account lockout and isolation, chat/offline reconciliation, miss-me cooldown/push, date responses, reminders, and deletion.
7. Build and verify release signature and ARM architectures in Actions; install/launch on an emulator where available; publish APK to GitHub Releases only after checks pass.
8. Deliver a phone-browser download URL, APK attachment where supported, signing backup through a private channel, and short tap-only installation instructions.

## Release evidence

Record exact tested commit, successful workflow URL, APK SHA-256, signing certificate fingerprint, package ID, minimum Android SDK, and validation results. Distinguish simulated notifications from real-device delivery. Do not mark untested features as verified.

## Current dependencies

- Supabase organization selection and a verified zero-cost project.
- Firebase connection and Spark project, Android client configuration, Google OAuth configuration, and private FCM sender credentials.
- A supported route to write GitHub signing secrets and workflows.

Account setup is incomplete; this file is a plan, not a claim of implemented functionality.
