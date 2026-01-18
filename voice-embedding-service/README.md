# Voice Embedding Service

A lightweight FastAPI service for extracting and comparing speaker voice embeddings using pyannote.audio.

## Features

- **Extract embeddings**: Get 256-dimensional speaker embeddings from audio files
- **Compare speakers**: Compute cosine similarity between embeddings
- **Multiple formats**: Supports wav, mp3, m4a, ogg, flac, and any format ffmpeg can decode
- **Simple auth**: API key authentication via header
- **One-click deploy**: Dockerfile ready for Railway/Fly.io

## Quick Start

### Prerequisites

1. **HuggingFace Token**: Required to download the pyannote model
   - Create account at https://huggingface.co
   - Generate token at https://huggingface.co/settings/tokens
   - Accept model terms at https://huggingface.co/pyannote/embedding

### Local Development

```bash
# Clone and navigate
cd voice-embedding-service

# Create virtual environment
python3.11 -m venv venv
source venv/bin/activate  # or `venv\Scripts\activate` on Windows

# Install dependencies
pip install -r requirements.txt

# Set environment variables
export HF_TOKEN="your-huggingface-token"
export API_KEY="your-secret-api-key"

# Run the server
python main.py
```

Server starts at `http://localhost:8000`

### API Documentation

Once running, visit:
- Swagger UI: http://localhost:8000/docs
- ReDoc: http://localhost:8000/redoc

## API Endpoints

### `GET /health`
Health check - no authentication required.

```bash
curl http://localhost:8000/health
```

Response:
```json
{
  "status": "healthy",
  "model_loaded": true,
  "version": "1.0.0"
}
```

### `POST /extract-embedding`
Extract embedding from base64-encoded audio.

```bash
# Encode audio file to base64
AUDIO_B64=$(base64 -i sample.wav)

curl -X POST http://localhost:8000/extract-embedding \
  -H "Content-Type: application/json" \
  -H "X-API-Key: your-secret-api-key" \
  -d "{\"audio_base64\": \"$AUDIO_B64\", \"format\": \"wav\"}"
```

Response:
```json
{
  "embedding": [0.123, -0.456, ...],  // 256 floats
  "dimension": 256
}
```

### `POST /extract-embedding/upload`
Extract embedding from uploaded file (multipart form).

```bash
curl -X POST http://localhost:8000/extract-embedding/upload \
  -H "X-API-Key: your-secret-api-key" \
  -F "file=@sample.wav"
```

### `POST /compare-embeddings`
Compare two embeddings and get similarity score.

```bash
curl -X POST http://localhost:8000/compare-embeddings \
  -H "Content-Type: application/json" \
  -H "X-API-Key: your-secret-api-key" \
  -d '{
    "embedding1": [0.123, -0.456, ...],
    "embedding2": [0.789, -0.012, ...]
  }'
```

Response:
```json
{
  "similarity": 0.85,
  "is_same_speaker": true
}
```

## Deployment

### Railway (Recommended)

```bash
# Install Railway CLI
npm install -g @railway/cli

# Login and deploy
railway login
railway init
railway up

# Set environment variables in Railway dashboard:
# - HF_TOKEN: your-huggingface-token
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
fly secrets set HF_TOKEN="your-huggingface-token"
fly secrets set API_KEY="your-secret-api-key"

# Deploy
fly deploy
```

### Docker (Self-hosted)

```bash
# Build image
docker build -t voice-embedding-service .

# Run container
docker run -d \
  -p 8000:8000 \
  -e HF_TOKEN="your-huggingface-token" \
  -e API_KEY="your-secret-api-key" \
  -v embedding-cache:/home/appuser/.cache/huggingface \
  voice-embedding-service
```

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `HF_TOKEN` | Yes | - | HuggingFace access token for model download |
| `API_KEY` | Yes | `dev-key-change-me` | API authentication key |
| `PORT` | No | `8000` | Server port |
| `ENV` | No | `production` | Set to `development` for auto-reload |

## Model Details

Uses **pyannote/embedding** model:
- Output: 256-dimensional speaker embedding
- Trained on: VoxCeleb dataset
- Architecture: ResNet-based x-vector
- License: MIT (commercial use allowed)

### Same-Speaker Detection

The service uses a threshold of **0.75** cosine similarity to determine if two embeddings belong to the same speaker. This threshold works well in practice but can be adjusted based on your use case:

- **Higher threshold (0.8+)**: Fewer false positives, may miss some matches
- **Lower threshold (0.7)**: Catch more matches, more false positives

## Usage with Swift (macOS App)

```swift
import Foundation

struct VoiceEmbeddingClient {
    let baseURL: URL
    let apiKey: String

    func extractEmbedding(audioData: Data) async throws -> [Float] {
        var request = URLRequest(url: baseURL.appendingPathComponent("extract-embedding"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")

        let body = ["audio_base64": audioData.base64EncodedString(), "format": "m4a"]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(EmbeddingResponse.self, from: data)
        return response.embedding
    }

    func compareSpeakers(emb1: [Float], emb2: [Float]) async throws -> (similarity: Float, isSameSpeaker: Bool) {
        var request = URLRequest(url: baseURL.appendingPathComponent("compare-embeddings"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")

        let body = ["embedding1": emb1, "embedding2": emb2]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(CompareResponse.self, from: data)
        return (response.similarity, response.isSameSpeaker)
    }
}

struct EmbeddingResponse: Codable {
    let embedding: [Float]
    let dimension: Int
}

struct CompareResponse: Codable {
    let similarity: Float
    let isSameSpeaker: Bool

    enum CodingKeys: String, CodingKey {
        case similarity
        case isSameSpeaker = "is_same_speaker"
    }
}
```

## Performance Notes

- **First request**: ~10-30 seconds (model download + load)
- **Subsequent requests**: ~200-500ms per audio file
- **Memory**: ~500MB for model
- **CPU**: Runs fine on 1 vCPU, faster with 2+
- **GPU**: Not required but speeds up inference if available

## License

MIT
