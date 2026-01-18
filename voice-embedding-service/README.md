# Voice Embedding Service

A lightweight FastAPI service for extracting and comparing speaker voice embeddings using [Resemblyzer](https://github.com/resemble-ai/Resemblyzer).

**No HuggingFace account required!** The model downloads automatically on first run.

## Features

- **Extract embeddings**: Get 256-dimensional speaker embeddings from audio files
- **Compare speakers**: Compute cosine similarity between embeddings
- **Simple auth**: API key authentication via header
- **Zero config**: Model downloads automatically, no tokens needed
- **One-click deploy**: Dockerfile ready for Railway/Fly.io

## Quick Start

### Local Development

```bash
cd voice-embedding-service

# Create virtual environment
python3 -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Set environment variables
export API_KEY="your-secret-api-key"

# Run the server
python main.py
```

Server starts at `http://localhost:8000`

### API Documentation

Once running, visit:
- **Swagger UI**: http://localhost:8000/docs
- **ReDoc**: http://localhost:8000/redoc

---

## API Reference

### Authentication

All endpoints except `/health` require an API key via the `X-API-Key` header.

```bash
curl -H "X-API-Key: your-secret-api-key" http://localhost:8000/extract-embedding
```

---

### `GET /health`

Health check endpoint. No authentication required.

**Response:**
```json
{
  "status": "healthy",
  "model_loaded": true,
  "version": "1.0.0"
}
```

**Example:**
```bash
curl http://localhost:8000/health
```

---

### `POST /extract-embedding`

Extract a 256-dimensional speaker embedding from base64-encoded audio.

**Request Body:**
```json
{
  "audio_base64": "UklGRi...",  // Base64-encoded audio file
  "format": "wav"               // Optional: audio format hint (default: "wav")
}
```

**Response:**
```json
{
  "embedding": [0.123, -0.456, 0.789, ...],  // 256 floats
  "dimension": 256
}
```

**Example:**
```bash
# Encode audio file to base64
AUDIO_B64=$(base64 -i sample.wav)

curl -X POST http://localhost:8000/extract-embedding \
  -H "Content-Type: application/json" \
  -H "X-API-Key: your-secret-api-key" \
  -d "{\"audio_base64\": \"$AUDIO_B64\", \"format\": \"wav\"}"
```

---

### `POST /extract-embedding/upload`

Extract embedding from an uploaded audio file (multipart form).

**Request:** Multipart form with `file` field containing the audio file.

**Response:**
```json
{
  "embedding": [0.123, -0.456, 0.789, ...],
  "dimension": 256
}
```

**Example:**
```bash
curl -X POST http://localhost:8000/extract-embedding/upload \
  -H "X-API-Key: your-secret-api-key" \
  -F "file=@sample.wav"
```

---

### `POST /compare-embeddings`

Compare two speaker embeddings and get a similarity score.

**Request Body:**
```json
{
  "embedding1": [0.123, -0.456, ...],  // 256-dim vector
  "embedding2": [0.789, -0.012, ...]   // 256-dim vector
}
```

**Response:**
```json
{
  "similarity": 0.85,        // Cosine similarity: -1 to 1
  "is_same_speaker": true    // true if similarity > 0.75
}
```

**Example:**
```bash
curl -X POST http://localhost:8000/compare-embeddings \
  -H "Content-Type: application/json" \
  -H "X-API-Key: your-secret-api-key" \
  -d '{
    "embedding1": [0.1, 0.2, ...],
    "embedding2": [0.1, 0.2, ...]
  }'
```

---

## Deployment

### Railway (Recommended)

```bash
# Install Railway CLI
npm install -g @railway/cli

# Login and initialize
railway login
railway init

# Deploy
railway up

# Set environment variables in Railway dashboard:
# - API_KEY: your-secret-api-key
```

### Fly.io

```bash
# Install Fly CLI
curl -L https://fly.io/install.sh | sh

# Login and launch
fly auth login
fly launch --name voice-embedding-service

# Set secrets
fly secrets set API_KEY="your-secret-api-key"

# Deploy
fly deploy
```

### Docker

```bash
# Build image
docker build -t voice-embedding-service .

# Run container
docker run -d \
  -p 8000:8000 \
  -e API_KEY="your-secret-api-key" \
  -v embedding-cache:/root/.cache \
  voice-embedding-service
```

### Docker Compose

```yaml
version: '3.8'
services:
  voice-embedding:
    build: .
    ports:
      - "8000:8000"
    environment:
      - API_KEY=your-secret-api-key
    volumes:
      - model-cache:/root/.cache
    restart: unless-stopped

volumes:
  model-cache:
```

---

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `API_KEY` | Yes | `dev-key-change-me` | API authentication key |
| `PORT` | No | `8000` | Server port |
| `ENV` | No | `production` | Set to `development` for auto-reload |

---

## Usage Examples

### Python Client

```python
import base64
import requests

BASE_URL = "http://localhost:8000"
API_KEY = "your-secret-api-key"
HEADERS = {"X-API-Key": API_KEY}

def extract_embedding(audio_path: str) -> list[float]:
    """Extract embedding from audio file."""
    with open(audio_path, "rb") as f:
        audio_b64 = base64.b64encode(f.read()).decode()

    response = requests.post(
        f"{BASE_URL}/extract-embedding",
        headers=HEADERS,
        json={"audio_base64": audio_b64, "format": "wav"}
    )
    return response.json()["embedding"]

def compare_speakers(emb1: list, emb2: list) -> dict:
    """Compare two embeddings."""
    response = requests.post(
        f"{BASE_URL}/compare-embeddings",
        headers=HEADERS,
        json={"embedding1": emb1, "embedding2": emb2}
    )
    return response.json()

# Example usage
emb1 = extract_embedding("speaker1.wav")
emb2 = extract_embedding("speaker2.wav")
result = compare_speakers(emb1, emb2)

print(f"Similarity: {result['similarity']:.2f}")
print(f"Same speaker: {result['is_same_speaker']}")
```

### Swift Client (for macOS/iOS)

```swift
import Foundation

struct VoiceEmbeddingClient {
    let baseURL: URL
    let apiKey: String

    init(baseURL: String = "http://localhost:8000", apiKey: String) {
        self.baseURL = URL(string: baseURL)!
        self.apiKey = apiKey
    }

    func extractEmbedding(audioData: Data, format: String = "wav") async throws -> [Float] {
        var request = URLRequest(url: baseURL.appendingPathComponent("extract-embedding"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")

        let body: [String: Any] = [
            "audio_base64": audioData.base64EncodedString(),
            "format": format
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(EmbeddingResponse.self, from: data)
        return response.embedding
    }

    func compareSpeakers(emb1: [Float], emb2: [Float]) async throws -> CompareResult {
        var request = URLRequest(url: baseURL.appendingPathComponent("compare-embeddings"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")

        let body: [String: Any] = ["embedding1": emb1, "embedding2": emb2]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(CompareResult.self, from: data)
    }
}

struct EmbeddingResponse: Codable {
    let embedding: [Float]
    let dimension: Int
}

struct CompareResult: Codable {
    let similarity: Float
    let isSameSpeaker: Bool

    enum CodingKeys: String, CodingKey {
        case similarity
        case isSameSpeaker = "is_same_speaker"
    }
}
```

### cURL Examples

```bash
# Health check
curl http://localhost:8000/health

# Extract embedding from file
curl -X POST http://localhost:8000/extract-embedding/upload \
  -H "X-API-Key: your-api-key" \
  -F "file=@audio.wav"

# Extract embedding from base64
curl -X POST http://localhost:8000/extract-embedding \
  -H "Content-Type: application/json" \
  -H "X-API-Key: your-api-key" \
  -d '{"audio_base64": "UklGRi...", "format": "wav"}'

# Compare two embeddings
curl -X POST http://localhost:8000/compare-embeddings \
  -H "Content-Type: application/json" \
  -H "X-API-Key: your-api-key" \
  -d '{"embedding1": [...], "embedding2": [...]}'
```

---

## Model Details

Uses **Resemblyzer** with a pre-trained speaker encoder:

| Property | Value |
|----------|-------|
| Output dimension | 256 |
| Model architecture | LSTM-based d-vector |
| Training data | VoxCeleb, LibriSpeech |
| License | Apache 2.0 |

### Same-Speaker Detection

The default threshold of **0.75** cosine similarity works well for most cases:

| Threshold | Use Case |
|-----------|----------|
| 0.80+ | High confidence, fewer false positives |
| 0.75 | Balanced (default) |
| 0.70 | More permissive, may have false positives |

---

## Performance

| Metric | Value |
|--------|-------|
| First request | ~5-10 seconds (model download) |
| Subsequent requests | ~100-300ms per audio file |
| Memory usage | ~200MB |
| CPU | Works on 1 vCPU |

---

## Testing

```bash
# Run all tests
pytest test_main.py -v

# Run with integration tests (downloads real model)
RUN_INTEGRATION_TESTS=true pytest test_main.py -v

# Run only unit tests (no model needed)
pytest test_main.py -v -k "not Integration"
```

---

## Troubleshooting

### "Model not found" error
The model downloads automatically on first request. Ensure you have internet access.

### Audio format issues
The service accepts WAV files. For other formats, convert first:
```bash
ffmpeg -i input.mp3 -ar 16000 -ac 1 output.wav
```

### Memory issues
The model uses ~200MB RAM. Ensure your container has at least 512MB available.

---

## License

MIT
