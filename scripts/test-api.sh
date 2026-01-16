#!/bin/bash
#
# Test script for MeetingRecorder API endpoints
#
# Prerequisites:
#   1. Build and run the app with ENABLE_TEST_API=1
#   Or: defaults write com.meetingrecorder.app enableTestAPI -bool true
#
# Usage:
#   ./scripts/test-api.sh
#

BASE_URL="http://localhost:8765"
PASSED=0
FAILED=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_pass() {
    echo -e "  ${GREEN}✓${NC} $1"
    ((PASSED++))
}

log_fail() {
    echo -e "  ${RED}✗${NC} $1"
    ((FAILED++))
}

log_section() {
    echo ""
    echo -e "${YELLOW}$1${NC}"
}

# Test helper - check if response contains expected string
test_contains() {
    local name="$1"
    local response="$2"
    local expected="$3"

    if echo "$response" | grep -q "$expected"; then
        log_pass "$name"
        return 0
    else
        log_fail "$name - expected '$expected'"
        echo "      Response: $(echo "$response" | head -c 200)"
        return 1
    fi
}

# Check if server is running
echo "════════════════════════════════════════════════════"
echo "  MeetingRecorder Test API"
echo "════════════════════════════════════════════════════"

response=$(curl -s --max-time 5 "$BASE_URL/health" 2>/dev/null)
if ! echo "$response" | grep -q "ok"; then
    echo -e "${RED}Error: Test API server is not running${NC}"
    echo ""
    echo "To enable:"
    echo "  defaults write com.meetingrecorder.app enableTestAPI -bool true"
    echo "  Then restart the app"
    exit 1
fi

echo -e "${GREEN}Server running on $BASE_URL${NC}"

# ═══════════════════════════════════════════════════════
# HEALTH
# ═══════════════════════════════════════════════════════
log_section "Health Check"
response=$(curl -s --max-time 5 "$BASE_URL/health")
test_contains "GET /health" "$response" '"ok"'

# ═══════════════════════════════════════════════════════
# PROVIDERS / KEYCHAIN
# ═══════════════════════════════════════════════════════
log_section "Keychain / Providers"

response=$(curl -s --max-time 5 "$BASE_URL/api/keychain/providers")
test_contains "GET /api/keychain/providers" "$response" '"providers"'
test_contains "  - has OpenAI" "$response" '"openai"'
test_contains "  - has Gemini" "$response" '"gemini"'

# Test set/delete cycle
response=$(curl -s --max-time 5 -X POST "$BASE_URL/api/keychain/set" \
    -H "Content-Type: application/json" \
    -d '{"provider":"deepgram","key":"test-key-12345"}')
test_contains "POST /api/keychain/set (deepgram)" "$response" '"success"'

response=$(curl -s --max-time 5 -X POST "$BASE_URL/api/keychain/get" \
    -H "Content-Type: application/json" \
    -d '{"provider":"deepgram"}')
test_contains "POST /api/keychain/get (verify)" "$response" '"isConfigured" : true'

response=$(curl -s --max-time 5 -X POST "$BASE_URL/api/keychain/delete" \
    -H "Content-Type: application/json" \
    -d '{"provider":"deepgram"}')
test_contains "POST /api/keychain/delete" "$response" '"success"'

# ═══════════════════════════════════════════════════════
# MODELS
# ═══════════════════════════════════════════════════════
log_section "Transcription Models"

response=$(curl -s --max-time 5 "$BASE_URL/api/transcribe/models")
test_contains "GET /api/transcribe/models" "$response" '"models"'
test_contains "  - has whisper-1" "$response" '"whisper-1"'
test_contains "  - has gpt-4o-mini-transcribe" "$response" '"gpt-4o-mini-transcribe"'
test_contains "  - has gemini" "$response" '"gemini-2.5-flash-lite"'

# ═══════════════════════════════════════════════════════
# RECORDING STATUS
# ═══════════════════════════════════════════════════════
log_section "Recording"

response=$(curl -s --max-time 5 "$BASE_URL/api/recording/status")
test_contains "GET /api/recording/status" "$response" '"isRecording"'

# ═══════════════════════════════════════════════════════
# MEETINGS
# ═══════════════════════════════════════════════════════
log_section "Meetings"

response=$(curl -s --max-time 5 "$BASE_URL/api/meetings")
test_contains "GET /api/meetings" "$response" '"meetings"'

# ═══════════════════════════════════════════════════════
# AUDIO UTILITIES
# ═══════════════════════════════════════════════════════
log_section "Audio Utilities"

response=$(curl -s --max-time 5 -X POST "$BASE_URL/api/audio/needs-compression" \
    -H "Content-Type: application/json" \
    -d '{"filePath":"/nonexistent.wav"}')
test_contains "POST /api/audio/needs-compression" "$response" '"needsCompression"'

# ═══════════════════════════════════════════════════════
# ERROR HANDLING
# ═══════════════════════════════════════════════════════
log_section "Error Handling"

response=$(curl -s --max-time 5 "$BASE_URL/api/nonexistent")
test_contains "GET /nonexistent → 404" "$response" '"Not found"'

response=$(curl -s --max-time 5 -X POST "$BASE_URL/api/silence/detect" \
    -H "Content-Type: application/json" \
    -d '{}')
test_contains "POST /api/silence/detect (missing param)" "$response" '"error"'

# ═══════════════════════════════════════════════════════
# REAL VALIDATION: SILENCE DETECTION
# ═══════════════════════════════════════════════════════
log_section "Silence Detection Validation"

# Create test audio: 2s speech, 3s silence, 2s speech (7 seconds total)
TEST_AUDIO="/tmp/test_silence_detection.wav"
python3 -c "
import wave, struct, math

sample_rate = 16000
with wave.open('$TEST_AUDIO', 'w') as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(sample_rate)

    # 2 seconds of 440Hz tone (speech simulation)
    for i in range(sample_rate * 2):
        sample = int(10000 * math.sin(2 * math.pi * 440 * i / sample_rate))
        w.writeframes(struct.pack('<h', sample))

    # 3 seconds of silence
    for i in range(sample_rate * 3):
        w.writeframes(struct.pack('<h', 0))

    # 2 seconds of 440Hz tone (speech simulation)
    for i in range(sample_rate * 2):
        sample = int(10000 * math.sin(2 * math.pi * 440 * i / sample_rate))
        w.writeframes(struct.pack('<h', sample))
" 2>/dev/null

if [ -f "$TEST_AUDIO" ]; then
    # Test 1: Verify duration is ~7 seconds
    response=$(curl -s --max-time 10 -X POST "$BASE_URL/api/audio/duration" \
        -H "Content-Type: application/json" \
        -d "{\"filePath\":\"$TEST_AUDIO\"}")

    duration=$(echo "$response" | grep -o '"durationSeconds" *: *[0-9.]*' | grep -o '[0-9.]*$')
    if [ -n "$duration" ]; then
        # Check if duration is between 6.5 and 7.5 seconds
        is_valid=$(python3 -c "print('yes' if 6.5 <= float('$duration') <= 7.5 else 'no')")
        if [ "$is_valid" = "yes" ]; then
            log_pass "Duration is correct (~7s, got ${duration}s)"
        else
            log_fail "Duration incorrect (expected ~7s, got ${duration}s)"
        fi
    else
        log_fail "Could not parse duration from response"
    fi

    # Test 2: Detect the 3-second silence (with 2s min threshold)
    response=$(curl -s --max-time 30 -X POST "$BASE_URL/api/silence/detect" \
        -H "Content-Type: application/json" \
        -d "{\"audioPath\":\"$TEST_AUDIO\",\"threshold\":-30,\"minDuration\":2.0}")

    if echo "$response" | grep -q '"success" *: *true'; then
        # Check that we found exactly 1 silence region
        count=$(echo "$response" | grep -o '"count" *: *[0-9]*' | grep -o '[0-9]*$')
        if [ "$count" = "1" ]; then
            log_pass "Found exactly 1 silence region (correct)"

            # Verify silence is around 2-5 seconds (started at 2s, ended at 5s)
            start=$(echo "$response" | grep -o '"start" *: *[0-9.]*' | head -1 | grep -o '[0-9.]*$')
            end=$(echo "$response" | grep -o '"end" *: *[0-9.]*' | head -1 | grep -o '[0-9.]*$')

            if [ -n "$start" ] && [ -n "$end" ]; then
                start_ok=$(python3 -c "print('yes' if 1.5 <= float('$start') <= 2.5 else 'no')")
                end_ok=$(python3 -c "print('yes' if 4.5 <= float('$end') <= 5.5 else 'no')")

                if [ "$start_ok" = "yes" ] && [ "$end_ok" = "yes" ]; then
                    log_pass "Silence timing correct (start: ${start}s, end: ${end}s)"
                else
                    log_fail "Silence timing wrong (start: ${start}s, end: ${end}s, expected ~2-5s)"
                fi
            else
                log_fail "Could not parse silence start/end times"
            fi
        elif [ -z "$count" ]; then
            log_fail "Could not parse silence count"
        else
            log_fail "Found $count silences (expected 1)"
        fi
    else
        log_fail "Silence detection failed"
        echo "      Response: $(echo "$response" | head -c 300)"
    fi

    rm -f "$TEST_AUDIO"
else
    log_fail "Could not create test audio file"
fi

# ═══════════════════════════════════════════════════════
# REAL VALIDATION: COMPRESSION
# ═══════════════════════════════════════════════════════
log_section "Compression Validation"

# Create a larger test file (~500KB WAV)
TEST_LARGE="/tmp/test_large_audio.wav"
python3 -c "
import wave, struct, math, random

sample_rate = 16000
duration_sec = 30  # 30 seconds
with wave.open('$TEST_LARGE', 'w') as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(sample_rate)

    for i in range(sample_rate * duration_sec):
        # Mix of tones + noise to simulate speech
        t = i / sample_rate
        sample = int(5000 * (
            math.sin(2 * math.pi * 300 * t) +
            0.5 * math.sin(2 * math.pi * 600 * t) +
            0.3 * (random.random() - 0.5)
        ))
        sample = max(-32767, min(32767, sample))
        w.writeframes(struct.pack('<h', sample))
" 2>/dev/null

if [ -f "$TEST_LARGE" ]; then
    # Get original file size
    orig_size=$(stat -f%z "$TEST_LARGE" 2>/dev/null || stat -c%s "$TEST_LARGE" 2>/dev/null)
    log_pass "Created test file: ${orig_size} bytes (~$((orig_size / 1024))KB)"

    # Test needs-compression (should return false for small file)
    response=$(curl -s --max-time 10 -X POST "$BASE_URL/api/audio/needs-compression" \
        -H "Content-Type: application/json" \
        -d "{\"filePath\":\"$TEST_LARGE\"}")

    needs=$(echo "$response" | grep -o '"needsCompression" *: *[a-z]*' | grep -o '[a-z]*$')
    if [ "$needs" = "false" ]; then
        log_pass "Correctly reports no compression needed (<25MB)"
    else
        log_fail "Incorrect needs-compression result: $needs"
    fi

    # Test estimate-size
    response=$(curl -s --max-time 10 -X POST "$BASE_URL/api/audio/estimate-size" \
        -H "Content-Type: application/json" \
        -d "{\"inputPath\":\"$TEST_LARGE\",\"level\":0}")

    if echo "$response" | grep -q '"estimatedSizeBytes"'; then
        est_size=$(echo "$response" | grep -o '"estimatedSizeBytes" *: *[0-9]*' | grep -o '[0-9]*$')
        if [ -n "$est_size" ] && [ "$est_size" -lt "$orig_size" ]; then
            log_pass "Estimated compressed size ($est_size bytes) < original ($orig_size bytes)"
        else
            log_fail "Estimated size not smaller than original"
        fi
    else
        log_fail "Could not get estimated size"
    fi

    rm -f "$TEST_LARGE"
else
    log_fail "Could not create large test file"
fi

# ═══════════════════════════════════════════════════════
# REAL VALIDATION: KEYCHAIN ROUND-TRIP
# ═══════════════════════════════════════════════════════
log_section "Keychain Validation"

# Test that we can save, read, and delete a key correctly
TEST_KEY="test-key-$(date +%s)"

# Save
response=$(curl -s --max-time 5 -X POST "$BASE_URL/api/keychain/set" \
    -H "Content-Type: application/json" \
    -d "{\"provider\":\"deepgram\",\"key\":\"$TEST_KEY\"}")

if echo "$response" | grep -q '"success" *: *true'; then
    log_pass "Saved test key to keychain"

    # Verify it's configured
    response=$(curl -s --max-time 5 -X POST "$BASE_URL/api/keychain/get" \
        -H "Content-Type: application/json" \
        -d '{"provider":"deepgram"}')

    if echo "$response" | grep -q '"isConfigured" *: *true'; then
        log_pass "Key verified as configured"
    else
        log_fail "Key not showing as configured after save"
    fi

    # Delete
    response=$(curl -s --max-time 5 -X POST "$BASE_URL/api/keychain/delete" \
        -H "Content-Type: application/json" \
        -d '{"provider":"deepgram"}')

    if echo "$response" | grep -q '"success" *: *true'; then
        log_pass "Deleted test key from keychain"

        # Verify it's gone
        response=$(curl -s --max-time 5 -X POST "$BASE_URL/api/keychain/get" \
            -H "Content-Type: application/json" \
            -d '{"provider":"deepgram"}')

        if echo "$response" | grep -q '"isConfigured" *: *false'; then
            log_pass "Key verified as deleted"
        else
            log_fail "Key still showing as configured after delete"
        fi
    else
        log_fail "Failed to delete test key"
    fi
else
    log_fail "Failed to save test key"
fi

# ═══════════════════════════════════════════════════════
# BASIC ENDPOINT TESTS (kept from before)
# ═══════════════════════════════════════════════════════
log_section "Basic Endpoint Tests"

response=$(curl -s --max-time 5 "$BASE_URL/api/transcribe/models")
model_count=$(echo "$response" | grep -o '"id"' | wc -l | tr -d ' ')
if [ "$model_count" -ge 4 ]; then
    log_pass "Models endpoint returns $model_count models (expected ≥4)"
else
    log_fail "Models endpoint returns only $model_count models (expected ≥4)"
fi

response=$(curl -s --max-time 5 "$BASE_URL/api/recording/status")
test_contains "Recording status endpoint" "$response" '"isRecording"'

response=$(curl -s --max-time 5 "$BASE_URL/api/meetings")
test_contains "Meetings endpoint" "$response" '"meetings"'

# ═══════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════
echo ""
echo "════════════════════════════════════════════════════"
TOTAL=$((PASSED + FAILED))
if [ $FAILED -eq 0 ]; then
    echo -e "  ${GREEN}All $TOTAL tests passed!${NC}"
else
    echo -e "  ${GREEN}Passed: $PASSED${NC}  ${RED}Failed: $FAILED${NC}  Total: $TOTAL"
fi
echo "════════════════════════════════════════════════════"

[ $FAILED -gt 0 ] && exit 1
exit 0
