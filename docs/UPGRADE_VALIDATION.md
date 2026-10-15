# Us 1.1 validation

Backend transaction tests in `supabase/tests/upgrade_v1_1.sql` passed on the project: third-account isolation, location identity and stop, date-locked letter secrecy, author-only message editing, couple pins, hiding expired positions, and cascading deletion of the new feature data. All fixtures roll back.

The deployed integration harness also passed login, simultaneous pairing and third-user lockout, private realtime typing/presence, chat/read receipts, five-minute Miss Me cooldown, date invitation acceptance, actual private photo upload/download, and deletion of rows and Storage objects. Synthetic accounts were removed.

Android validation requires analysis, unit/widget/SQLite tests, signed universal release build, signature/resource/architecture verification, installation and launch on API 24, and the actual Android OAuth-denial deep-link callback. No production credentials enter these tests or artifacts.

Limitations: successful Google account authorization, real-phone FCM delivery/actions, hardware GPS accuracy, screen-off location behavior under vendor battery policies and microphone recording have not been tested on two physical phones. Android can pause location updates; accuracy and freshness are displayed. No claim of exact GPS or universal feature parity with every messaging app is made.

The local Flutter dependency check was stopped by automatic review after an attempted cloud metadata endpoint request. Subsequent compilation and verification use the GitHub Actions pipeline.
