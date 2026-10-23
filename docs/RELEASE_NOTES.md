# Us v1.8.0 — AI, right where you write

Tap the sparkle button beside your message to use all nine AI tools without leaving chat: replies, rewrites, Ask AI together, summaries, plans, conversation search, date planning, expense drafts and memory captions.

- Suggestions and readable plans appear directly in the message box. Edit them, try another option, or Undo before sending.
- Ask AI together prepares a private draft. The usual Send button shares it when you are ready.
- Dates, tasks and expenses have a separate editable Review & save to Us action.
- New typing is preserved while AI works or a message is being sent. Closing the tools discards a pending result.
- Improved narrow-screen and keyboard layouts, larger-text support, input validation, privacy controls and error messages.

Install **Us.apk as an update** over your existing Us app; do not uninstall it. Both partners should update. The release uses the existing signing certificate and a higher Android build number.

Each person enables AI independently using the settings button in the chat AI panel. Both partners must allow shared-chat context for reply help, summaries, recall and extracting plans. Rewrites, generic date ideas, expense descriptions and captions use only your submitted text. Photos, voice recordings, location and cycle records are excluded from automatic AI context.

Groq GPT-OSS 120B powers the assistant. Limit: 20 requests per couple daily (UTC), at least 30 seconds apart. No paid fallback. Tamil and Tanglish remain beta; review wording. Recall uses limited keyword matches, and date costs are estimates.

Validation: 152 Flutter tests and 8 server logic tests. Release checks verify the existing signing certificate, ARM architectures, and in-place upgrades from v1.7.0 on Android 7 and Android 15 before publication. Physical-device and two-phone interaction checks are not claimed. Existing voice/video calls remain experimental without a provisioned TURN relay. Android 17 testing remains skipped as previously requested.
