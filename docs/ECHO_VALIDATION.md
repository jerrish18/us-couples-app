# ECHO candidate verification — 2026-10-25

This report distinguishes automated checks, live backend checks and unavailable device checks. It does not certify the whole app or Tamil/Tanglish voice quality as production-ready.

## Verified

- Existing repository inspected at `ba92be9` (v1.8.0). Work is isolated on `development/echo-reliability`; [draft PR #6](https://github.com/jerrish18/us-couples-app/pull/6). Main was not merged and no public production release was created.
- Initial focused Flutter regression run: **26 passed**, including opaque AI message-picker surfaces and visible selection in both themes, source filtering/context handling, draft preservation and video handoff/retry.
- Full existing Flutter suite with those regressions: **154 passed** locally. Initial SQLite failures were environment-only (`libsqlite3.so` missing); they passed after providing the system library link. No application/test expectation was weakened.
- Three additional ECHO/app-shell widget tests passed: disclosure/transcript/takeover controls on narrow light/dark screens at 1.5x text size, and the actual app shell positioning the composer 8 logical pixels above the keyboard while removing the dock. The reported floating composer did not reproduce in that verified layout; its existing placement was preserved.
- After the final media retry corrections, the **29 focused Flutter tests** passed again. Analyzer reported no errors or warnings, with four existing informational notices in unchanged core files.
- **13 TypeScript tests** passed: task parsing, byte/context limits, source validation, costs/dates, local/cloud routing, exact context preservation, quota-independent local inference, malformed-output failover, bounded retry/circuit behavior and HTTPS requirements.
- Deno type checking of the deployed `us-ai` entrypoint passed. An existing implicit `input` type was made explicit.
- **11 Python bridge tests** pass, including gateway authentication, speech-adapter fallback, schedule/expiry/manual rules, interruption segmentation, session file permissions, rate-limit failover and real local WebRTC peers/codecs. The WebRTC test keeps the original peer, forces inference failure, and checks a second human leg. Distinct tones are checked in both relay directions over actual Opus/RTP. STT/TTS/LLM are test doubles in that transport test; it does not establish human speech quality.
- Disposable PostgreSQL 17 tests passed against the original call guard and additive ECHO schema. They exercise callee-only atomic answer claims, duplicate claims, outsider denial, caller read access without write access, private preferences, transcript erasure and rejection of stale results after opt-out.
- The existing UI-scope check passed: its 24 protected backend/service files and established navigation destinations remain intact. No signing/configuration credentials were added to Git.

## Live Supabase verification

- Applied the additive `echo_receptionist` migration to the existing project. Local migration version was aligned with the server-recorded version `20261025082647`. All four ECHO tables have RLS and policies; anonymous users cannot execute `echo_answer`.
- Deployed `us-ai` version **10**, with JWT verification **enabled**. Existing cloud key/configuration was preserved; no local gateway secret or Mac endpoint was invented.
- Disposable authenticated accounts exercised real AI rewrite and selected-context reply requests. Consent denial, partner consent requirements, private draft behavior, ECHO claim arbitration, outsider isolation and live erasure protection all passed. See [ECHO_LIVE_VALIDATION.json](ECHO_LIVE_VALIDATION.json).
- Test users, their couple and calls were removed. An independent SQL count confirmed **zero remaining** for each. The temporary QA endpoint was immediately replaced by an inert HTTP 410 handler with JWT verification enabled; its one-time request credential was deleted.
- Security advisors showed no new ECHO warnings. Existing service-only private-table policy notices and the existing [disabled leaked-password protection warning](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection) remain. Existing auth settings were preserved.

## Actual local speech checks

English, Tamil and Tanglish AI disclosures synthesized into nonempty 16 kHz mono PCM using eSpeak NG/ffmpeg: approximately 9.96, 9.52 and 8.35 seconds respectively. These are robotic offline voices.

A multilingual Whisper `tiny` English smoke test returned “Hello, please call me tomorrow.” from that synthetic input. Tamil/Tanglish tests with Whisper `small` returned inaccurate transcripts; nonempty output is not an accuracy pass. For example, Tamil “நாளை எனக்கு போன் செய்யுங்கள்.” was transcribed as “அல்லாயினக்குப் போம் செய்யுங்கள்”. Tamil/Tanglish voice accuracy remains an open acceptance gate, requiring human recordings and review. The M3/Metal and installed macOS voice paths have adapters and fixture tests, but were not run on a Mac.

## Signed Android build

The existing signing workflow successfully built and verified a v1.9.0+9 candidate from `4d32043`, then installed/launched that APK on Android 7 and Android 15: [run 40176580557](https://github.com/jerrish18/us-couples-app/actions/runs/40176580557). Its certificate/package/minimum-API/ARM checks passed under the existing verification script.

A final candidate build is triggered after the last media retry corrections. The current run/check status and final downloadable artifact are linked from [PR #6](https://github.com/jerrish18/us-couples-app/pull/6) and [Flutter validation](https://github.com/jerrish18/us-couples-app/actions/workflows/flutter-validation.yml). Use the artifact from the final successful run, not an earlier intermediate build. Artifacts contain `Us.apk` and its SHA-256 file and follow the workflow's seven-day retention period.

This workspace's outbound proxy rejected the GitHub artifact-storage host, so an Actions artifact download to the workspace was not possible. The signed artifact remains accessible from GitHub to the repository owner. No debug key was substituted and no new signing key was created.

## Module audit coverage and remaining acceptance gates

| Area | Evidence / limit |
| --- | --- |
| Login and Google OAuth | Existing auth validation/UI/deep-link tests and Android callback smoke checks; no fresh real Google-account sign-in on a physical phone |
| Pairing/sync/security | Existing queue/database tests; disposable real account pairing and live RLS checks; no two-device physical synchronization soak |
| Chat/composer/selection | Existing and new widget/layout/context tests; real shell keyboard placement verified |
| Camera/gallery/video/audio | Code inspection and source-handoff/player-platform tests; no new physical camera/codec test |
| Normal and ECHO calls | Existing expiry/state tests; local real WebRTC transport/takeover test; actual two-phone, NAT/TURN and Bluetooth tests pending |
| Memories/expenses/calendar/cycle/lists | Existing widget, validation, layout and persistence tests passed; no claim of a physical end-to-end test for every module |
| Notifications/background | Existing foreground-service/FCM infrastructure reused; synthetic ECHO push outbox path exercised; real locked-screen delivery and Android background restrictions pending |
| Themes/navigation/spacing | Existing layout/snapshot suite and new selection/ECHO tests passed; unchanged navigation destinations verified |
| AI features | Existing task/schema tests plus live rewrite/reply; no claim that every generated answer in every language is factually or linguistically correct |

The user's M3 is currently unreachable. Always-on voice availability, real M3 latency, natural Tamil/Tanglish speech quality, background/locked-screen behavior, physical camera/video playback, real Google OAuth, multi-network two-phone calls and long-running battery/performance tests remain unverified. Automatic answering stays off until an authorized user enables it with a working bridge. `release-ready.json` is deliberately false.
