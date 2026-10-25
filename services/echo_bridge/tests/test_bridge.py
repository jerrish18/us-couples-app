import asyncio
import json
import tempfile
import unittest
from datetime import datetime, timezone, timedelta
from pathlib import Path
from unittest.mock import patch
from types import SimpleNamespace
import httpx
import numpy as np
from aiortc import RTCPeerConnection, RTCSessionDescription, RTCConfiguration
from av import AudioResampler
from services.echo_bridge.calls import should_answer, EchoCall
from services.echo_bridge.inference import Inference
from services.echo_bridge.media import OutputAudio, Utterances
from services.echo_bridge.store import Account


class RulesTests(unittest.TestCase):
    def setUp(self):
        self.now = datetime(2026, 10, 25, 18, 30, tzinfo=timezone.utc)
        self.call = {
            "state": "ringing",
            "video": False,
            "created_at": (self.now - timedelta(seconds=25)).isoformat(),
            "expires_at": (self.now + timedelta(seconds=35)).isoformat(),
        }
        self.prefs = {"enabled": True, "rule": "always", "delay_seconds": 20}

    def test_manual_delay_disabled_expired_and_video(self):
        self.assertTrue(should_answer(self.call, self.prefs, now=self.now))
        self.assertFalse(
            should_answer(self.call, {**self.prefs, "delay_seconds": 30}, now=self.now)
        )
        self.assertTrue(
            should_answer(
                self.call, {**self.prefs, "rule": "manual"}, manual=True, now=self.now
            )
        )
        self.assertFalse(
            should_answer(
                self.call, {**self.prefs, "enabled": False}, manual=True, now=self.now
            )
        )
        self.assertFalse(
            should_answer(
                {**self.call, "video": True}, self.prefs, manual=True, now=self.now
            )
        )
        self.assertFalse(
            should_answer(
                {**self.call, "expires_at": self.now.isoformat()},
                self.prefs,
                now=self.now,
            )
        )

    def test_schedule_wraps_midnight_in_own_timezone(self):
        prefs = {
            **self.prefs,
            "rule": "schedule",
            "timezone": "Asia/Kolkata",
            "start_minute": 22 * 60,
            "end_minute": 7 * 60,
        }
        self.assertTrue(should_answer(self.call, prefs, now=self.now))
        self.assertFalse(
            should_answer(self.call, {**prefs, "timezone": "bad-zone"}, now=self.now)
        )
        self.assertFalse(
            should_answer(
                self.call,
                {**prefs, "start_minute": 60, "end_minute": 120},
                now=self.now,
            )
        )

    def test_barge_in_and_bounded_utterances(self):
        vad = Utterances()
        barge, utterance = vad.feed(np.ones(3200, dtype=np.int16) * 3000)
        self.assertTrue(barge)
        self.assertIsNone(utterance)
        barge, utterance = vad.feed(np.zeros(9600, dtype=np.int16))
        self.assertFalse(barge)
        self.assertEqual(len(utterance), 12800)


class AsyncTests(unittest.IsolatedAsyncioTestCase):
    async def test_silent_media_stays_clocked_when_inference_offline(self):
        track = OutputAudio()
        first = await track.recv()
        second = await track.recv()
        self.assertEqual(first.pts, 0)
        self.assertEqual(second.pts, 320)
        self.assertEqual(second.to_ndarray().max(), 0)
        track.push(np.ones(640, dtype=np.int16))
        track.clear()
        self.assertEqual((await track.recv()).to_ndarray().max(), 0)
        track.stop()

    async def test_rate_limit_switch_preserves_context(self):
        calls = []

        def handler(request):
            calls.append(json.loads(request.content))
            if len(calls) == 1:
                return httpx.Response(429, headers={"retry-after": "120"})
            return httpx.Response(
                200,
                text="data: "
                + json.dumps({"choices": [{"delta": {"content": "வணக்கம்"}}]})
                + "\n\ndata: [DONE]\n",
            )

        config = SimpleNamespace(
            ollama_url="http://local",
            model="local",
            groq_key="test",
            groq_model="cloud",
        )
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as http:
            inference = Inference(config, http)
            context = [{"role": "user", "content": "Same context"}]
            self.assertEqual(await inference.complete(context), "வணக்கம்")
            self.assertEqual(calls[0]["messages"], calls[1]["messages"])
            self.assertGreater(inference.cooldowns["local"], 0)

    async def test_local_gateway_cannot_bypass_edge_cloud_quota(self):
        requests = []

        def handler(request):
            requests.append(str(request.url))
            return httpx.Response(503)

        config = SimpleNamespace(
            ollama_url="http://local",
            model="local",
            groq_key="test",
            groq_model="cloud",
        )
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as http:
            with self.assertRaises(RuntimeError):
                await Inference(config, http).complete([], local_only=True)
        self.assertEqual(len(requests), 1)
        self.assertTrue(requests[0].startswith("http://local"))

    async def test_partial_response_does_not_replay_from_another_provider(self):
        n = 0

        def handler(request):
            nonlocal n
            n += 1
            return httpx.Response(
                200, text='{"message":{"content":"hello"}}\ninvalid json\n'
            )

        config = SimpleNamespace(
            ollama_url="http://local",
            model="local",
            groq_key="test",
            groq_model="cloud",
        )
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as http:
            with self.assertRaises(RuntimeError):
                await Inference(config, http).complete([])
        self.assertEqual(n, 1)

    async def test_credentials_are_private_and_symlinks_rejected(self):
        with tempfile.TemporaryDirectory() as root:
            config = SimpleNamespace(state_dir=Path(root))
            account = Account(config, "test-id", "not-a-real-token", None)
            account.save()
            self.assertEqual(account.path.stat().st_mode & 0o777, 0o600)
            account.path.unlink()
            account.path.symlink_to(Path(root) / "target")
            with self.assertRaises(ValueError):
                account.save()

    async def test_metal_stt_adapter_and_local_cpu_fallback(self):
        from services.echo_bridge.speech import Speech

        config = SimpleNamespace(
            whisper_cpp_url="http://127.0.0.1:8080", whisper_model="small"
        )
        speech = Speech(config)
        response = httpx.Response(
            200,
            json={"text": "நாளை பேசலாம்"},
            request=httpx.Request("POST", "http://127.0.0.1:8080/inference"),
        )
        with patch("services.echo_bridge.speech.httpx.post", return_value=response):
            self.assertEqual(
                speech._transcribe(np.zeros(320, dtype=np.int16), "Tamil"),
                "நாளை பேசலாம்",
            )
        with patch(
            "services.echo_bridge.speech.httpx.post",
            side_effect=httpx.ConnectError("offline"),
        ) as request, patch.object(
            speech, "_cpu_transcribe", return_value="CPU fallback"
        ):
            self.assertEqual(
                speech._transcribe(np.zeros(320, dtype=np.int16), "Tamil"),
                "CPU fallback",
            )
            self.assertEqual(
                speech._transcribe(np.zeros(320, dtype=np.int16), "Tamil"),
                "CPU fallback",
            )
            self.assertEqual(request.call_count, 1)

    async def test_gateway_auth_and_message_validation(self):
        from aiohttp import web
        from aiohttp.test_utils import TestClient, TestServer
        from services.echo_bridge.server import Bridge

        with tempfile.TemporaryDirectory() as folder:
            config = SimpleNamespace(
                state_dir=Path(folder), inference_key="test-only-key"
            )
            bridge = Bridge(config)
            app = web.Application()
            app.router.add_post("/v1/chat/completions", bridge.complete)
            async with TestClient(TestServer(app)) as client:
                response = await client.post(
                    "/v1/chat/completions", json={"messages": []}
                )
                self.assertEqual(response.status, 401)
                response = await client.post(
                    "/v1/chat/completions",
                    headers={"Authorization": "Bearer test-only-key"},
                    json={"messages": [{"role": "admin", "content": "bad"}]},
                )
                self.assertEqual(response.status, 400)
            await bridge.close()

    async def test_real_webrtc_audio_survives_provider_failure_and_human_takeover(self):
        """Real aiortc peers/codecs. No external API, audio device or mocked RTP."""
        caller = RTCPeerConnection(RTCConfiguration(iceServers=[]))
        human = RTCPeerConnection(RTCConfiguration(iceServers=[]))
        outgoing = OutputAudio()
        outgoing.push(np.ones(16000, dtype=np.int16) * 2000)
        caller.addTrack(outgoing)
        offer = await caller.createOffer()
        await caller.setLocalDescription(offer)
        tracks, human_tracks = [], []

        def tone(hz):
            return (np.sin(np.arange(16000) * 2 * np.pi * hz / 16000) * 8000).astype(
                np.int16
            )

        async def detect(track, hz):
            resample = AudioResampler(format="s16", layout="mono", rate=16000)
            async with asyncio.timeout(5):
                while True:
                    for audio in resample.resample(await track.recv()):
                        pcm = audio.to_ndarray().reshape(-1).astype(np.float32)
                        if np.sqrt(np.mean(pcm**2)) < 200:
                            continue
                        frequencies = np.fft.rfftfreq(len(pcm), 1 / 16000)
                        peak = frequencies[np.argmax(np.abs(np.fft.rfft(pcm)))]
                        if abs(peak - hz) < 80:
                            return

        @human.on("track")
        def human_receive(track):
            human_tracks.append(track)

        @caller.on("track")
        def receive(track):
            tracks.append(track)

        class FakeAccount:
            uid = "callee"
            patches = []

            async def ice(self):
                return []

            async def request(self, *args, **kwargs):
                return True

            async def patch(self, *args, **kwargs):
                self.patches.append((args, kwargs))
                return [args[1]]

        class OfflineInference:
            async def stream(self, *args):
                raise RuntimeError("offline")
                yield ""

        class LocalSpeech:
            cache = {}

            def synthesize(self, *args):
                return tone(1200)[:8000]

            async def transcribe(self, *args):
                return "Please call me tomorrow"

        account = FakeAccount()
        row = {
            "id": "call",
            "offer": caller.localDescription.sdp,
            "callee_id": "callee",
            "caller_id": "caller",
            "couple_id": "couple",
        }
        call = EchoCall(
            account,
            row,
            {"language": "English", "retain_transcript": True},
            LocalSpeech(),
            OfflineInference(),
        )

        # The database monitor is tested separately; transport has local peers here.
        async def monitor():
            await asyncio.Event().wait()

        call.monitor = monitor
        try:
            self.assertTrue(await call.answer())
            await caller.setRemoteDescription(
                RTCSessionDescription(call.peer.localDescription.sdp, "answer")
            )
            async with asyncio.timeout(8):
                while caller.connectionState != "connected" or not call.disclosed:
                    await asyncio.sleep(0.05)
                frame = await tracks[0].recv()
            self.assertGreater(frame.samples, 0)
            await call.respond(np.ones(16000, dtype=np.int16))
            self.assertEqual(caller.connectionState, "connected")
            self.assertTrue(any(m["role"] == "caller" for m in call.transcript))
            human_audio = OutputAudio()
            human.addTrack(human_audio)
            await human.setLocalDescription(await human.createOffer())
            original = call.peer
            await call.takeover(human.localDescription.sdp)
            await human.setRemoteDescription(
                RTCSessionDescription(call.human_peer.localDescription.sdp, "answer")
            )
            async with asyncio.timeout(8):
                while not call.human:
                    await asyncio.sleep(0.05)
            # Verify distinct audio tones traverse both relay directions over
            # real Opus/RTP, rather than merely checking a connected flag.
            outgoing.push(tone(400))
            human_audio.push(tone(800))
            await asyncio.gather(detect(tracks[0], 800), detect(human_tracks[0], 400))
            self.assertIs(call.peer, original)
            self.assertEqual(caller.connectionState, "connected")
            self.assertEqual(human.connectionState, "connected")
            self.assertTrue(
                any(args[1].get("state") == "human" for args, _ in account.patches)
            )
        finally:
            await call.close()
            await caller.close()
            await human.close()


if __name__ == "__main__":
    unittest.main()
