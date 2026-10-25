import asyncio
import hashlib
import io
import shutil
import subprocess
import wave
import numpy as np

DISCLOSURE = {
 'English': 'Hello. I am ECHO, an AI assistant, answering for your partner. You are speaking with AI. You can leave a message or ask your partner to take over.',
 'Tamil': 'வணக்கம். நான் எக்கோ, உங்கள் துணையின் செயற்கை நுண்ணறிவு உதவியாளர். நீங்கள் ஏஐ உடன் பேசுகிறீர்கள். ஒரு செய்தியைச் சொல்லலாம்.',
 'Tanglish': 'ஹாய். நான் எக்கோ, உங்க பார்ட்னரோட ஏஐ அசிஸ்டன்ட். நீங்க ஏஐ கூட பேசுறீங்க. உங்க மெசேஜ் சொல்லலாம்.',
}
FALLBACK = {
 'English': 'I cannot reach the conversation service. Please tell me the message you want your partner to receive.',
 'Tamil': 'இப்போது உரையாடல் சேவை கிடைக்கவில்லை. உங்கள் துணைக்கு சொல்ல வேண்டிய செய்தியைச் சொல்லுங்கள்.',
 'Tanglish': 'இப்போ கன்வர்சேஷன் சர்வீஸ் கிடைக்கலை. உங்க பார்ட்னருக்கு சொல்ல வேண்டிய மெசேஜ் சொல்லுங்க.',
}
ACK = {
 'English': 'Thank you. Your message has been saved for your partner.',
 'Tamil': 'நன்றி. உங்கள் செய்தி உங்கள் துணைக்காக சேமிக்கப்பட்டது.',
 'Tanglish': 'தேங்க்ஸ். உங்க மெசேஜ் உங்க பார்ட்னருக்காக சேவ் பண்ணியாச்சு.',
}
NO_STT = {
 'English': 'I could not transcribe that. Please send your partner a message in the Us chat.',
 'Tamil': 'நீங்கள் சொன்னதை எழுத முடியவில்லை. Us அரட்டையில் உங்கள் துணைக்கு செய்தி அனுப்புங்கள்.',
 'Tanglish': 'நீங்க சொன்னதை எழுத முடியலை. Us சாட்டில் உங்க பார்ட்னருக்கு மெசேஜ் அனுப்புங்க.',
}

UNSAVED = {
 'English': 'I heard your message but could not save it. Please send it to your partner in the Us chat.',
 'Tamil': 'உங்கள் செய்தியைக் கேட்டேன். ஆனால் சேமிக்க முடியவில்லை. Us அரட்டையில் உங்கள் துணைக்கு அனுப்புங்கள்.',
 'Tanglish': 'உங்க மெசேஜ் கேட்டேன். ஆனா சேவ் பண்ண முடியலை. Us சாட்டில் உங்க பார்ட்னருக்கு அனுப்புங்க.',
}

class Speech:
    def __init__(self, config):
        self.config = config
        self.model = None
        self.cache = {}
        self.ready = False
        self.stt_lock = asyncio.Lock()

    def synthesize(self, text, language, voice='default'):
        key = hashlib.sha256((language+voice+text).encode()).hexdigest()
        if key in self.cache:
            return self.cache[key]
        speed = {'default':'155','soft':'135','bright':'175'}[voice]
        lang = 'en' if language == 'English' else 'ta'
        # Separate argv and stdin prevent shell/option injection from conversation.
        result = subprocess.run([self.config.tts, '--stdout', '-v', lang, '-s', speed, '--stdin'],
            input=text.encode(), capture_output=True, timeout=25, check=True)
        with wave.open(io.BytesIO(result.stdout)) as wav:
            pcm = np.frombuffer(wav.readframes(wav.getnframes()), dtype='<i2').copy()
            rate = wav.getframerate()
        # eSpeak outputs 22050 Hz; resample off the event loop with ffmpeg.
        if rate != 16000:
            result = subprocess.run(['ffmpeg','-v','error','-f','s16le','-ar',str(rate),'-ac','1','-i','pipe:0',
                '-f','s16le','-ar','16000','-ac','1','pipe:1'], input=pcm.tobytes(), capture_output=True, timeout=10, check=True)
            pcm = np.frombuffer(result.stdout, dtype='<i2').copy()
        if len(self.cache) < 64:
            self.cache[key] = pcm
        return pcm

    async def prepare(self):
        if not shutil.which(self.config.tts) or not shutil.which('ffmpeg'):
            return False
        # A call is never auto-answered without a working audible AI disclosure.
        for language in DISCLOSURE:
            for phrase in (DISCLOSURE, FALLBACK, ACK, NO_STT, UNSAVED):
                await asyncio.to_thread(self.synthesize, phrase[language], language)
        # Download/load the multilingual local model before advertising readiness.
        await self.transcribe(np.zeros(16000, dtype=np.int16), 'English')
        self.ready = True
        return True

    def _transcribe(self, pcm, language):
        if self.model is None:
            from faster_whisper import WhisperModel
            self.model = WhisperModel(self.config.whisper_model, device='cpu', compute_type='int8')
        segments, _ = self.model.transcribe(pcm.astype(np.float32)/32768,
            language='en' if language == 'English' else 'ta', beam_size=3, vad_filter=True,
            condition_on_previous_text=False)
        return ' '.join(s.text.strip() for s in segments).strip()

    async def transcribe(self, pcm, language):
        async with self.stt_lock:
            return await asyncio.to_thread(self._transcribe, pcm, language)
