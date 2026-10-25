# ECHO on your Android phone — v1.10 candidate

ECHO can now run the language and speech-recognition models on the phone that receives the Us call. The Mac is optional. Phone mode does not call Groq, Ollama or an AI inference server. Supabase still handles call signaling, permissions and optional transcript storage; calls need internet.

The initial profiles target the supplied devices conservatively:

| Device | Initial pack | Optional upgrade |
| --- | --- | --- |
| Pixel 8, 8 GB RAM | Light | Larger language model after measuring performance |
| Partner's AI+ Ultra 2, 6 GB RAM | Light | Keep Light; larger pack is disabled below the RAM threshold |

The app reads actual Android architecture, RAM, free RAM and storage. It does not assume a chipset from the handset name. Phone inference requires supported 64-bit Android 9+; existing normal app features retain the established Android 7+ minimum. CPU inference is used initially. No Pixel-only Gemini Nano or unsupported NPU capability is assumed.

## Set up each phone once

1. Install the new signed v1.10 candidate over Us using the existing signing identity. Do not uninstall the app or clear its data.
2. Open Profile and settings → ECHO receptionist. Select **This phone · no Mac needed**.
3. Keep the **Light** model pack initially. Tap **Download / resume models**, preferably on Wi-Fi. The light pack is about **557 MB**; the larger pack is about **1.27 GB**, plus Android offline voice data. The app reserves additional free storage and verifies every file before loading it. Interrupted downloads can resume.
4. Choose English, Tamil or Tanglish. Use **Install offline voice data** if Android has no installed offline voice for the chosen language. Tamil/Tanglish need an offline Tamil voice. A network-only voice is rejected.
5. Tap **Prepare and test phone AI**. This checks the installed voice's synthesis output, loads the local speech model and language model, and performs a real short generation. Use **Listen to offline voice** to hear the installed Android voice.
6. Enable ECHO answering, choose manual/delayed/scheduled rules, and **Save ECHO settings**.
7. For locked-screen/background readiness, explicitly enable **Keep ECHO ready in the background** while Us is open and grant call/notification permissions. A persistent notification offers **Stop ECHO**. This uses more battery and keeps the existing Flutter engine/signaling alive.

**AI Answer is disabled until the selected host is ready and answering settings are enabled.** In phone mode it does not show the old “start your Mac” error. Each partner installs their own pack on their own phone.

Previously enabled phone answering warms verified downloaded models when Us opens and the account/couple is ready. A previously requested background-ready service can be resumed from the foreground. Automatic startup after reboot or Android force-stop is not claimed. Android, especially vendor battery management, can stop the process. A force-stopped, powered-off or offline phone cannot answer a new call. Reopen Us and check readiness if Android stopped it.

The larger model is optional. It can improve wording but consumes more RAM and may run more slowly. It does not change the selected Whisper speech model. No latency or Tamil accuracy target is claimed from RAM size alone; measure both real phones before enabling unattended use.

Preparing also synthesizes bounded fixed AI identification and failure replies into memory before accepting calls. Those prepared replies do not depend on a live TTS engine during the call. Voice styles adjust the selected offline voice's pitch and speaking rate; they are not cloned partner voices. Prepare again after changing language or style.

## What happens in a call

- The existing authenticated Us/WebRTC call is answered by the receiving phone after an atomic database claim. A bridge cannot take a call configured for phone hosting.
- ECHO identifies itself as AI audibly. Personal greetings follow that identification.
- Caller audio is received in the native WebRTC processing path, converted to bounded local speech segments, and recognized by offline multilingual Whisper in a worker isolate.
- The local quantized Qwen model streams text into sentence-level Android offline TTS. Generated PCM replaces the microphone's outgoing audio. The phone's microphone is not transmitted while AI is answering. Capturing is explicitly mono so a second microphone channel cannot escape the replacement.
- Caller speech interrupts queued synthesis and cancels pending generation. Late speech chunks from an interrupted generation are discarded.
- **Take over call** switches the same peer/audio track back to the human microphone. It does not create a second call or depend on the Mac bridge.
- Inference and synthesis errors do not close the WebRTC peer. If recognition or saving fails, the caller is directed to Us chat; a saved-message acknowledgement is only used after a successful database write.
- A live transcript can be shown on the receiving phone without saving it. Saving remains off by default. Opting in shares the saved call transcript/recap under existing participant RLS and one-day call retention. Erasing it also clears current local history and stops future saving.

STT uses bounded utterances after a pause (up to 12 seconds), not partial word-by-word streaming. TTS streams by sentence and by the Android engine's audio callbacks. Exact latency, interruption quality and Tamil/Tanglish accuracy require device tests. Existing text-AI tools retain their previously implemented hybrid server routing; this release moves the ECHO call pipeline to the phone.

## Model provenance and storage

- Light: `unsloth/Qwen3-0.6B-GGUF`, Q4_K_M, pinned revision and SHA-256.
- Larger: `unsloth/Qwen3-1.7B-GGUF`, Q4_K_M, pinned revision and SHA-256.
- Speech: multilingual Whisper base int8 ONNX encoder/decoder and tokens from `csukuangfj/sherpa-onnx-whisper-base`, pinned revision and SHA-256.
- Synthesis: an installed Android offline voice, selected by language. No paid voice API or hidden network fallback is added.

Weights live in Us private application storage, survive normal signed updates, and can be removed from ECHO settings. No caller audio recording is retained. Temporary synthesis files are private and deleted. Qwen's upstream model license is Apache 2.0; Whisper's upstream license is MIT; sherpa-onnx is Apache 2.0. Consult the pinned upstream model repositories and dependency license files before redistributing weights. Model files are downloaded explicitly rather than bundled into the APK.

Phone mode does not require an AI subscription or API key and is not subject to an AI provider's free request quota. Battery, storage, memory, internet/data service, existing Supabase/Firebase limits and network/TURN availability still apply. No paid hosting or account upgrade was provisioned.

## Verification status

See [ECHO_PHONE_VALIDATION.md](ECHO_PHONE_VALIDATION.md) and the current PR checks for the signed candidate. A successful build or CPU smoke test is not a two-phone/locked-screen acceptance test.
