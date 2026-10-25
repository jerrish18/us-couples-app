import os
import sys
from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class Config:
    supabase_url: str = field(
        default_factory=lambda: os.environ["SUPABASE_URL"].rstrip("/")
    )
    supabase_key: str = field(default_factory=lambda: os.environ["SUPABASE_KEY"])
    inference_key: str = field(
        default_factory=lambda: os.environ.get("ECHO_INFERENCE_KEY", "")
    )
    state_dir: Path = field(
        default_factory=lambda: Path(
            os.environ.get("ECHO_STATE_DIR", "private-echo-state")
        )
    )
    ollama_url: str = field(
        default_factory=lambda: os.environ.get(
            "OLLAMA_URL", "http://127.0.0.1:11434"
        ).rstrip("/")
    )
    model: str = field(default_factory=lambda: os.environ.get("ECHO_MODEL", "qwen3:4b"))
    groq_key: str = field(default_factory=lambda: os.environ.get("GROQ_API_KEY", ""))
    groq_model: str = field(
        default_factory=lambda: os.environ.get("GROQ_MODEL", "openai/gpt-oss-120b")
    )
    whisper_model: str = field(
        default_factory=lambda: os.environ.get("ECHO_WHISPER_MODEL", "small")
    )
    tts: str = field(default_factory=lambda: os.environ.get("ECHO_TTS", "espeak-ng"))
    whisper_cpp_url: str = field(
        default_factory=lambda: os.environ.get("ECHO_WHISPER_CPP_URL", "").rstrip("/")
    )
    mac_voice_en: str = field(
        default_factory=lambda: os.environ.get("ECHO_MAC_VOICE_EN")
        or ("Samantha" if sys.platform == "darwin" else "")
    )
    mac_voice_ta: str = field(
        default_factory=lambda: os.environ.get("ECHO_MAC_VOICE_TA", "")
    )
