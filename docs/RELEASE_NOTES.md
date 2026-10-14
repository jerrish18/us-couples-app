# Us 1.0.0

Private couples app for Android 7.0 and later. Signed universal APK includes ARMv7 and ARM64; x86_64 is included for emulator verification. Package: com.jerrish18.us.

## Included

Email/password signup with email confirmation and resend, Google sign-in, six-character invite with permanent two-member lock and partner-only Row Level Security. Real-time text/photo/voice chat, replies, read receipts, heart reactions, typing/presence and durable offline queue with private media cache. Miss Me with server-enforced five-minute cooldown, history and notification reply. Shared dates, responses, calendar, 24h/1h reminders, anniversaries and milestones. Memories, shared lists, love notes, moods, manual partner time zone, private/shared journal, days/mood widget, export, optional PIN/biometric lock, themes, notification preferences and quiet hours. Unlink deletes couple rows and private media bytes.

Backend configuration is included. Server credentials and private signing key are excluded. No ads, analytics or tracking SDKs. Free plans only; no paid fallback is configured.

## Validation and limits

Dart analysis and automated tests pass. Signed candidate was installed and launched on Android API 24 through GitHub Actions. Live backend tests cover racing joins, third-user denial, chat/read state, private typing/presence, Miss Me cooldown, date response, actual private photo upload/download/deletion. SQL tests cover scheduled reminders, milestones, private journals and full deletion. The publishing workflow repeats signature, architectures, package, minimum API and exact APK installation/launch checks before publishing.

Physical-phone FCM delivery/actions, Google account authorization, email receipt, camera/microphone, biometric UI, widgets and OS reminder timing have not been verified. FCM service-account authentication and the send endpoint were checked without a real device token. Supabase Free may pause inactive projects; server pushes/reminders cannot execute while paused. Local reminders cover dates previously synced to the phone; Android may delay inexact reminders or push delivery under battery restrictions.

Keep the private signing backup provided separately. It is never a release asset.
