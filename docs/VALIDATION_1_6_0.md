# Validation for Us 1.6.0

- Source: `6086df7712949d7213d9a1d3123e4bf75a4708ff`; signed build run: https://github.com/jerrish18/us-couples-app/actions/runs/39465654374.
- All **121 Flutter tests passed**. Analyzer: no errors or warnings, four existing informational notices.
- Ninety light/dark, large-text, RTL and narrow-screen layout images generated; primary screens and expense layouts reviewed. New expense/cycle forms passed at 320dp with enlarged text and keyboard insets.
- Signed universal APK compiled, existing signing certificate verified, ARMv7/ARM64/x86_64 included. APK SHA256: `329a6097efdf02273403598b7effecb868e83f613fc197b07cc0cd661b21a844`.
- Android 7 and Android 15: exact APK installed over the previous release with unchanged app identity, reached login, handled the OAuth denial callback, and stayed alive without a reported crash.
- All twelve 64-bit native libraries passed ELF 16 KB LOAD alignment and stored library ZIP entries passed 16 KB alignment.
- Android 17 testing **skipped at the user's explicit request** on 2026-10-20. The primary test could not install its SDK package; a follow-up emulator failed to boot before app installation. Android 17 compatibility remains unverified. The release gate permits only this recorded exception; analysis, tests, signed build, source identity, checksum and Android 7/15 evidence remain required.
- Connected database tests passed in a rolled-back transaction: expense author editing, private cycle records, sharing/revocation, overlap rejection, callee-only answers, candidate isolation, third-user exclusion and deletion cascades. No new security-advisor warnings for the new tables.
- Database migration, authenticated call-relay endpoint and updated push worker are applied. Anonymous relay requests return 401.

Not performed: physical two-phone camera/media, Bluetooth, background notifications and call audio/video checks. TURN is not provisioned. Calls remain experimental and can fail on restrictive networks.
