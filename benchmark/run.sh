#!/bin/bash
# Launch the transcription benchmark UI

cd "$(dirname "$0")"

# Try to load from .env file first
if [ -f .env ]; then
    echo "Loading API keys from .env file..."
    export $(grep -v '^#' .env | xargs)
fi

# If no OpenAI key in env, try to read from MeetingRecorder keychain
if [ -z "$OPENAI_API_KEY" ]; then
    echo "Checking macOS keychain for OpenAI key..."
    KEYCHAIN_KEY=$(security find-generic-password -s "MeetingRecorder-OpenAI" -w 2>/dev/null)
    if [ -n "$KEYCHAIN_KEY" ]; then
        export OPENAI_API_KEY="$KEYCHAIN_KEY"
        echo "✓ Found OpenAI key in keychain"
    else
        echo "⚠ No OpenAI key found. Set OPENAI_API_KEY or add to .env"
    fi
fi

# Show which keys are configured
echo ""
echo "API Keys configured:"
[ -n "$OPENAI_API_KEY" ] && echo "  ✓ OpenAI" || echo "  ✗ OpenAI (required)"
[ -n "$ASSEMBLYAI_API_KEY" ] && echo "  ✓ AssemblyAI" || echo "  ✗ AssemblyAI (optional)"
[ -n "$GEMINI_API_KEY" ] && echo "  ✓ Gemini" || echo "  ✗ Gemini (optional)"
echo ""

# Activate venv
source venv/bin/activate

# Run the app
python app.py
