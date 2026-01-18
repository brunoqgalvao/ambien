#!/usr/bin/env python3
"""Test all transcription models with a sample audio file"""

import os
import json
import time
import requests
import base64
import subprocess
import tempfile
from pathlib import Path
from datetime import datetime
from dotenv import load_dotenv
from openai import OpenAI

load_dotenv()

# Test audio file
AUDIO_PATH = "/Users/brunogalvao/Documents/MeetingRecorder/recordings/meeting_2026-01-17_10-09-33.m4a"
RESULTS_DIR = Path(__file__).parent / "test_results"
RESULTS_DIR.mkdir(exist_ok=True)

def get_audio_duration(file_path):
    try:
        result = subprocess.run(
            ["ffprobe", "-v", "error", "-show_entries", "format=duration",
             "-of", "default=noprint_wrappers=1:nokey=1", file_path],
            capture_output=True, text=True, timeout=10
        )
        return float(result.stdout.strip())
    except:
        return 0.0

def compress_audio(audio_path, target_mb=24):
    """Compress audio to fit size limit"""
    file_size_mb = Path(audio_path).stat().st_size / (1024 * 1024)
    if file_size_mb <= target_mb:
        return audio_path

    duration = get_audio_duration(audio_path)
    if duration <= 0:
        raise ValueError("Could not determine audio duration")

    # Calculate target bitrate
    target_kbps = int((target_mb * 8 * 1024) / duration)
    target_kbps = max(32, min(target_kbps, 128))

    temp_dir = Path(tempfile.gettempdir()) / "benchmark_compressed"
    temp_dir.mkdir(exist_ok=True)
    compressed_path = temp_dir / f"compressed_{Path(audio_path).stem}.m4a"

    cmd = [
        "ffmpeg", "-y", "-i", audio_path,
        "-ac", "1", "-ar", "16000",
        "-b:a", f"{target_kbps}k",
        "-acodec", "aac",
        str(compressed_path)
    ]

    result = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    if result.returncode != 0:
        raise ValueError(f"Compression failed: {result.stderr[:200]}")

    new_size = compressed_path.stat().st_size / (1024 * 1024)
    print(f"  Compressed: {file_size_mb:.1f}MB -> {new_size:.1f}MB ({target_kbps}kbps)")
    return str(compressed_path)

def save_result(model, result, error=None):
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    filename = f"{model.replace('/', '_')}_{timestamp}.json"
    filepath = RESULTS_DIR / filename

    data = {
        "model": model,
        "timestamp": timestamp,
        "audio_file": AUDIO_PATH,
        "error": error,
        "result": result
    }

    with open(filepath, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)

    print(f"  Saved to {filepath.name}")
    return filepath

def test_openai(model):
    print(f"\n[Testing] {model}")
    client = OpenAI()

    file_size_mb = Path(AUDIO_PATH).stat().st_size / (1024 * 1024)
    print(f"  Original size: {file_size_mb:.1f}MB")

    # Compress if needed
    audio_path = AUDIO_PATH
    if file_size_mb > 25:
        try:
            audio_path = compress_audio(AUDIO_PATH)
            file_size_mb = Path(audio_path).stat().st_size / (1024 * 1024)
        except Exception as e:
            error = f"Compression failed: {e}"
            print(f"  ERROR: {error}")
            save_result(model, None, error)
            return None

    start = time.time()
    try:
        with open(audio_path, "rb") as f:
            kwargs = {"file": f, "model": model}

            if model == "whisper-1":
                kwargs["response_format"] = "verbose_json"
                kwargs["language"] = "pt"
            elif model == "gpt-4o-transcribe-diarize":
                kwargs["response_format"] = "verbose_json"
                kwargs["chunking_strategy"] = "auto"
                kwargs["language"] = "pt"
            else:
                kwargs["response_format"] = "json"
                kwargs["language"] = "pt"

            response = client.audio.transcriptions.create(**kwargs)

        latency = time.time() - start
        print(f"  Success! Latency: {latency:.1f}s")

        text = response.text if hasattr(response, 'text') else str(response)

        result = {
            "text": text[:500] + "..." if len(text) > 500 else text,
            "full_text_length": len(text),
            "latency_seconds": round(latency, 2),
            "has_segments": hasattr(response, 'segments'),
            "segment_count": len(response.segments) if hasattr(response, 'segments') else 0,
        }

        if hasattr(response, 'segments') and response.segments:
            has_speakers = any(hasattr(seg, 'speaker') and seg.speaker for seg in response.segments)
            result["has_speaker_labels"] = has_speakers
            result["first_3_segments"] = [
                {
                    "start": seg.start,
                    "end": seg.end,
                    "text": seg.text[:100],
                    "speaker": getattr(seg, 'speaker', None)
                }
                for seg in response.segments[:3]
            ]

        save_result(model, result)
        return result

    except Exception as e:
        latency = time.time() - start
        error = str(e)
        print(f"  ERROR ({latency:.1f}s): {error[:200]}")
        save_result(model, None, error)
        return None

def test_assemblyai():
    print(f"\n[Testing] assemblyai-best")
    api_key = os.environ.get("ASSEMBLYAI_API_KEY")
    if not api_key:
        error = "ASSEMBLYAI_API_KEY not set"
        print(f"  ERROR: {error}")
        save_result("assemblyai-best", None, error)
        return None

    headers = {"authorization": api_key}
    start = time.time()

    try:
        print("  Uploading...")
        with open(AUDIO_PATH, "rb") as f:
            upload_response = requests.post(
                "https://api.assemblyai.com/v2/upload",
                headers=headers,
                data=f
            )
        upload_url = upload_response.json()["upload_url"]
        print(f"  Upload done ({time.time() - start:.1f}s)")

        print("  Requesting transcription...")
        transcript_request = {
            "audio_url": upload_url,
            "speaker_labels": True,
            "language_code": "pt"
        }
        transcript_response = requests.post(
            "https://api.assemblyai.com/v2/transcript",
            headers=headers,
            json=transcript_request
        )
        transcript_id = transcript_response.json()["id"]

        print("  Polling...")
        while True:
            poll_response = requests.get(
                f"https://api.assemblyai.com/v2/transcript/{transcript_id}",
                headers=headers
            )
            status = poll_response.json()["status"]
            if status == "completed":
                break
            elif status == "error":
                raise ValueError(f"AssemblyAI error: {poll_response.json().get('error')}")
            print(f"    Status: {status} ({time.time() - start:.1f}s)")
            time.sleep(5)

        result_data = poll_response.json()
        latency = time.time() - start
        print(f"  Success! Latency: {latency:.1f}s")

        text = result_data.get("text", "")
        utterances = result_data.get("utterances", [])

        result = {
            "text": text[:500] + "..." if len(text) > 500 else text,
            "full_text_length": len(text),
            "latency_seconds": round(latency, 2),
            "segment_count": len(utterances),
            "has_speaker_labels": True,
            "confidence": result_data.get("confidence"),
        }

        if utterances:
            result["first_3_segments"] = [
                {
                    "start": u["start"] / 1000,
                    "end": u["end"] / 1000,
                    "text": u["text"][:100],
                    "speaker": f"Speaker {u['speaker']}"
                }
                for u in utterances[:3]
            ]

        save_result("assemblyai-best", result)
        return result

    except Exception as e:
        error = str(e)
        print(f"  ERROR: {error[:200]}")
        save_result("assemblyai-best", None, error)
        return None

def test_gemini(model):
    print(f"\n[Testing] {model}")
    api_key = os.environ.get("GEMINI_API_KEY")
    if not api_key:
        error = "GEMINI_API_KEY not set"
        print(f"  ERROR: {error}")
        save_result(model, None, error)
        return None

    start = time.time()

    try:
        print("  Reading audio...")
        with open(AUDIO_PATH, "rb") as f:
            audio_data = base64.b64encode(f.read()).decode("utf-8")

        audio_duration = get_audio_duration(AUDIO_PATH)
        print(f"  Duration: {audio_duration/60:.1f}min, Base64: {len(audio_data)/1024/1024:.1f}MB")

        model_api_map = {
            "gemini-2.0-flash": "gemini-2.0-flash",
            "gemini-2.5-flash": "gemini-2.5-flash",
            "gemini-3-flash": "gemini-3-flash-preview",
        }
        api_model = model_api_map.get(model, "gemini-2.0-flash")

        prompt = """Transcribe this audio in Portuguese with speaker diarization and timestamps.

RULES:
1. Label speakers as Speaker A, Speaker B, etc. based on voice.
2. Group consecutive speech from the same speaker into ONE segment.
3. Only start a new segment when the speaker CHANGES.
4. Include timestamp (MM:SS) at the start of each segment.

FORMAT:
[Speaker A, 0:00] Complete speech until next speaker.
[Speaker B, 1:15] Next speaker's complete response.

Transcribe the entire audio now:"""

        # Calculate appropriate max tokens
        estimated_tokens = max(8192, int(audio_duration / 60 * 150))
        max_tokens = min(estimated_tokens, 65536)
        print(f"  Max tokens: {max_tokens}")

        url = f"https://generativelanguage.googleapis.com/v1beta/models/{api_model}:generateContent?key={api_key}"

        payload = {
            "contents": [{"parts": [
                {"text": prompt},
                {"inline_data": {"mime_type": "audio/mp4", "data": audio_data}}
            ]}],
            "generationConfig": {"temperature": 0.1, "maxOutputTokens": max_tokens}
        }

        print(f"  Sending to {api_model}...")
        response = requests.post(url, json=payload, timeout=600)

        if response.status_code != 200:
            raise ValueError(f"HTTP {response.status_code}: {response.text[:500]}")

        result_json = response.json()
        latency = time.time() - start
        print(f"  Success! Latency: {latency:.1f}s")

        text = ""
        if "candidates" in result_json and result_json["candidates"]:
            parts = result_json["candidates"][0].get("content", {}).get("parts", [])
            text = " ".join(p.get("text", "") for p in parts)

        import re
        speakers_found = set(re.findall(r'\[Speaker\s+([A-Z])', text))

        result = {
            "text": text[:500] + "..." if len(text) > 500 else text,
            "full_text_length": len(text),
            "latency_seconds": round(latency, 2),
            "api_model": api_model,
            "speakers_found": list(speakers_found),
            "has_speaker_labels": len(speakers_found) > 0,
            "max_tokens_used": max_tokens,
        }

        save_result(model, result)
        return result

    except Exception as e:
        error = str(e)
        print(f"  ERROR: {error[:300]}")
        save_result(model, None, error)
        return None

def main():
    print("=" * 60)
    print("TRANSCRIPTION MODEL TEST (with fixes)")
    print("=" * 60)

    audio_duration = get_audio_duration(AUDIO_PATH)
    file_size = Path(AUDIO_PATH).stat().st_size / (1024 * 1024)
    print(f"Audio: {AUDIO_PATH}")
    print(f"Duration: {audio_duration/60:.1f} min")
    print(f"Size: {file_size:.1f} MB")

    results = {}

    # OpenAI (with compression)
    for model in ["whisper-1", "gpt-4o-mini-transcribe", "gpt-4o-transcribe", "gpt-4o-transcribe-diarize"]:
        results[model] = test_openai(model)

    # AssemblyAI
    results["assemblyai-best"] = test_assemblyai()

    # Gemini (with increased max tokens)
    for model in ["gemini-2.0-flash", "gemini-2.5-flash", "gemini-3-flash"]:
        results[model] = test_gemini(model)

    # Summary
    print("\n" + "=" * 60)
    print("SUMMARY")
    print("=" * 60)

    for model, result in results.items():
        if result:
            latency = result.get("latency_seconds", "?")
            has_speakers = result.get("has_speaker_labels", False)
            text_len = result.get("full_text_length", 0)
            print(f"✓ {model}: {latency}s, {text_len} chars, speakers={has_speakers}")
        else:
            print(f"✗ {model}: FAILED")

    # Save summary
    summary_path = RESULTS_DIR / "summary.json"
    with open(summary_path, "w") as f:
        json.dump({
            "audio_file": AUDIO_PATH,
            "audio_duration_min": audio_duration / 60,
            "file_size_mb": file_size,
            "timestamp": datetime.now().isoformat(),
            "results": {k: v for k, v in results.items() if v}
        }, f, indent=2)

    print(f"\nResults in: {RESULTS_DIR}")

if __name__ == "__main__":
    main()
