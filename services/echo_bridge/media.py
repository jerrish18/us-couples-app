import asyncio
import time
from collections import deque
from fractions import Fraction
import numpy as np
from av import AudioFrame, AudioResampler
from aiortc import AudioStreamTrack

class OutputAudio(AudioStreamTrack):
    """A clocked track survives empty speech queues and failed inference."""
    def __init__(self):
        super().__init__()
        self.frames = deque(maxlen=1600)
        self.samples = 0
        self.started = None

    def clear(self):
        self.frames.clear()

    def push(self, pcm):
        for start in range(0, len(pcm), 320):
            chunk = np.zeros(320, dtype=np.int16)
            part = pcm[start:start+320]
            chunk[:len(part)] = part
            self.frames.append(chunk)

    async def recv(self):
        if self.started is None:
            self.started = time.monotonic()
        await asyncio.sleep(max(0, self.started+self.samples/16000-time.monotonic()))
        pcm = self.frames.popleft() if self.frames else np.zeros(320,dtype=np.int16)
        frame = AudioFrame.from_ndarray(pcm.reshape(1,-1),format='s16',layout='mono')
        frame.sample_rate = 16000
        frame.pts = self.samples
        frame.time_base = Fraction(1,16000)
        self.samples += 320
        return frame

class Utterances:
    """Bounded VAD segmentation with early barge-in and silence detection."""
    def __init__(self, threshold=450):
        self.threshold = threshold
        self.parts = []
        self.voiced = 0
        self.silence = 0
        self.total = 0
        self.interrupted = False

    def feed(self, pcm):
        loud = float(np.sqrt(np.mean(pcm.astype(np.float32)**2))) > self.threshold
        if loud:
            self.voiced += len(pcm)
            self.silence = 0
        elif self.voiced:
            self.silence += len(pcm)
        if self.voiced:
            self.parts.append(pcm)
            self.total += len(pcm)
        barge = self.voiced >= 3200 and not self.interrupted
        self.interrupted |= barge
        result = None
        if self.total >= 12*16000 or self.silence >= 9600:
            if self.voiced >= 3200:
                result = np.concatenate(self.parts)
            self.parts, self.voiced, self.silence, self.total, self.interrupted = [],0,0,0,False
        return barge, result

async def consume(track, callback):
    resampler = AudioResampler(format='s16',layout='mono',rate=16000)
    while True:
        frame = await track.recv()
        for audio in resampler.resample(frame):
            await callback(audio.to_ndarray().reshape(-1).copy())
