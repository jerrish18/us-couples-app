# Us AI v1.7 candidate

Adds Help me reply, Rewrite, Ask AI together, Catch me up, Turn chat into plans, Find past conversations, Date planner, expense drafting and memory captions.

## User flows

Open Us AI from the chat chip or overflow menu. A text-only `@Us ` draft opens the shared assistant for review instead of sending automatically. Long-press a saved text message for reply assistance. Expenses has an AI button. Memory composer has Suggest a caption; only the description you type is processed, not the photograph.

Each partner independently enables AI. Both must allow shared chat context for reply, shared answers, summaries, search and extracting plans. Rewrites, generic dates, expenses and captions use only the request text. You can revoke permission in the AI panel; the server checks again after inference. Permissions and private output are not written to the shared offline cache. Revocation cannot retract content already sent to Groq or explicitly shared answers.

Results are drafts. Use this text copies a suggestion into the calling composer; no message is sent. Dates/tasks/expenses require an editable review and explicit Save. Draft save buttons disable after success. The shared action explicitly says Ask & share and stores a labelled answer visible to both partners. The chat expansion shows the five newest shared answers and refreshes every 20 seconds while mounted.

## Server

`supabase/ai.sql` adds RLS preferences, shared answer storage and a service-role-only atomic quota reservation. Applied to Uss via the migration API. `supabase/tests/ai.sql` uses synthetic users inside a rolled-back transaction.

`supabase/functions/us-ai/` uses authenticated user validation and caller-scoped RLS queries. The service role is used only for atomic quota reservation and publishing a validated shared answer. No provider key enters Dart code. JWT gateway verification remains enabled. Fixed model `openai/gpt-oss-120b`, low reasoning, strict JSON schema, 1,200 completion tokens, 40-second timeout, no automatic retry or paid fallback. At most 20 attempts per couple per UTC day, 30 seconds between attempts; provider errors also consume an attempt. These app limits supplement the provider's account limits and do not guarantee availability.

Message retrieval is bounded to the newest 30 saved nondeleted text messages or keyword matches, then 4,500 UTF-8 bytes. One message contributes at most 1,200 UTF-8 bytes, truncated without splitting characters. Summary range is at most 31 days. The UI discloses partial coverage. Recall is keyword retrieval, not semantic full-history search. Citations must use IDs from the exact context; original-message buttons recheck current RLS/deletion status. Media, cycle data, location, private journal, and expense history are not retrieved.

## Activation needed

The deployed function returns setup_required until `GROQ_API_KEY` is saved under Supabase Edge Function Secrets. Use a Groq free-plan account without paid billing. No paid service has been activated. Do not paste the key into chat, the APK, GitHub files, or a public issue.

Phone setup:
1. Open https://console.groq.com/keys and create a key on your free account.
2. Open https://supabase.com/dashboard/project/mrtwyopmhmozuawgkuwi/functions/secrets .
3. Add name `GROQ_API_KEY`, paste its value, and save. Functions read new secrets without rebuilding the APK.

Before general release: run synthetic English/Tamil/Tanglish quality cases, judge meaning preservation/naturalness, and verify a real two-phone shared AI answer and plan save. No live model-quality result is claimed before these checks.

## Validation

Run `node --test supabase/functions/us-ai/logic.test.ts`, `flutter analyze --no-fatal-infos`, and `flutter test`. SQL tests cover independent consent, revocation, forged shared answers, outsider isolation, atomic rate limits and deletion cascade. Security advisor flags private.ai_usage's deliberate default-deny RLS (service-role-only). Existing leaked-password-protection warning is unrelated to this update.

## Video playback repair

Sent videos now check whether the queued capture file still exists before trying local playback. After upload, playback uses a fresh private signed streaming URL instead of waiting for a whole-file download. Decoder/init/play errors release the controller; retry builds a new player and URL. Clip changes dispose the old player; completed clips rewind before replay; initialization times out after 25 seconds. Preview keeps local playback. Native codec/HDR compatibility still needs verification on the actual phones.

The existing video message has an uploaded object with matching byte size (aggregate metadata check only; no private video content was downloaded). Tests cover a deleted capture file, a successful sent-video network fallback and a failed decoder followed by a successful retry.

Validation on 2026-10-21: all 128 Flutter tests passed; four AI logic tests passed in Node; SQL privacy/quota tests passed on Uss. Flutter analyzer returned no errors/warnings and four pre-existing informational notices. Chat screenshots reviewed. Live Groq quality evaluation, two-phone AI verification and physical-device video decoding remain pending. Android 17 testing stays skipped at the user's request. No stable v1.7 release is claimed yet.
