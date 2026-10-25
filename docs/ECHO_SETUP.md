# ECHO self-hosted voice receptionist (v1.9 candidate)

ECHO extends the existing Us Flutter/Supabase/WebRTC app. It does not replace the app, change its package ID or signing key, or migrate existing user records. Automatic answering is **off by default**. Each partner authorizes their own bridge session and answering preferences.

## What runs where

- Flutter keeps the existing normal audio/video calls and adds AI Answer, Take over call, live saved transcripts, and ECHO settings/history under Profile and settings.
- A trusted Mac runs `services/echo_bridge`. It polls the existing calls as the callee using an independent Supabase user session. It terminates a WebRTC audio leg, transcribes locally, streams LLM text into sentence-level speech, and sends audio back over the same connection.
- Human takeover adds a second WebRTC audio leg between the callee's phone and the bridge. Audio is relayed through the bridge. The original caller connection and its DTLS transport remain open. The bridge must continue running after takeover.
- ECHO always plays an AI identification. The first two seconds are protected from interruption. Later caller speech cancels pending generation and queued speech.
- Local inference defaults to Ollama. An optional server-side free Groq key enables failover. Context stays in the same bounded conversation during switching. Provider failures do not close the media peer. Saved message-taking acknowledgements are used only after a successful database write.
- STT uses bounded VAD utterances, with recognition after a pause (or a 12-second segment). It does not expose partial word-by-word transcription. TTS streams sentence-by-sentence rather than sample-by-sample neural generation.
- Speech uses local multilingual Whisper and local eSpeak NG. macOS can use an installed natural voice through `say`. A local whisper.cpp server can use Metal on the M3, with CPU Whisper as fallback.

This is an experimental voice candidate. English synthetic speech/recognition and local WebRTC transport were exercised. Tamil/Tanglish speech synthesized successfully, but synthetic-voice transcription was inaccurate. Natural Tamil/Tanglish conversation quality, M3 latency, two physical phones, and Android locked-screen behavior have **not** been validated. Do not rely on it for emergencies.

## Zero additional subscription cost

Use the existing Mac, Ollama, multilingual Whisper, eSpeak NG, existing Supabase/Firebase project and current signing workflow. No paid API is required. Optional Groq is subject to its free account limits; leave its key empty for local-only voice. No paid plan is provisioned or automatically upgraded.

The existing cloud text-AI allowance is still capped at 20 shared requests/day and one request per 30 seconds. Local inference does not consume that allowance and can continue when cloud quota is exhausted. Local capacity and availability are finite too.

A sleeping, disconnected or powered-off Mac cannot answer. A bridge process failure interrupts calls that depend on that bridge; an LLM/STT/TTS inference failure is handled separately and leaves the media connection alive. Free tunnels and free cloud hosting offer no always-on guarantee. Supabase free projects, email delivery, quotas, network restrictions, and any existing free TURN relay also limit availability. NATs that need TURN will fail without a reachable relay; no new paid relay is configured.

## Prepare the Mac

Install a supported Python (3.11 recommended), Ollama, ffmpeg and eSpeak NG using their free distributions. With Homebrew already installed:

```sh
brew install python@3.11 ollama ffmpeg espeak-ng
ollama serve
```

In a second terminal:

```sh
ollama pull qwen3:4b
cd /path/to/us-couples-app/services
python3.11 -m venv .venv
source .venv/bin/activate
python -m pip install -r echo_bridge/requirements.txt
cp echo_bridge/.env.example .env
chmod 600 .env
```

Edit the ignored `.env` locally. Set `SUPABASE_URL` and its **publishable** key from the existing project (also identified in `lib/core/config.dart`). Never use the service-role key. Choose `ECHO_STATE_DIR` on a private local disk, outside sync/shared folders. Existing app signing secrets are unrelated and must stay in the existing signing workflow.

The 4B model and concurrent speech models need memory. On a smaller M3, consider `qwen3:1.7b` and set `ECHO_MODEL` accordingly; accuracy and latency must be assessed on that Mac. Whisper downloads its model on first startup. Download models while online; cached models can then run without an AI provider account. App signaling still needs Supabase connectivity.

Load configuration in each terminal that runs the bridge:

```sh
set -a
source .env
set +a
python -m echo_bridge login
```

The login command requests a magic-link email for the **existing** Us account. Copy the verification link from the email into the hidden terminal prompt without opening it. This creates an independent bridge session and does not copy the phone's refresh token. It requires email login to be enabled and an unused, unexpired link; the free email provider has strict sending limits. For an existing password account, use `python -m echo_bridge login --password` instead. Passwords and verification links are never stored. Do not paste credentials into chat or GitHub.

The bridge stores only its rotating Supabase refresh token in a directory with mode 700 and files with mode 600. Treat that Mac account as trusted. Start the service:

```sh
python -m echo_bridge
```

Voice readiness stays false until disclosure/fallback audio and the CPU STT model are prepared. Open `http://127.0.0.1:8787/health` on the Mac to check `voice_ready` and `local_llm_ready`. Only readiness flags are returned. Ollama can be unavailable while voice message-taking remains ready.

In Us: Profile and settings → ECHO receptionist → Check bridge status. Enable answering, choose manual/automatic/scheduled rules, language, voice style, greeting and whether to save transcripts, then Save. Rules apply only to voice calls. Schedule times use the displayed IANA time zone; equal start/end means all day and overnight ranges are supported. Default time zone is Asia/Kolkata.

Keep the Mac awake, allow Python's necessary WebRTC network access, and retain the existing call-relay configuration. Automatic answering runs on the Mac, so it does not need to acquire an Android microphone from the background. The phone still needs normal notification permissions for ECHO alerts and foreground call permissions when a human joins.

To revoke access: disable ECHO in the app and stop the bridge. Revoke its separate session through Supabase account/session controls when required. Removing the bridge's private session file stops future logins on that Mac but does not itself revoke a server-side refresh token. Never commit or export those session files.

## Optional M3 acceleration and installed voices

Use a multilingual whisper.cpp model with a local `whisper-server` built with Metal. Inspect the installed server's `--help` for its supported flags, bind it to loopback (for example port 8080), then set:

```sh
ECHO_WHISPER_CPP_URL=http://127.0.0.1:8080
```

The bridge uses its `/inference` audio-upload API and falls back to the warmed CPU Whisper model after a failure. This adapter is tested with HTTP fixtures; actual Metal/M3 execution is pending access to the Mac.

List installed macOS voices with `say -v '?'`. English defaults to Samantha if available. Set `ECHO_MAC_VOICE_EN` and, only if a Tamil-capable voice is installed, `ECHO_MAC_VOICE_TA`. Names must match the installed voices. A failed system voice falls back to eSpeak. Voice style changes speech rate. Offline eSpeak Tamil/Tanglish is robotic. No natural Tamil voice/model is bundled or downloaded silently. Use Tamil script in personal Tamil/Tanglish greetings for eSpeak pronunciation.

## Optional local fallback for existing chat AI

Voice calls use outbound Supabase signaling and do not require a public HTTP gateway. For the Supabase `us-ai` Edge Function to reach your Mac's Ollama-backed gateway, it needs a reachable **HTTPS** endpoint. Keep Ollama and port 8787 bound to loopback and use a trusted reverse proxy or free HTTPS tunnel. Do not expose Ollama directly.

Generate a gateway key locally with `python -c 'import secrets; print(secrets.token_urlsafe(32))'`. Store it only in the ignored Mac configuration as `ECHO_INFERENCE_KEY` and Supabase Edge Function secrets as `ECHO_INFERENCE_KEY`. Set the HTTPS base URL as the server-only `ECHO_INFERENCE_URL`, and set `ECHO_MODEL` consistently. No URL or gateway key is sent to Flutter. Do not put these values into Git, build-time Dart constants or screenshots.

`POST /v1/chat/completions` requires the gateway key and supports the structured response format the existing chat endpoint uses. `us-ai` tries this local gateway first and then optional Groq, validates output/citations, rechecks live consent, and preserves the existing editable-draft behavior. With no gateway configured, the deployed app keeps its existing Groq path. With neither usable local inference nor cloud quota, chat tools return an explicit error and keep the draft.

## Privacy and recovery

Raw microphone audio is processed in memory. System TTS uses an automatically removed temporary audio file; no caller recording is retained. The bridge is a trusted media endpoint and can hear the call; this is not end-to-end encryption between the two phones while ECHO/relay is in use.

Saving defaults off. Enabling it stores up to 80 bounded transcript entries, a verbatim caller-message recap, and keyword-based important-message flags. Both call participants can read their call record; outsiders cannot. Only the callee can change its bridge record. Call records and dependent ECHO records follow the established call cleanup policy (roughly one day after call creation, subject to the existing cron job running). The callee can erase live transcripts and stop saving, or delete an ended call's ECHO record in history. Database enforcement prevents delayed inference from restoring erased content.

Revoking AI answering stops processing on the next preference check. If STT fails, ECHO asks the caller to send a chat message. If inference fails but the spoken message was saved, ECHO uses a prepared acknowledgement. If saving is disabled or fails, it explicitly says the message could not be saved. AI/gateway health never controls whether the media peer remains connected.

Existing normal calls remain available when the bridge is offline. A simultaneous human Answer and ECHO Answer is arbitrated atomically by the database. A failed takeover releases the phone's new leg while leaving the original caller/bridge leg available.

## Verification commands

```sh
flutter test
flutter analyze --no-fatal-infos
node --test supabase/functions/us-ai/*.test.ts
npx deno check supabase/functions/us-ai/index.ts
python -m unittest discover -s services/echo_bridge/tests -v
```

`python scripts/test_echo_database.py` requires a **fresh, disposable local PostgreSQL** with `psql`; it refuses non-loopback database hosts. CI provisions this automatically. It tests the original call guard plus the additive ECHO schema and mocks only push delivery.

The existing signed Android workflow builds and verifies the existing certificate and tests install/launch on Android 7 and 15. Those smoke tests do not demonstrate a complete two-phone ECHO call, real Google account authorization, media codecs on a physical phone or locked-screen behavior. See `ECHO_VALIDATION.md` for actual results and remaining gates.
