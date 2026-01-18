#!/usr/bin/env python3
"""
Web UI for comparing transcription results side-by-side.
Supports: OpenAI (Whisper, GPT-4o), AssemblyAI, Google Gemini
"""

import os
import json
import time
import hashlib
import requests
import base64
import sqlite3
import subprocess
from pathlib import Path
from datetime import datetime
from flask import Flask, render_template_string, request, jsonify, send_file
from openai import OpenAI
from dotenv import load_dotenv

# Load .env file
load_dotenv()

app = Flask(__name__)

# Audio files directories
AUDIO_DIR = Path(os.path.expanduser("~/Library/Application Support/audio"))
MEETING_RECORDER_DB = Path(os.path.expanduser("~/Library/Application Support/MeetingRecorder/database.sqlite"))
RESULTS_DIR = Path(__file__).parent / "results"
CACHE_DIR = Path(__file__).parent / ".cache"
RESULTS_DIR.mkdir(exist_ok=True)
CACHE_DIR.mkdir(exist_ok=True)


def get_cache_key(audio_path: str, model: str, language: str, prompt: str) -> str:
    """Generate a cache key based on inputs"""
    # Include file modification time to invalidate cache if file changes
    try:
        mtime = str(Path(audio_path).stat().st_mtime)
    except:
        mtime = ""

    key_data = f"{audio_path}|{mtime}|{model}|{language or ''}|{prompt or ''}"
    return hashlib.sha256(key_data.encode()).hexdigest()[:16]


def get_cached_result(cache_key: str):  # Returns dict or None
    """Get cached result if it exists"""
    cache_file = CACHE_DIR / f"{cache_key}.json"
    if cache_file.exists():
        try:
            with open(cache_file, "r", encoding="utf-8") as f:
                result = json.load(f)
                result["_cached"] = True
                return result
        except:
            pass
    return None


def save_to_cache(cache_key: str, result: dict):
    """Save result to cache"""
    cache_file = CACHE_DIR / f"{cache_key}.json"
    try:
        with open(cache_file, "w", encoding="utf-8") as f:
            json.dump(result, f, indent=2, ensure_ascii=False)
    except Exception as e:
        print(f"Failed to cache result: {e}")


def get_audio_duration(file_path: str) -> float:
    """Get audio duration using ffprobe"""
    try:
        result = subprocess.run(
            ["ffprobe", "-v", "error", "-show_entries", "format=duration",
             "-of", "default=noprint_wrappers=1:nokey=1", file_path],
            capture_output=True, text=True, timeout=10
        )
        return float(result.stdout.strip())
    except:
        return 0.0


def format_duration(seconds: float) -> str:
    """Format duration as human readable string"""
    if seconds <= 0:
        return "?"
    if seconds < 60:
        return f"{int(seconds)}s"
    elif seconds < 3600:
        mins = int(seconds / 60)
        secs = int(seconds % 60)
        return f"{mins}m{secs:02d}s"
    else:
        hours = int(seconds / 3600)
        mins = int((seconds % 3600) / 60)
        return f"{hours}h{mins:02d}m"


def get_meetings_from_db() -> list:
    """Get meetings with audio files from MeetingRecorder database"""
    if not MEETING_RECORDER_DB.exists():
        return []

    try:
        conn = sqlite3.connect(str(MEETING_RECORDER_DB))
        cursor = conn.cursor()
        cursor.execute("""
            SELECT title, audio_path, duration, status
            FROM meetings
            WHERE audio_path IS NOT NULL AND audio_path != ''
            ORDER BY start_time DESC
            LIMIT 50
        """)
        rows = cursor.fetchall()
        conn.close()

        meetings = []
        for title, audio_path, duration, status in rows:
            if audio_path and Path(audio_path).exists():
                size_bytes = Path(audio_path).stat().st_size
                size_mb = size_bytes / (1024 * 1024)

                if not duration or duration <= 0:
                    duration = get_audio_duration(audio_path)

                meetings.append({
                    "path": audio_path,
                    "name": title or Path(audio_path).stem,
                    "duration": duration,
                    "duration_str": format_duration(duration),
                    "size": f"{size_mb:.1f}MB" if size_mb >= 1 else f"{size_bytes/1024:.0f}KB",
                    "status": status,
                    "source": "MeetingRecorder"
                })

        return meetings
    except Exception as e:
        print(f"Error reading database: {e}")
        return []


def get_available_apis():
    return {
        "openai": bool(os.environ.get("OPENAI_API_KEY")),
        "assemblyai": bool(os.environ.get("ASSEMBLYAI_API_KEY")),
        "gemini": bool(os.environ.get("GEMINI_API_KEY")),
    }


MODELS = {
    "whisper-1": {"name": "Whisper v2", "provider": "openai", "supports_prompt": True, "supports_diarization": False, "cost_per_min": 0.006},
    "gpt-4o-mini-transcribe": {"name": "GPT-4o Mini", "provider": "openai", "supports_prompt": True, "supports_diarization": False, "cost_per_min": 0.003},
    "gpt-4o-transcribe": {"name": "GPT-4o Transcribe", "provider": "openai", "supports_prompt": True, "supports_diarization": False, "cost_per_min": 0.006},
    "gpt-4o-transcribe-diarize": {"name": "GPT-4o + Diarize", "provider": "openai", "supports_prompt": False, "supports_diarization": True, "cost_per_min": 0.006},
    "assemblyai-best": {"name": "AssemblyAI Best", "provider": "assemblyai", "supports_prompt": False, "supports_diarization": True, "cost_per_min": 0.00283},
    # Gemini Flash models - prices calculated from audio token rates (25 tokens/sec = 1500 tokens/min)
    # Input cost = audio_input_per_1M * 1500 / 1M
    # Output cost ≈ 300 text tokens/min * output_per_1M / 1M (transcription text is small)
    "gemini-2.0-flash": {"name": "Gemini 2.0 Flash", "provider": "gemini", "supports_prompt": True, "supports_diarization": True, "cost_per_min": 0.0011},  # $0.70 audio + $0.40 out
    "gemini-2.5-flash-lite": {"name": "Gemini 2.5 Flash-Lite", "provider": "gemini", "supports_prompt": True, "supports_diarization": True, "cost_per_min": 0.0005},  # $0.30 audio + $0.40 out
    "gemini-2.5-flash": {"name": "Gemini 2.5 Flash", "provider": "gemini", "supports_prompt": True, "supports_diarization": True, "cost_per_min": 0.0016},  # $1.00 audio + $2.50 out
    "gemini-3-flash": {"name": "Gemini 3 Flash", "provider": "gemini", "supports_prompt": True, "supports_diarization": True, "cost_per_min": 0.0016},  # $1.00 audio + $3.00 out
}

# Per-model prompt templates
# {language} and {user_context} are replaced at runtime
MODEL_PROMPTS = {
    # Whisper supports simple vocabulary hints
    "whisper-1": """{user_context}""",

    # GPT-4o models - simple context
    "gpt-4o-mini-transcribe": """{user_context}""",
    "gpt-4o-transcribe": """{user_context}""",

    # GPT-4o diarize - no prompt support
    "gpt-4o-transcribe-diarize": None,

    # AssemblyAI - no prompt support (uses language_code)
    "assemblyai-best": None,

    # Gemini - detailed diarization instructions
    "gemini-2.0-flash": """Transcribe this audio in {language} with speaker diarization and timestamps.

CRITICAL RULES:
1. Identify speakers by their voice characteristics. Label them as Speaker A, Speaker B, Speaker C, etc.
2. IMPORTANT: Keep the SAME speaker label for consecutive speech from the same person. Do NOT create a new segment every sentence - group continuous speech from one speaker into ONE segment.
3. Only create a new segment when the speaker CHANGES.
4. Include timestamps in MM:SS format for each segment.

OUTPUT FORMAT (follow exactly):
[Speaker A, 0:00] First speaker's complete statement or paragraph here, including all sentences until another speaker talks.

[Speaker B, 0:45] Second speaker's complete response here.

[Speaker A, 1:23] First speaker talking again.

WRONG (don't do this):
[Speaker A, 0:00] First sentence.
[Speaker A, 0:05] Second sentence from same person.
[Speaker A, 0:10] Third sentence from same person.

RIGHT (do this instead):
[Speaker A, 0:00] First sentence. Second sentence from same person. Third sentence from same person.

{user_context}

Now transcribe the audio with proper speaker grouping and timestamps:""",

    "gemini-2.5-flash": """Transcribe this audio in {language} with speaker diarization and timestamps.

RULES:
1. Label speakers as Speaker A, Speaker B, etc. based on voice.
2. Group consecutive speech from the same speaker into ONE segment.
3. Only start a new segment when the speaker CHANGES.
4. Include timestamp (MM:SS) at the start of each segment.

FORMAT:
[Speaker A, 0:00] Complete speech until next speaker.
[Speaker B, 1:15] Next speaker's complete response.

{user_context}

Transcribe now:""",

    "gemini-2.5-flash-lite": """Transcribe this audio in {language} with speaker diarization and timestamps.

RULES:
1. Label speakers as Speaker A, Speaker B, etc. based on voice.
2. Group consecutive speech from the same speaker into ONE segment.
3. Only start a new segment when the speaker CHANGES.
4. Include timestamp (MM:SS) at the start of each segment.

FORMAT:
[Speaker A, 0:00] Complete speech until next speaker.
[Speaker B, 1:15] Next speaker's complete response.

{user_context}

Transcribe now:""",

    "gemini-3-flash": """Transcribe this audio in {language} with speaker diarization and timestamps.

RULES:
1. Label speakers as Speaker A, Speaker B, etc. based on voice.
2. Group consecutive speech from the same speaker into ONE segment.
3. Only start a new segment when the speaker CHANGES.
4. Include timestamp (MM:SS) at the start of each segment.

FORMAT:
[Speaker A, 0:00] Complete speech until next speaker.
[Speaker B, 1:15] Next speaker's complete response.

{user_context}

Transcribe now:""",

}

# Default user context (editable in UI)
DEFAULT_USER_CONTEXT = """Reunião de trabalho em português brasileiro.
Nomes: Nelson Williams, Rosenthal, Viseu da Paula, Igão.
Termos: API, frontend, backend, views, queries, planilhas, banco de dados."""


def get_prompt_for_model(model: str, language: str, user_context: str = None):
    """Get the formatted prompt for a specific model"""
    template = MODEL_PROMPTS.get(model)
    if template is None:
        return None

    lang_names = {"pt": "Portuguese", "en": "English", "es": "Spanish"}
    lang_str = lang_names.get(language, language) if language else "the detected language"

    return template.format(
        language=lang_str,
        user_context=user_context or ""
    ).strip()


# ============== Transcription Functions ==============

def compress_audio_for_openai(audio_path: str, target_mb: float = 24) -> str:
    """Compress audio to fit OpenAI's 25MB limit using ffmpeg"""
    import tempfile

    file_size_mb = Path(audio_path).stat().st_size / (1024 * 1024)
    if file_size_mb <= target_mb:
        return audio_path

    # Get duration
    duration = get_audio_duration(audio_path)
    if duration <= 0:
        raise ValueError("Could not determine audio duration for compression")

    # Calculate target bitrate to achieve target size
    # target_mb * 8 (bits per byte) * 1024 (kb) / duration (seconds) = kbps
    target_kbps = int((target_mb * 8 * 1024) / duration)
    # Minimum reasonable bitrate for speech is ~32kbps
    target_kbps = max(32, min(target_kbps, 128))

    # Create temp file
    temp_dir = Path(tempfile.gettempdir()) / "benchmark_compressed"
    temp_dir.mkdir(exist_ok=True)
    compressed_path = temp_dir / f"compressed_{Path(audio_path).stem}.m4a"

    # Compress with ffmpeg
    cmd = [
        "ffmpeg", "-y", "-i", audio_path,
        "-ac", "1",  # mono
        "-ar", "16000",  # 16kHz sample rate (good for speech)
        "-b:a", f"{target_kbps}k",
        "-acodec", "aac",
        str(compressed_path)
    ]

    result = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    if result.returncode != 0:
        raise ValueError(f"Compression failed: {result.stderr[:200]}")

    new_size_mb = compressed_path.stat().st_size / (1024 * 1024)
    print(f"[Compression] {file_size_mb:.1f}MB -> {new_size_mb:.1f}MB ({target_kbps}kbps)")

    return str(compressed_path)


def transcribe_openai(audio_path: str, model: str, language: str = None, user_context: str = None) -> dict:
    client = OpenAI()
    model_info = MODELS.get(model, {})
    start_time = time.time()

    # Check file size and compress if needed (25MB limit)
    file_size_mb = Path(audio_path).stat().st_size / (1024 * 1024)
    original_path = audio_path
    if file_size_mb > 25:
        try:
            audio_path = compress_audio_for_openai(audio_path)
            file_size_mb = Path(audio_path).stat().st_size / (1024 * 1024)
            if file_size_mb > 25:
                raise ValueError(f"Still too large after compression ({file_size_mb:.1f}MB)")
        except Exception as e:
            raise ValueError(f"File too large ({file_size_mb:.1f}MB) and compression failed: {e}")

    # Check duration limit for diarize model (1400 seconds max)
    if model == "gpt-4o-transcribe-diarize":
        duration = get_audio_duration(original_path)
        if duration > 1400:
            raise ValueError(f"Audio too long for diarize model ({int(duration/60)}min). Limit is 23min. Use AssemblyAI or Gemini for diarization.")

    # Get model-specific prompt
    prompt = get_prompt_for_model(model, language, user_context)

    with open(audio_path, "rb") as audio_file:
        kwargs = {"file": audio_file, "model": model}

        if model == "whisper-1":
            kwargs["response_format"] = "verbose_json"
            if prompt:
                kwargs["prompt"] = prompt
        elif model == "gpt-4o-transcribe-diarize":
            # Diarize model requires diarized_json format
            kwargs["response_format"] = "diarized_json"
            kwargs["chunking_strategy"] = "auto"
        else:
            # gpt-4o-transcribe and gpt-4o-mini-transcribe only support json/text
            kwargs["response_format"] = "json"

        if language:
            kwargs["language"] = language

        response = client.audio.transcriptions.create(**kwargs)

    latency = time.time() - start_time

    if hasattr(response, 'text'):
        text = response.text
    elif isinstance(response, dict):
        text = response.get('text', str(response))
    else:
        text = str(response)

    result = {
        "model": model,
        "model_name": model_info.get("name", model),
        "provider": "openai",
        "text": text,
        "latency_seconds": round(latency, 2),
        "prompt_used": prompt if model == "whisper-1" else None,
        "language_hint": language,
    }

    if hasattr(response, 'duration'):
        result["duration_seconds"] = response.duration
        result["estimated_cost_cents"] = round(response.duration / 60 * model_info.get("cost_per_min", 0.006) * 100, 2)

    if hasattr(response, 'segments'):
        result["segments"] = [
            {"speaker": getattr(seg, 'speaker', None), "start": seg.start, "end": seg.end, "text": seg.text}
            for seg in response.segments
        ]

    return result


def transcribe_assemblyai(audio_path: str, language: str = None) -> dict:
    api_key = os.environ.get("ASSEMBLYAI_API_KEY")
    if not api_key:
        raise ValueError("ASSEMBLYAI_API_KEY not set")

    headers = {"authorization": api_key}
    start_time = time.time()

    with open(audio_path, "rb") as f:
        upload_response = requests.post("https://api.assemblyai.com/v2/upload", headers=headers, data=f)
    upload_url = upload_response.json()["upload_url"]

    transcript_request = {"audio_url": upload_url, "speaker_labels": True}
    if language:
        transcript_request["language_code"] = language

    transcript_response = requests.post("https://api.assemblyai.com/v2/transcript", headers=headers, json=transcript_request)
    transcript_id = transcript_response.json()["id"]

    while True:
        poll_response = requests.get(f"https://api.assemblyai.com/v2/transcript/{transcript_id}", headers=headers)
        status = poll_response.json()["status"]
        if status == "completed":
            break
        elif status == "error":
            raise ValueError(f"AssemblyAI error: {poll_response.json().get('error')}")
        time.sleep(2)

    result_data = poll_response.json()
    latency = time.time() - start_time

    segments = []
    if "utterances" in result_data:
        for utt in result_data["utterances"]:
            segments.append({
                "speaker": f"Speaker {utt['speaker']}",
                "start": utt["start"] / 1000,
                "end": utt["end"] / 1000,
                "text": utt["text"]
            })

    duration = result_data.get("audio_duration", 0)

    return {
        "model": "assemblyai-best",
        "model_name": "AssemblyAI Best",
        "provider": "assemblyai",
        "text": result_data.get("text", ""),
        "latency_seconds": round(latency, 2),
        "duration_seconds": duration,
        "estimated_cost_cents": round(duration / 60 * 0.283, 2),
        "segments": segments,
        "language_hint": language,
        "confidence": result_data.get("confidence"),
    }


def transcribe_gemini(audio_path: str, model: str = "gemini-2.0-flash", language: str = None, user_context: str = None) -> dict:
    api_key = os.environ.get("GEMINI_API_KEY")
    if not api_key:
        raise ValueError("GEMINI_API_KEY not set")

    model_info = MODELS.get(model, {})
    start_time = time.time()
    audio_duration = get_audio_duration(audio_path)

    with open(audio_path, "rb") as f:
        audio_data = base64.b64encode(f.read()).decode("utf-8")

    ext = Path(audio_path).suffix.lower()
    mime_types = {".m4a": "audio/mp4", ".mp3": "audio/mpeg", ".wav": "audio/wav", ".webm": "audio/webm"}
    mime_type = mime_types.get(ext, "audio/mp4")

    # Get model-specific prompt
    prompt = get_prompt_for_model(model, language, user_context)

    # Use current model names - see https://ai.google.dev/gemini-api/docs/models
    model_api_map = {
        "gemini-2.0-flash": "gemini-2.0-flash",
        "gemini-2.5-flash-lite": "gemini-2.5-flash-lite",
        "gemini-2.5-flash": "gemini-2.5-flash",
        "gemini-3-flash": "gemini-3-flash-preview",  # Preview model name
    }
    api_model = model_api_map.get(model, "gemini-2.0-flash")

    url = f"https://generativelanguage.googleapis.com/v1beta/models/{api_model}:generateContent?key={api_key}"

    # Use max output tokens - no artificial limits
    # Gemini Flash models support up to 65k output tokens
    max_tokens = 65536

    payload = {
        "contents": [{"parts": [{"text": prompt}, {"inline_data": {"mime_type": mime_type, "data": audio_data}}]}],
        "generationConfig": {"temperature": 0.1, "maxOutputTokens": max_tokens}
    }

    response = requests.post(url, json=payload, timeout=600)  # 10 min timeout for long audio
    response.raise_for_status()
    result = response.json()

    latency = time.time() - start_time

    text = ""
    if "candidates" in result and result["candidates"]:
        parts = result["candidates"][0].get("content", {}).get("parts", [])
        text = " ".join(p.get("text", "") for p in parts)

    segments = parse_gemini_diarization(text.strip())

    # Extract actual token usage from API response
    usage = result.get("usageMetadata", {})
    input_tokens = usage.get("promptTokenCount", 0)
    output_tokens = usage.get("candidatesTokenCount", 0)
    total_tokens = usage.get("totalTokenCount", 0)

    # Calculate actual cost from token usage
    # Pricing per 1M tokens (from https://ai.google.dev/gemini-api/docs/pricing)
    GEMINI_PRICING = {
        "gemini-2.0-flash": {"audio_input": 0.70, "output": 0.40},
        "gemini-2.5-flash-lite": {"audio_input": 0.30, "output": 0.40},
        "gemini-2.5-flash": {"audio_input": 1.00, "output": 2.50},
        "gemini-3-flash": {"audio_input": 1.00, "output": 3.00},
    }
    pricing = GEMINI_PRICING.get(model, {"audio_input": 1.00, "output": 2.50})

    # Cost in dollars: (tokens / 1M) * price_per_1M
    input_cost = (input_tokens / 1_000_000) * pricing["audio_input"]
    output_cost = (output_tokens / 1_000_000) * pricing["output"]
    total_cost_dollars = input_cost + output_cost
    cost_cents = round(total_cost_dollars * 100, 4)

    return {
        "model": model,
        "model_name": model_info.get("name", model),
        "provider": "gemini",
        "text": text.strip(),
        "latency_seconds": round(latency, 2),
        "duration_seconds": audio_duration,
        "estimated_cost_cents": cost_cents,
        "actual_cost": True,  # Flag that this is real cost from API
        "tokens": {
            "input": input_tokens,
            "output": output_tokens,
            "total": total_tokens,
        },
        "prompt_used": (prompt[:200] + "...") if prompt else None,
        "language_hint": language,
        "segments": segments if segments else None,
    }


def parse_gemini_diarization(text: str) -> list:
    import re
    segments = []

    # Patterns to match speaker labels with optional timestamps
    # Order matters - more specific patterns first
    patterns = [
        r'\[Speaker\s+([A-Z]),?\s*(\d{1,2}:\d{2}(?::\d{2})?)\]',  # [Speaker A, 0:00] or [Speaker A, 1:23:45]
        r'\*\*Speaker\s+([A-Z])\s*\((\d{1,2}:\d{2}(?::\d{2})?)\):\*\*',  # **Speaker A (0:00):**
        r'Speaker\s+([A-Z])\s*\((\d{1,2}:\d{2}(?::\d{2})?)\):',  # Speaker A (0:00):
        r'\[Speaker\s+([A-Z])\]',  # [Speaker A]
        r'\*\*Speaker\s+([A-Z]):\*\*',  # **Speaker A:**
        r'Speaker\s+([A-Z]):',  # Speaker A:
    ]

    lines = text.split('\n')
    current_speaker = None
    current_text = []
    current_time = None

    for line in lines:
        line = line.strip()
        if not line:
            continue

        speaker_found = None
        time_found = None

        for pattern in patterns:
            match = re.search(pattern, line)
            if match:
                speaker_found = f"Speaker {match.group(1)}"
                if len(match.groups()) > 1 and match.group(2):
                    time_found = match.group(2)
                line = re.sub(pattern, '', line).strip()
                break

        if speaker_found:
            # Save previous speaker's segment
            if current_speaker and current_text:
                segments.append({
                    "speaker": current_speaker,
                    "text": ' '.join(current_text).strip(),
                    "start": parse_timestamp(current_time),
                    "end": None
                })
            current_speaker = speaker_found
            current_time = time_found
            current_text = [line] if line else []
        elif current_speaker:
            # Continue adding to current speaker's text
            current_text.append(line)

    # Don't forget the last segment
    if current_speaker and current_text:
        segments.append({
            "speaker": current_speaker,
            "text": ' '.join(current_text).strip(),
            "start": parse_timestamp(current_time),
            "end": None
        })

    # Post-process: merge consecutive segments from same speaker (in case model still splits them)
    merged_segments = []
    for seg in segments:
        if merged_segments and merged_segments[-1]["speaker"] == seg["speaker"]:
            # Same speaker - merge text
            merged_segments[-1]["text"] += " " + seg["text"]
            # Keep the original start time, don't update end
        else:
            merged_segments.append(seg)

    # Calculate end times based on next segment's start
    for i, seg in enumerate(merged_segments):
        if i + 1 < len(merged_segments) and merged_segments[i + 1]["start"] is not None:
            seg["end"] = merged_segments[i + 1]["start"]

    return merged_segments


def parse_timestamp(ts: str):  # Returns float or None
    """Parse timestamp string like '0:00' or '1:23:45' to seconds"""
    if not ts:
        return None
    try:
        parts = ts.split(':')
        if len(parts) == 2:
            return int(parts[0]) * 60 + int(parts[1])
        elif len(parts) == 3:
            return int(parts[0]) * 3600 + int(parts[1]) * 60 + int(parts[2])
    except:
        pass
    return None


# ============== Flask Routes ==============

HTML_TEMPLATE = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Transcription Benchmark</title>
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: #0a0a0a;
            color: #e0e0e0;
            min-height: 100vh;
            padding: 20px;
        }
        h1 { color: #fff; margin-bottom: 20px; font-weight: 500; }
        h2 { color: #888; font-size: 14px; font-weight: 500; margin-bottom: 10px; text-transform: uppercase; letter-spacing: 0.5px; }

        .container { max-width: 1800px; margin: 0 auto; }

        .api-status {
            display: flex;
            gap: 16px;
            margin-bottom: 20px;
            font-size: 13px;
        }
        .api-status span { display: flex; align-items: center; gap: 6px; }
        .api-status .dot { width: 8px; height: 8px; border-radius: 50%; }
        .api-status .dot.active { background: #10b981; }
        .api-status .dot.inactive { background: #4a4a4a; }

        .controls {
            background: #1a1a1a;
            border-radius: 12px;
            padding: 20px;
            margin-bottom: 20px;
        }
        .controls-row {
            display: flex;
            gap: 20px;
            flex-wrap: wrap;
            align-items: end;
            margin-bottom: 16px;
        }
        .controls-row:last-child { margin-bottom: 0; }

        .control-group { display: flex; flex-direction: column; gap: 8px; }
        .control-group label { font-size: 12px; color: #888; text-transform: uppercase; letter-spacing: 0.5px; }
        .control-group.flex-1 { flex: 1; }

        select, input, textarea {
            background: #2a2a2a;
            border: 1px solid #3a3a3a;
            border-radius: 8px;
            padding: 10px 14px;
            color: #fff;
            font-size: 14px;
            min-width: 200px;
        }
        select:focus, input:focus, textarea:focus { outline: none; border-color: #7c3aed; }
        textarea { min-height: 80px; resize: vertical; font-family: inherit; width: 100%; }

        .model-checkboxes { display: flex; gap: 8px; flex-wrap: wrap; }
        .model-checkbox {
            display: flex;
            align-items: center;
            gap: 6px;
            background: #2a2a2a;
            padding: 8px 12px;
            border-radius: 8px;
            cursor: pointer;
            border: 2px solid transparent;
            transition: all 0.2s;
            font-size: 13px;
        }
        .model-checkbox:hover { background: #3a3a3a; }
        .model-checkbox.selected { border-color: #7c3aed; background: rgba(124, 58, 237, 0.15); }
        .model-checkbox.disabled { opacity: 0.4; cursor: not-allowed; }
        .model-checkbox .check {
            width: 16px; height: 16px;
            border: 2px solid #4a4a4a;
            border-radius: 4px;
            display: flex; align-items: center; justify-content: center;
            font-size: 10px;
        }
        .model-checkbox.selected .check { background: #7c3aed; border-color: #7c3aed; }
        .model-checkbox.selected .check::after { content: '✓'; color: white; }
        .model-info { font-size: 10px; color: #666; }
        .model-info.diarize { color: #7c3aed; }
        .provider-tag { font-size: 9px; padding: 2px 5px; border-radius: 3px; }
        .provider-openai { background: #1a1a2e; color: #10b981; }
        .provider-assemblyai { background: #1a2e1a; color: #3b82f6; }
        .provider-gemini { background: #2e1a1a; color: #f59e0b; }

        button {
            background: #7c3aed;
            color: white;
            border: none;
            border-radius: 8px;
            padding: 12px 24px;
            font-size: 14px;
            font-weight: 500;
            cursor: pointer;
            transition: all 0.2s;
        }
        button:hover { background: #6d28d9; }
        button:disabled { background: #4a4a4a; cursor: not-allowed; }
        button.secondary { background: #3a3a3a; }
        button.secondary:hover { background: #4a4a4a; }

        .audio-player { background: #1a1a1a; border-radius: 12px; padding: 16px; margin-bottom: 20px; }
        audio { width: 100%; height: 40px; }

        .results-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(500px, 1fr));
            gap: 20px;
        }

        .result-card {
            background: #1a1a1a;
            border-radius: 12px;
            border: 2px solid #2a2a2a;
            overflow: hidden;
        }
        .result-card.loading { opacity: 0.6; }
        .result-card.error { border-color: #ef4444; }
        .result-card.winner { border-color: #10b981; }
        .result-card.cached { border-color: #f59e0b; }

        .result-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 16px 20px;
            background: #151515;
            border-bottom: 1px solid #2a2a2a;
        }
        .result-header h3 { color: #fff; font-size: 15px; font-weight: 500; display: flex; align-items: center; gap: 8px; }
        .result-meta { display: flex; gap: 12px; font-size: 11px; color: #888; }
        .result-meta .cached-badge { color: #f59e0b; font-weight: 500; }

        .result-tabs {
            display: flex;
            gap: 0;
            background: #151515;
            border-bottom: 1px solid #2a2a2a;
        }
        .result-tab {
            padding: 10px 20px;
            font-size: 12px;
            color: #888;
            cursor: pointer;
            border-bottom: 2px solid transparent;
            transition: all 0.2s;
        }
        .result-tab:hover { color: #fff; }
        .result-tab.active { color: #7c3aed; border-bottom-color: #7c3aed; }

        .result-content {
            padding: 20px;
            font-size: 14px;
            line-height: 1.7;
            max-height: 500px;
            overflow-y: auto;
        }
        .result-content::-webkit-scrollbar { width: 6px; }
        .result-content::-webkit-scrollbar-track { background: #2a2a2a; border-radius: 3px; }
        .result-content::-webkit-scrollbar-thumb { background: #4a4a4a; border-radius: 3px; }

        .tab-content { display: none; }
        .tab-content.active { display: block; }

        .segment {
            margin-bottom: 16px;
            padding: 12px 16px;
            background: #252525;
            border-radius: 8px;
            border-left: 3px solid #7c3aed;
        }
        .segment-header {
            display: flex;
            align-items: center;
            gap: 10px;
            margin-bottom: 8px;
        }
        .speaker-label {
            display: inline-block;
            background: #7c3aed;
            color: white;
            padding: 3px 10px;
            border-radius: 4px;
            font-size: 11px;
            font-weight: 600;
        }
        .speaker-a, .speaker-speaker_a, .speaker-0, .speaker-speaker_0 { background: #7c3aed; }
        .speaker-b, .speaker-speaker_b, .speaker-1, .speaker-speaker_1 { background: #059669; }
        .speaker-c, .speaker-speaker_c, .speaker-2, .speaker-speaker_2 { background: #d97706; }
        .speaker-d, .speaker-speaker_d, .speaker-3, .speaker-speaker_3 { background: #dc2626; }
        .speaker-e, .speaker-speaker_e, .speaker-4, .speaker-speaker_4 { background: #2563eb; }

        .segment[data-speaker="Speaker A"], .segment[data-speaker="speaker_0"], .segment[data-speaker="Speaker 0"] { border-left-color: #7c3aed; }
        .segment[data-speaker="Speaker B"], .segment[data-speaker="speaker_1"], .segment[data-speaker="Speaker 1"] { border-left-color: #059669; }
        .segment[data-speaker="Speaker C"], .segment[data-speaker="speaker_2"], .segment[data-speaker="Speaker 2"] { border-left-color: #d97706; }
        .segment[data-speaker="Speaker D"], .segment[data-speaker="speaker_3"], .segment[data-speaker="Speaker 3"] { border-left-color: #dc2626; }

        .segment-time {
            font-size: 11px;
            color: #888;
            font-family: 'SF Mono', Monaco, monospace;
            background: #1a1a1a;
            padding: 2px 8px;
            border-radius: 4px;
            cursor: pointer;
            transition: all 0.15s;
        }
        .segment-time:hover {
            background: #7c3aed;
            color: #fff;
        }
        .segment-time.playing {
            background: #7c3aed;
            color: #fff;
            animation: pulse 1.5s ease-in-out infinite;
        }
        @keyframes pulse {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.7; }
        }

        .segment.active {
            background: #2a2a3a;
            border-left-color: #a855f7;
        }
        .segment-text { color: #e0e0e0; }

        .raw-json {
            background: #151515;
            padding: 16px;
            border-radius: 8px;
            font-family: 'SF Mono', Monaco, monospace;
            font-size: 12px;
            white-space: pre-wrap;
            word-break: break-all;
            color: #a0a0a0;
        }

        .plain-text {
            white-space: pre-wrap;
            word-wrap: break-word;
        }

        .loading-spinner {
            display: inline-block;
            width: 16px; height: 16px;
            border: 2px solid #4a4a4a;
            border-top-color: #7c3aed;
            border-radius: 50%;
            animation: spin 1s linear infinite;
        }
        @keyframes spin { to { transform: rotate(360deg); } }

        .error-message {
            color: #ef4444;
            background: rgba(239, 68, 68, 0.1);
            padding: 12px;
            border-radius: 6px;
            font-size: 13px;
        }

        .actions {
            display: flex;
            gap: 8px;
            padding: 16px 20px;
            background: #151515;
            border-top: 1px solid #2a2a2a;
        }
        .actions button { padding: 8px 16px; font-size: 12px; }

        .empty-state { text-align: center; padding: 60px 20px; color: #666; grid-column: 1 / -1; }
        .shortcut-hint { font-size: 11px; color: #666; margin-top: 4px; }
        .prompt-note { font-size: 11px; color: #7c3aed; margin-top: 4px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Transcription Benchmark</h1>

        <div class="api-status">
            <span><span class="dot {{ 'active' if apis.openai else 'inactive' }}"></span> OpenAI</span>
            <span><span class="dot {{ 'active' if apis.assemblyai else 'inactive' }}"></span> AssemblyAI</span>
            <span><span class="dot {{ 'active' if apis.gemini else 'inactive' }}"></span> Gemini</span>
        </div>

        <div class="controls">
            <div class="controls-row">
                <div class="control-group" style="flex: 1; max-width: 500px;">
                    <label>Audio File</label>
                    <select id="audioSelect" onchange="loadAudio()">
                        <option value="">Select audio file...</option>
                        {% for audio in audio_files %}
                        <option value="{{ audio.path }}" data-duration="{{ audio.duration }}">{{ audio.duration_str }} - {{ audio.name }} ({{ audio.size }})</option>
                        {% endfor %}
                    </select>
                </div>

                <div class="control-group">
                    <label>Language</label>
                    <select id="languageSelect">
                        <option value="">Auto-detect</option>
                        <option value="pt" selected>Portuguese</option>
                        <option value="en">English</option>
                        <option value="es">Spanish</option>
                    </select>
                </div>

                <div class="control-group">
                    <button onclick="runBenchmark()" id="runBtn">
                        <span id="runBtnText">Run Selected Models</span>
                    </button>
                    <div class="shortcut-hint">⌘+Enter | Cached results shown in yellow</div>
                </div>
            </div>

            <div class="controls-row">
                <div class="control-group">
                    <label>Models (click to toggle)</label>
                    <div class="model-checkboxes" id="modelCheckboxes">
                        {% for model_id, model in models.items() %}
                        {% set available = apis.get(model.provider, False) %}
                        <label class="model-checkbox {{ 'selected' if available else '' }} {{ '' if available else 'disabled' }}"
                               data-model="{{ model_id }}" data-available="{{ 'true' if available else 'false' }}"
                               onclick="toggleModel(this)">
                            <span class="check"></span>
                            <span>{{ model.name }}</span>
                            {% if model.supports_diarization %}<span class="model-info diarize">👥</span>{% endif %}
                            <span class="provider-tag provider-{{ model.provider }}">{{ model.provider }}</span>
                        </label>
                        {% endfor %}
                    </div>
                </div>
            </div>

            <div class="controls-row">
                <div class="control-group flex-1">
                    <label>Context / Vocabulary Hints</label>
                    <textarea id="userContextInput" placeholder="Add vocabulary hints, speaker names, meeting context...">{{ default_user_context }}</textarea>
                    <div class="prompt-note">Used by Whisper and Gemini. AssemblyAI and GPT-4o-diarize use native diarization only.</div>
                </div>
            </div>
        </div>

        <div class="audio-player" id="audioPlayer" style="display: none;">
            <audio id="audio" controls></audio>
        </div>

        <h2>Results</h2>
        <div class="results-grid" id="results">
            <div class="empty-state">
                <p>Select an audio file and models, then click "Run Selected Models"</p>
            </div>
        </div>
    </div>

    <script>
        let currentAudio = null;
        const apis = {{ apis | tojson }};
        const models = {{ models | tojson }};

        document.addEventListener('keydown', (e) => {
            if ((e.metaKey || e.ctrlKey) && e.key === 'Enter') {
                e.preventDefault();
                runBenchmark();
            }
        });

        function toggleModel(el) {
            if (el.dataset.available !== 'true') return;
            el.classList.toggle('selected');
        }

        function getSelectedModels() {
            return Array.from(document.querySelectorAll('.model-checkbox.selected'))
                .filter(el => el.dataset.available === 'true')
                .map(el => el.dataset.model);
        }

        function loadAudio() {
            const select = document.getElementById('audioSelect');
            const player = document.getElementById('audioPlayer');
            const audio = document.getElementById('audio');

            if (select.value) {
                currentAudio = select.value;
                audio.src = '/audio?path=' + encodeURIComponent(select.value);
                player.style.display = 'block';
            } else {
                player.style.display = 'none';
                currentAudio = null;
            }
        }

        async function runBenchmark() {
            if (!currentAudio) { alert('Please select an audio file first'); return; }

            const selectedModels = getSelectedModels();
            if (selectedModels.length === 0) { alert('Please select at least one model'); return; }

            const language = document.getElementById('languageSelect').value;
            const userContext = document.getElementById('userContextInput').value;

            const btn = document.getElementById('runBtn');
            const btnText = document.getElementById('runBtnText');
            btn.disabled = true;
            btnText.innerHTML = '<span class="loading-spinner"></span> Running...';

            const resultsDiv = document.getElementById('results');
            resultsDiv.innerHTML = '';

            for (const model of selectedModels) {
                resultsDiv.appendChild(createResultCard(model, null, true));
            }

            const promises = selectedModels.map(model =>
                fetch('/transcribe', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ audio_path: currentAudio, model, language: language || null, user_context: userContext || null })
                }).then(r => r.json()).then(data => ({ model, data }))
                  .catch(err => ({ model, data: { error: err.message } }))
            );

            for (const promise of promises) {
                const { model, data } = await promise;
                const card = document.getElementById('card-' + model.replace(/[^a-z0-9]/gi, '_'));
                if (card) card.replaceWith(createResultCard(model, data, false));
            }

            btn.disabled = false;
            btnText.textContent = 'Run Selected Models';
        }

        function createResultCard(model, data, loading) {
            const info = models[model] || { name: model, provider: 'unknown' };
            const cardId = 'card-' + model.replace(/[^a-z0-9]/gi, '_');

            const card = document.createElement('div');
            card.className = 'result-card' + (loading ? ' loading' : '') + (data?.error ? ' error' : '') + (data?._cached ? ' cached' : '');
            card.id = cardId;

            if (loading) {
                card.innerHTML = `
                    <div class="result-header">
                        <h3>${info.name} <span class="provider-tag provider-${info.provider}">${info.provider}</span></h3>
                        <div class="result-meta"><span><span class="loading-spinner"></span> Transcribing...</span></div>
                    </div>
                    <div class="result-content" style="color: #666; padding: 40px; text-align: center;">Waiting for results...</div>
                `;
            } else if (data?.error) {
                card.innerHTML = `
                    <div class="result-header">
                        <h3>${info.name} <span class="provider-tag provider-${info.provider}">${info.provider}</span></h3>
                    </div>
                    <div class="result-content"><div class="error-message">${escapeHtml(data.error)}</div></div>
                `;
            } else {
                const duration = data.duration_seconds ? formatDuration(data.duration_seconds) : '?';
                const latency = data.latency_seconds ? `${data.latency_seconds.toFixed(1)}s` : '?';
                const cost = data.estimated_cost_cents ? `$${(data.estimated_cost_cents / 100).toFixed(4)}` : 'free';
                const costLabel = data.actual_cost ? '💰' : '💰~';  // ~ means estimated
                const cached = data._cached ? '<span class="cached-badge">CACHED</span>' : '';
                const tokens = data.tokens ? `🔢 ${(data.tokens.input/1000).toFixed(1)}k in / ${(data.tokens.output/1000).toFixed(1)}k out` : '';

                // Build segments view
                let segmentsHtml = '';
                if (data.segments && data.segments.length > 0 && data.segments.some(s => s.speaker)) {
                    segmentsHtml = data.segments.map((seg, idx) => {
                        const speaker = seg.speaker || 'unknown';
                        const speakerClass = speaker.toLowerCase().replace(/[^a-z0-9_]/g, '_');
                        const startSec = seg.start !== null && seg.start !== undefined ? seg.start : null;
                        const endSec = seg.end !== null && seg.end !== undefined ? seg.end : null;
                        const timeStr = startSec !== null ? formatTime(startSec) : '';
                        const endStr = endSec !== null ? ` - ${formatTime(endSec)}` : '';
                        const clickHandler = startSec !== null ? `onclick="playFromTime(${startSec}, ${endSec || 'null'})"` : '';
                        return `<div class="segment" data-speaker="${speaker}" data-start="${startSec}" data-end="${endSec}" data-idx="${idx}">
                            <div class="segment-header">
                                <span class="speaker-label speaker-${speakerClass}">${speaker}</span>
                                ${timeStr ? `<span class="segment-time" ${clickHandler} title="Click to play from ${timeStr}">▶ ${timeStr}${endStr}</span>` : ''}
                            </div>
                            <div class="segment-text">${escapeHtml(seg.text)}</div>
                        </div>`;
                    }).join('');
                } else {
                    segmentsHtml = '<div class="plain-text">' + escapeHtml(data.text || 'No transcription') + '</div>';
                }

                // Build raw JSON view
                const rawJson = JSON.stringify(data, null, 2);

                card.innerHTML = `
                    <div class="result-header">
                        <h3>${info.name} <span class="provider-tag provider-${info.provider}">${info.provider}</span></h3>
                        <div class="result-meta">
                            ${cached}
                            <span title="API latency">⏱ ${latency}</span>
                            <span title="Audio duration">📏 ${duration}</span>
                            <span title="${data.actual_cost ? 'Actual cost from API' : 'Estimated cost'}">${costLabel} ${cost}</span>
                            ${tokens ? `<span title="Token usage">${tokens}</span>` : ''}
                        </div>
                    </div>
                    <div class="result-tabs">
                        <div class="result-tab active" onclick="switchTab(this, 'segments')">Transcript</div>
                        <div class="result-tab" onclick="switchTab(this, 'plain')">Plain Text</div>
                        <div class="result-tab" onclick="switchTab(this, 'raw')">Raw JSON</div>
                    </div>
                    <div class="result-content">
                        <div class="tab-content active" data-tab="segments">${segmentsHtml}</div>
                        <div class="tab-content" data-tab="plain"><div class="plain-text">${escapeHtml(data.text || '')}</div></div>
                        <div class="tab-content" data-tab="raw"><div class="raw-json">${escapeHtml(rawJson)}</div></div>
                    </div>
                    <div class="actions">
                        <button class="secondary" onclick="copyText(this)" data-text="${escapeAttr(data.text || '')}">Copy Text</button>
                        <button class="secondary" onclick="copyJson(this)" data-json="${escapeAttr(rawJson)}">Copy JSON</button>
                        <button class="secondary" onclick="markWinner(this)">⭐ Best</button>
                    </div>
                `;
            }

            return card;
        }

        function switchTab(tabEl, tabName) {
            const card = tabEl.closest('.result-card');
            card.querySelectorAll('.result-tab').forEach(t => t.classList.remove('active'));
            card.querySelectorAll('.tab-content').forEach(t => t.classList.remove('active'));
            tabEl.classList.add('active');
            card.querySelector(`.tab-content[data-tab="${tabName}"]`).classList.add('active');
        }

        function formatTime(seconds) {
            if (seconds === null || seconds === undefined) return '';
            const mins = Math.floor(seconds / 60);
            const secs = Math.floor(seconds % 60);
            return `${mins}:${secs.toString().padStart(2, '0')}`;
        }

        function formatDuration(seconds) {
            if (seconds < 60) return `${Math.round(seconds)}s`;
            if (seconds < 3600) return `${Math.floor(seconds/60)}m${Math.floor(seconds%60)}s`;
            return `${Math.floor(seconds/3600)}h${Math.floor((seconds%3600)/60)}m`;
        }

        function escapeHtml(text) {
            const div = document.createElement('div');
            div.textContent = text;
            return div.innerHTML;
        }

        function escapeAttr(text) {
            return text.replace(/"/g, '&quot;').replace(/'/g, '&#39;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
        }

        function copyText(btn) {
            navigator.clipboard.writeText(btn.dataset.text);
            const orig = btn.textContent;
            btn.textContent = 'Copied!';
            setTimeout(() => btn.textContent = orig, 1500);
        }

        function copyJson(btn) {
            navigator.clipboard.writeText(btn.dataset.json.replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&lt;/g, '<').replace(/&gt;/g, '>'));
            const orig = btn.textContent;
            btn.textContent = 'Copied!';
            setTimeout(() => btn.textContent = orig, 1500);
        }

        function markWinner(btn) {
            document.querySelectorAll('.result-card').forEach(c => c.classList.remove('winner'));
            btn.closest('.result-card').classList.add('winner');
        }

        // Audio playback from timestamps
        let currentPlayingEnd = null;
        let playbackCheckInterval = null;

        function playFromTime(startSeconds, endSeconds) {
            const audio = document.getElementById('audio');
            if (!audio.src) {
                alert('Please load an audio file first');
                return;
            }

            // Clear previous interval
            if (playbackCheckInterval) {
                clearInterval(playbackCheckInterval);
                playbackCheckInterval = null;
            }

            // Seek to start time and play
            audio.currentTime = startSeconds;
            currentPlayingEnd = endSeconds;
            audio.play();

            // Highlight the segment being played
            updateActiveSegment(startSeconds);

            // Show playing indicator on timestamp
            document.querySelectorAll('.segment-time').forEach(el => el.classList.remove('playing'));
            event.target.classList.add('playing');

            // If we have an end time, stop at that point
            if (endSeconds !== null) {
                playbackCheckInterval = setInterval(() => {
                    if (audio.currentTime >= endSeconds) {
                        audio.pause();
                        clearInterval(playbackCheckInterval);
                        playbackCheckInterval = null;
                        document.querySelectorAll('.segment-time').forEach(el => el.classList.remove('playing'));
                        document.querySelectorAll('.segment').forEach(el => el.classList.remove('active'));
                    }
                }, 100);
            }
        }

        function updateActiveSegment(currentTime) {
            document.querySelectorAll('.segment').forEach(seg => {
                const start = parseFloat(seg.dataset.start);
                const end = seg.dataset.end !== 'null' ? parseFloat(seg.dataset.end) : Infinity;

                if (!isNaN(start) && currentTime >= start && currentTime < end) {
                    seg.classList.add('active');
                } else {
                    seg.classList.remove('active');
                }
            });
        }

        // Update active segment as audio plays
        document.addEventListener('DOMContentLoaded', () => {
            const audio = document.getElementById('audio');
            if (audio) {
                audio.addEventListener('timeupdate', () => {
                    updateActiveSegment(audio.currentTime);
                });

                audio.addEventListener('pause', () => {
                    document.querySelectorAll('.segment-time').forEach(el => el.classList.remove('playing'));
                });

                audio.addEventListener('ended', () => {
                    document.querySelectorAll('.segment-time').forEach(el => el.classList.remove('playing'));
                    document.querySelectorAll('.segment').forEach(el => el.classList.remove('active'));
                });
            }
        });
    </script>
</body>
</html>
"""

@app.route('/')
def index():
    audio_files = get_meetings_from_db()

    if AUDIO_DIR.exists():
        existing_paths = {f["path"] for f in audio_files}
        for f in sorted(AUDIO_DIR.glob("*.m4a"), key=lambda x: x.stat().st_mtime, reverse=True)[:10]:
            if str(f) not in existing_paths:
                size_kb = f.stat().st_size / 1024
                duration = get_audio_duration(str(f))
                audio_files.append({
                    "path": str(f), "name": f.name, "duration": duration,
                    "duration_str": format_duration(duration),
                    "size": f"{size_kb:.0f}KB" if size_kb < 1024 else f"{size_kb/1024:.1f}MB",
                    "source": "legacy"
                })

    return render_template_string(HTML_TEMPLATE, audio_files=audio_files, models=MODELS, apis=get_available_apis(), default_user_context=DEFAULT_USER_CONTEXT)


@app.route('/audio')
def serve_audio():
    path = request.args.get('path')
    if path and os.path.exists(path):
        return send_file(path, mimetype='audio/m4a')
    return "Not found", 404


@app.route('/transcribe', methods=['POST'])
def transcribe():
    data = request.json
    audio_path = data.get('audio_path')
    model = data.get('model', 'whisper-1')
    language = data.get('language')
    user_context = data.get('user_context')  # Renamed from prompt

    if not audio_path or not os.path.exists(audio_path):
        return jsonify({"error": "Audio file not found"}), 400

    # Check cache first
    cache_key = get_cache_key(audio_path, model, language, user_context)
    cached = get_cached_result(cache_key)
    if cached:
        print(f"[CACHE HIT] {model} - {Path(audio_path).name}")
        return jsonify(cached)

    print(f"[CACHE MISS] {model} - {Path(audio_path).name}")

    try:
        model_info = MODELS.get(model, {})
        provider = model_info.get("provider", "openai")

        if provider == "openai":
            result = transcribe_openai(audio_path, model, language, user_context)
        elif provider == "assemblyai":
            result = transcribe_assemblyai(audio_path, language)
        elif provider == "gemini":
            result = transcribe_gemini(audio_path, model, language, user_context)
        else:
            return jsonify({"error": f"Unknown provider: {provider}"}), 400

        # Save to cache
        save_to_cache(cache_key, result)

        # Also save to results
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        audio_name = Path(audio_path).stem
        result_file = RESULTS_DIR / f"{audio_name}_{model}_{timestamp}.json"
        with open(result_file, "w", encoding="utf-8") as f:
            json.dump(result, f, indent=2, ensure_ascii=False)

        return jsonify(result)

    except Exception as e:
        import traceback
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500


@app.route('/clear-cache', methods=['POST'])
def clear_cache():
    """Clear all cached results"""
    count = 0
    for f in CACHE_DIR.glob("*.json"):
        f.unlink()
        count += 1
    return jsonify({"cleared": count})


if __name__ == '__main__':
    apis = get_available_apis()
    cache_count = len(list(CACHE_DIR.glob("*.json")))
    print("\n🎙️  Transcription Benchmark UI")
    print("   Open http://localhost:5001 in your browser\n")
    print("   APIs configured:")
    print(f"     {'✓' if apis['openai'] else '✗'} OpenAI")
    print(f"     {'✓' if apis['assemblyai'] else '✗'} AssemblyAI")
    print(f"     {'✓' if apis['gemini'] else '✗'} Gemini")
    print(f"\n   Cache: {cache_count} entries in .cache/")
    print()
    app.run(debug=True, port=5001)
