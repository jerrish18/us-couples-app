# Validation for the 1.6.0 candidate

Completed:
- Connected-database transaction tests: expense editing restricted to author; partner health data private until opt-in; sharing revocation enforced; overlapping period entries rejected; call answer restricted to callee; ICE isolated to participants; third-user access denied; couple deletion cascades.
- Database security advisors: no new warnings for the four new protected tables.
- Pure Dart tests: calendar-day cycle estimates, duplicate history, empty history, expense grouping/search and integer paise totals.
- Flutter analyzer: no errors or warnings; four informational notices in existing code.

- Full Flutter/widget suite: **121 tests passed** on Flutter 3.47.7 / Dart 3.13.5. The SQLite tests used a local libsqlite3.so alias to the environment’s existing libsqlite3.so.0; no application database behavior was changed.
- Screenshot review: 90 light/dark, large-text, RTL and narrow-screen images generated; reviewed the primary screen groups and new expense screen.
- New expense/cycle editor tests passed at 320dp width with 1.5x text and keyboard insets.
- Generated Android project preparation passed: all XML parses, API 37 target/compile, API 24 minimum, foreground service and nearby-device permissions present. Kotlin/Gradle compilation remains unverified until CI runs.

Publication status:
- Local implementation commit: c7b3ee61b22cea3d21b9f78cb00513ecbff0b8ce on feat/us-1-6.
- Public GitHub branch publication was rejected by automatic approval review because explicit user permission to publish the changes was required. No feature branch or PR was published and no 1.6 APK was released.
- The additive database changes, call-relay function and updated push worker are applied to the connected project. Existing client data remains supported.

Not yet completed:
- Signed APK and API 24/35/37 emulator installation/launch for this exact source.
- Physical two-device video capture, Bluetooth, background notifications and actual voice/video media exchange.
- TURN relay provisioning and testing on restrictive mobile data networks.

No release-ready declaration is made while these remain pending. Existing release-ready.json is explicitly false.
