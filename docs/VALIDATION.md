# Release validation

Release configuration is complete. The exact signed universal candidate passed installation and launch on Android API 24 in GitHub Actions run 38624345330. Physical-phone feature checks listed below remain unverified.

## Passed

- Flutter dependency resolution, generated Drift source, Dart analysis, auth validation and offline queue tests.
- Full debug Android compilation, including the native days/mood widget.
- Signed release candidate compilation and signature verification against the private release certificate; ARMv7 and ARM64 included; minimum API 24 and application ID checked from the APK itself.
- SQL tests: partner-only content access, third-user lockout, private journal isolation, shared lists, storage metadata restrictions, atomic five-minute Miss Me cooldown.
- SQL reminder tests: 24h/1h date offsets, leap-day birthdays, yearly milestones, deduplication, opt-in nudge and restricted scheduler execution.
- SQL deletion tests: outsiders blocked, idempotent request, new writes/uploads frozen, privileged final cleanup and row cascades.
- Live REST tests with three disposable real Auth accounts: password login; two simultaneous invite joins with exactly one winner; outsider read/write denial; chat and read receipt; Miss Me cooldown; date acceptance.
- Live private Realtime WebSocket test: presence and typing reach the partner; third account subscription is denied.
- Actual private PNG bytes: owner upload, partner signed-URL download, outsider URL signing rejected, partner-initiated deletion removes bytes through Storage API and removes space/chat rows.
- Disposable test accounts and spaces removed after tests.
- FCM service-account OAuth and FCM endpoint health confirmed; invalid dummy device token correctly rejected.
- Security advisor: no warnings/errors; four informational notices are intentional RLS-deny-all internal tables. See https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy.

- Exact signed candidate installs and reaches the login screen on Android API 24; process stays alive and no app crash is reported. WorkManager reflection and notification drawable retention fixes are verified in the optimized release.

## Outstanding

- Real Google account authorization and return to the installed app remain untested. Provider is enabled; authorization redirects to Google with the expected Firebase-project client, exact Supabase callback and basic email/profile scopes. Google documents basic-identity-only apps as exempt from the testing allowlist requirement.
- Google provider, client, callback and app redirect allowlist are configured. No Google account password or OAuth client secret is included in source or APK.
- Email confirmation remains enabled by the owner's choice. Custom Gmail SMTP settings are saved with an encrypted credential entered by the owner. Actual signup-email receipt has not yet been verified.
- Actual Android phone FCM receipt, notification action, microphone, photo picker, biometric prompts, offline network switching, widget launcher and OS scheduling behavior need real-device checks. An emulator launch is not evidence these work on a physical phone.

## Free-tier behavior

Supabase cron/push cannot run while a free project is paused. Device reminders provide a backup for dates already synced to that device. Android may delay inexact backup reminders or FCM under battery restrictions. There is no paid fallback or billing upgrade configured.
