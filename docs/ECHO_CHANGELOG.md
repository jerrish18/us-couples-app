# v1.9.0+9 candidate changes

- Fix native modal surfaces inheriting a transparent bottom-sheet background. Keep the established glass appearance for sheets that explicitly request it.
- Give AI context rows visible selection colors in both themes; prune unavailable context selections when the picker opens.
- Recover video playback from a deleted local capture after upload; resolve stale voice-note files through remote storage too.
- Keep the existing composer position; add a real app-shell regression proving the composer sits above the keyboard with the dock removed.
- Add server-only local-first structured AI routing, quota-aware cloud fallback, bounded retries, circuit cooldowns and citation/output validation. Context and unsent drafts are preserved.
- Prevent a late-assigned ringing/connection timer from ending a call that connected while ICE candidates were being saved.
- Add opt-in per-partner ECHO settings, manual AI Answer, automatic delay/schedule rules, saved transcript display/history, erasure and human takeover controls.
- Add a self-hosted WebRTC bridge with independent user sessions, local multilingual STT, streaming LLM/sentence TTS, interruption handling, prepared AI identification and failure responses, message-taking and a second media leg for human takeover.
- Add local whisper.cpp and macOS installed-voice adapters with CPU/eSpeak fallback. M3 runtime and natural Tamil/Tanglish quality remain unverified.
- Add isolated RLS/atomic claim/retention tests, bridge/auth/failover tests, real local WebRTC transport tests, UI tests and CI.
- Preserve existing authentication, pairing, Firebase/Supabase configuration, navigation destinations, Android identity, signing workflow and all existing user records. No paid service or subscription is provisioned.

This candidate is not marked ready for a public production release. See the validation report for the exact build and known limits.
