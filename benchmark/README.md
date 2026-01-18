# Transcription Benchmark Tool

Compare different transcription models and prompts side-by-side.

## Setup

```bash
cd benchmark
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

## Set your API key

```bash
export OPENAI_API_KEY="sk-..."
```

## Run benchmarks

```bash
# Transcribe with all models
python benchmark.py transcribe --audio ../test_audio/sample.m4a

# Run web UI for comparison
python app.py
# Open http://localhost:5001
```

## Models tested

- `whisper-1` - Original Whisper (baseline)
- `gpt-4o-transcribe` - GPT-4o transcribe (no diarization)
- `gpt-4o-mini-transcribe` - Cheaper, faster
- `gpt-4o-transcribe-diarize` - With speaker labels

## Prompt variations

Edit `prompts.json` to test different prompts.
