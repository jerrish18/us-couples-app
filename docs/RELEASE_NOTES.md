# Us 1.6.0

- Expense dates, categories, outing groups, group totals, search and editing.
- Cycle care with history, symptoms, mood, calendar estimates and optional partner sharing.
- Record/select/preview/send videos and play them inside chat (50 MB cap).
- Voice/video calling implementation with private signaling, incoming notifications and active-call controls.
- Warmer dark mode, redesigned dock highlight, stronger spring motion and native haptics.
- Android 17 target with context-specific permissions and an active-call foreground service.

Calling is experimental until a TURN relay and physical two-phone tests are completed. Direct calls can fail on restrictive networks. Incoming notifications open Us to answer; full-screen native Telecom integration is not included.

Install as an update without uninstalling the existing app. Physical camera, Bluetooth and call-media checks are separate from automated installation/launch tests.

Validation: 121 Flutter tests passed; signed update/launch checked on Android 7 and 15. Android 17 testing was skipped at the user’s request and compatibility remains unverified.
