# On-phone ECHO verification

This work targets the user's Pixel 8 (8 GB) and partner's reported AI+ Ultra 2 (6 GB). Neither physical handset is attached to this workspace. No handset latency, battery or Tamil/Tanglish accuracy result is invented.

Verified locally before Android packaging:

- **160 Flutter tests passed**, including existing auth/chat/media/layout/persistence coverage and new download/size/hash/resume checks. The optional real-model smoke test is deliberately skipped in the ordinary suite.
- A separate **real model smoke test passed** with the actual downloaded/checksummed Qwen3 0.6B GGUF and Whisper base int8 ONNX models: local CPU generation returned the requested greeting and offline recognition identified “tomorrow” in the synthetic English WAV. No LLM or recognizer response was mocked. The test took about 28 seconds overall in the Linux test environment; this is not phone latency.
- The initial real-model attempt failed at Linux dynamic-library lookup after language generation. Adding the packaged sherpa-onnx library directory to the Linux test environment resolved it. The second run passed. No expected response was weakened.
- Three model-manager tests passed against a local HTTP server: partial-file resume via Range, integrity rejection, and pinned catalog/pack size constraints. A first attempt's HTTP interruption fixture was invalid; the corrected test seeds a realistic partial file and exercises an actual HTTP resume request.
- Analyzer: no new errors, warnings or informational notices; four existing notices remain in unchanged core files.
- Local PostgreSQL tests verify that phone hosting blocks a legacy Mac answer, only the callee can claim the phone call, duplicate answers are rejected, takeover keeps the original SDP, and outsiders cannot read or modify the session.
- Existing bridge tests pass after host filtering. Existing normal callers and bridge-hosted accounts remain compatible.
- Native audio JVM tests cover microphone replacement with silence, resampling, bounded buffers, speech segmentation, silence rejection and late-chunk cancellation. Their Android Gradle execution and signed packaging run in the current validation workflow; consult its final status.

The archive dependency required by the on-device runtime was upgraded. Backup export now awaits ZIP finalization before sharing; its protected-file manifest records that intentional change. No signing, authentication or stored user-record migration is included.

The additive phone-host migration introduces host-specific atomic answer RPCs; no existing user records are deleted or forcibly enabled. Normal Android app support remains API 24+, with phone AI gated to supported 64-bit API 28+ devices.

Open acceptance gates: actual Android call-audio routing, microphone isolation on the handsets, real Tamil/Tanglish recognition/voice quality, same-peer human takeover on devices, locked-screen/background readiness under both vendors' restrictions, long calls, thermal behavior and battery use. The new client performs its own readiness/model/voice checks, but these gates still require physical handset validation. `release-ready.json` stays false.
