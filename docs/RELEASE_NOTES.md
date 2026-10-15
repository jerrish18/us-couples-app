# Us 1.1.0

Install this APK over your existing Us app. Do not uninstall first. The package name and signing certificate are unchanged; version code is 2.

- Explicit cold-start and running-app Google sign-in callbacks, visible retry errors, and deferred auth-state refresh.
- Targeted realtime updates, immediate save feedback, fewer full reloads and smoother Material 3 screens.
- Chat search, stars, shared pins, swipe-to-reply, edit, delete for both, six emoji reactions, document attachments (5 MB), link opening, drafts, polls, photo zoom and voice preview/playback controls.
- Android Share to Us for drafts, photos and PDFs; send is an explicit action.
- Open when letters, optional server-enforced date locks, expiring availability, equal-split expense records and memory collections.
- Opt-in live location for 15 minutes, one hour or eight hours; foreground indicator, stop, automatic expiry, last update and accuracy radius. Only the latest position is stored, outside the offline cache. OpenStreetMap is optional and requires no billing/API key.

Backend isolation/integration checks pass. Android build, signing, architecture and emulator checks run before publication. Real Google account completion, phone push and hardware GPS/screen-off behavior require physical-device verification; see UPGRADE_VALIDATION.md. GPS accuracy and background execution depend on the phone and surroundings.

Video/music connections, games, ads and analytics are excluded. Existing app features remain available. Email verification stays enabled.
