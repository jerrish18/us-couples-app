# Us v1.8.0 release verification

The signed v1.8.0+8 candidate was built from `2e8fd55c261a1249e814a10a04c191cc1c817d02` in [GitHub Actions run 40004638565](https://github.com/jerrish18/us-couples-app/actions/runs/40004638565).

- 152 Flutter tests and 8 server logic tests passed. Analyzer: no errors or warnings, four existing informational notices. UI scope and repository credential-file checks passed.
- The existing Android signing certificate, package identity, version, minimum Android API 24, and ARM architectures passed `scripts/verify_apk.py` in the build. The publication workflow verifies the exact artifact again.
- The exact signed candidate passed in-place upgrade from public v1.7.0, launch, process-survival and OAuth-denial callback checks on Android 7 and Android 15. Existing app identity remained unchanged. Android 17 remains skipped as previously requested.
- All 12 checked 64-bit shared libraries have ELF LOAD alignment >= 16 KB and stored ZIP entries aligned to 16 KB.
- Supabase `us-ai` version 9 is active with JWT verification. A real Groq request through the authenticated endpoint passed with synthetic paired users. AI was blocked by default, blocked with only one partner consenting, returned a private answer after both opted in, stored no shared answer even with an attempted publication flag, and was blocked again after revocation.
- The synthetic couple and users were removed; a separate SQL count confirmed zero remaining. The temporary validation endpoint was replaced by an inert, JWT-protected HTTP 410 handler.

APK SHA-256: `bd91c21c368b2c334ff430763b32c3e3af0968dd9d04bd5077ef529c4491f1b4`.

The release publishes the same candidate, with no rebuild after emulator verification. See `release-ready.json`, `NATIVE_ALIGNMENT_1_8_0.json` and `LIVE_AI_VALIDATION_1_8_0.json` for machine-readable evidence.

Physical-device/two-phone checks were not performed. Tamil/Tanglish wording, bounded keyword recall, provider quotas and experimental calling limitations remain as described in the release notes.
