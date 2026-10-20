# Us 1.6.0

This update adds expense organization, cycle care, video messages, and a WebRTC calling implementation, and refines the existing visual system. It requires the existing v1.5 database plus the new migration. Keep the existing signing key and app installation.

## Expense organization

`lib/features/expenses/expenses_screen.dart` replaces the old generic expense list. Each expense has a spending date, category, optional outing/purpose, and notes. Switch between date, category and outing groups, search descriptions and groups, and inspect group totals. Only the author can edit/delete. Existing equal-split semantics are retained. Totals are calculated in integer paise. Legacy records use their creation date in India because their actual spending date was never recorded.

## Cycle care

Open More → Cycle care. Each account sets up its own tracker. The person tracking their period must set it up on their own phone/account; the app never infers whose body is being tracked from gender or couple ownership. Log date ranges, flow, symptoms, mood and notes. The month view distinguishes logged days from estimated days. Estimates use up to six recent valid recorded intervals; with insufficient history, the chosen typical length is used. Dates are normalized to calendar days to avoid daylight-saving differences.

Sharing is off initially. The owner can opt into sharing all their logged fields with their partner, revoke sharing, edit/delete entries, or delete the tracker and its history. Database policies enforce these choices. Health records are fetched separately from UsSpace and never put in its shared offline cache or ordinary space backups. Pausing clears this screen's in-memory records; resuming fetches fresh permissions/data. A partner who already saw information cannot have that knowledge withdrawn. Forecasts are estimates, not ovulation confirmation or contraception.

## Video messages

Chat attachment sheet includes Record video and Video gallery. Recording is limited to two minutes by the picker. A local preview is available before sending. Supported containers: MP4, MOV, M4V and 3GP. Limit: 50 MB; music and other files remain 5 MB. Videos download/play only after tapping, can be paused/scrubbed, and pause when the app backgrounds. There is no transcoding: a long/high-resolution capture can exceed the cap and must be shortened. Audio/video permissions are requested at use. Android picker lost-data recovery asks before sending recovered videos.

## Calls

Voice/video actions in chat use flutter_webrtc, Supabase private database signaling and the existing authenticated push worker. Includes answer/decline/end, mute, speaker, camera toggle/switch, ICE candidate exchange, timeouts and peer cleanup. Android starts a microphone/camera foreground service after foreground permission acquisition; its ongoing notification can reopen/end the call. Incoming calls use a notification that opens Us to answer; this is not a native full-screen Telecom/CallKit integration. Force-stopped apps and blocked notifications cannot reliably receive calls.

A direct STUN connection is available. **A production TURN relay is not provisioned. Calls can fail on restrictive mobile networks until one is configured.** `call-relay` validates the user's session and couple membership and can mint short-lived standard coturn REST credentials from Edge secrets `TURN_URL` and `TURN_SHARED_SECRET`. No long-lived relay secret belongs in the APK or repository. No paid relay account or usage has been enabled. This candidate must not be described as a reliable calling release before relay and two-phone testing.

Signaling expires ringing calls after 60 seconds and active sessions after two hours; cleanup removes SDP/candidates after one day. Only the intended callee can supply an answer. Couple membership, immutable identity grants, live-call uniqueness and state transitions are enforced server-side. Push dispatch rechecks ring state and expires incoming notifications. Notification preferences/quiet hours still apply.

## Android and UI

Targets/compiles Android 17 (API 37), retaining minimum API 24. Requests Android 17 local-network permission and Android 12+ Bluetooth connection permission at call use. Adds modern system haptic confirmations with fallback and throttling; honors system haptic settings. The dock uses an icon-sized selected pill and consistent icon/label geometry. Dark surfaces, accent containers, glass borders and ambient glow are retuned. Page entrances and press springs are more expressive while respecting reduced-motion settings.

## Validation

The SQL suite `supabase/tests/us_v1_6.sql` passed against the connected database in a rolled-back transaction: expense ownership, private cycle data, opt-in sharing/revocation, overlap rejection, callee-only answer, ICE visibility, third-account isolation and deletion cascades. Security advisors reported no new table/policy warnings.

All 121 Flutter tests passed. Analysis reported no errors or warnings, with four existing informational notices. Ninety layout snapshots were generated, and primary light/dark and expense views were reviewed. The signed universal APK compiled successfully, retained the existing signing certificate, and passed in-place update, launch and OAuth-denial callback checks on Android 7 and 15. Its 64-bit native libraries and stored ZIP entries were checked for 16 KB page alignment.

Android 17 testing was skipped at the user's explicit request. Its initial SDK setup failed, and a subsequent emulator failed to boot before installation. Compatibility with Android 17 remains unverified. Automated startup checks do not establish two-phone camera, Bluetooth, background push, call audio/video or mobile-network relay reliability.

## Source map

- `lib/features/expenses/`: grouping logic, forms and list.
- `lib/features/cycle/`: estimates, forms and calendar.
- `lib/features/calls/`: service, signal processing, overlay and controls.
- `lib/features/chat/video_bubble.dart`: local/private playback.
- `lib/core/haptics.dart`, `theme.dart`, `design.dart`: shared feedback and visuals.
- `android_templates/MainActivity.kt`, `UsCallService.kt`: permissions/haptics/foreground service.
- `supabase/migrations/20261020165344_us_v1_6.sql`: additive database changes.
- `supabase/functions/call-relay/`: authenticated relay credential endpoint.

The UI scope baseline was updated only for authorized media-service changes and the Cycle care route. All other protected backend/service files remain guarded. The release report binds the published APK to its source, checksum and validation runs.
